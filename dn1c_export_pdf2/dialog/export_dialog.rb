# frozen_string_literal: true

require "json"
require_relative "../model/project_data"
require_relative "../controller/export_controller"

module DN1Code
  module ExportPdf2
    module Dialog
      class ExportDialog
        DIALOG_ID = "DN1C_ExportPdf2_Dialog"
        @dialog = nil

        def self.refresh_if_open(model = nil)
          if @dialog && @dialog.visible?
            model ||= (defined?(Sketchup) ? Sketchup.active_model : nil)
            return unless model

            Service::ObserverService.handle_model_opened(model, false) if defined?(Service::ObserverService)

            project_data = Model::ProjectData.new
            project_data.load_auto(model)

            json_str = JSON.generate(project_data.to_h)
            @dialog.execute_script("window.app && window.app.loadData(#{json_str});")
          end
        end

        def self.show_dialog
          model = (defined?(Sketchup) && Sketchup.respond_to?(:active_model)) ? Sketchup.active_model : nil
          if model && model.respond_to?(:path) && !model.path.to_s.empty?
            Service::ObserverService.handle_model_opened(model, false) if defined?(Service::ObserverService)
          end

          if @dialog && @dialog.visible?
            @dialog.bring_to_front
            refresh_if_open(model)
            return
          end

          options = {
            dialog_title:    "DN1C Export PDF 2 — Экспорт сцен в PDF",
            preferences_key: "DN1C_ExportPdf2_Pref",
            scrollable:      true,
            resizable:       true,
            width:           860,
            height:          680,
            left:            150,
            top:             100,
            min_width:       650,
            min_height:      500,
            style:           UI::HtmlDialog::STYLE_DIALOG
          }

          @dialog = UI::HtmlDialog.new(options)
          html_path = File.join(__dir__, "html", "index.html")
          @dialog.set_file(html_path)

          setup_callbacks(@dialog)
          @dialog.show
        end

        def self.setup_callbacks(dialog)
          # Загрузка данных проекта в веб-интерфейс (первично YAML, вторично библиотека модели)
          dialog.add_action_callback("getData") do |_action_context|
            model = Sketchup.active_model
            if model && model.respond_to?(:path) && !model.path.to_s.empty?
              Service::ObserverService.handle_model_opened(model, false) if defined?(Service::ObserverService)
            end

            project_data = Model::ProjectData.new
            project_data.load_auto(model)

            json_str = JSON.generate(project_data.to_h)
            dialog.execute_script("window.app && window.app.loadData(#{json_str});")
          end

          # Обновить все данные во всех хранилищах (модель, сцены, YAML)
          dialog.add_action_callback("refreshData") do |_action_context, data_json|
            begin
              payload = JSON.parse(data_json, symbolize_names: true)
              model = Sketchup.active_model
              project_data = Model::ProjectData.new
              project_data.project_info.merge!(payload[:project_info]) if payload[:project_info]
              project_data.pdf_settings.merge!(payload[:pdf_settings]) if payload[:pdf_settings]
              project_data.history = payload[:history] if payload[:history]

              if payload[:scenes].is_a?(Array)
                project_data.scenes = payload[:scenes].map { |h| Model::SceneItem.from_h(h) }
              end

              # Синхронизация сцен из активной модели
              project_data.sync_with_model_scenes(model)

              # Сохранение во все хранилища (библиотека модели + YAML файл)
              project_data.save_auto(model)

              yaml_name = project_data.yaml_filename(model)

              # Обновляем UI свежими данными
              refreshed_json = JSON.generate(project_data.to_h)
              dialog.execute_script("window.app && window.app.loadData(#{refreshed_json});")
              dialog.execute_script("window.app && window.app.showNotification('Все данные и YAML (#{yaml_name}) успешно обновлены', 'success');")

              if defined?(Sketchup) && Sketchup.respond_to?(:status_text=)
                Sketchup.status_text = "DN1C Export PDF: Все данные и YAML (#{yaml_name}) обновлены"
              end
            rescue StandardError => e
              dialog.execute_script("window.app && window.app.showNotification('Ошибка обновления: #{e.message}', 'error');")
            end
          end

          # Сохранение настроек из веб-интерфейса (в библиотеку модели и в YAML файл)
          dialog.add_action_callback("saveData") do |_action_context, data_json|
            begin
              payload = JSON.parse(data_json, symbolize_names: true)
              model = Sketchup.active_model
              project_data = Model::ProjectData.new
              project_data.project_info.merge!(payload[:project_info]) if payload[:project_info]
              project_data.pdf_settings.merge!(payload[:pdf_settings]) if payload[:pdf_settings]
              project_data.history = payload[:history] if payload[:history]

              if payload[:scenes].is_a?(Array)
                project_data.scenes = payload[:scenes].map { |h| Model::SceneItem.from_h(h) }
              end

              project_data.sync_with_model_scenes(model)
              project_data.save_auto(model)
              yaml_name = project_data.yaml_filename(model)
              dialog.execute_script("window.app && window.app.showNotification('Настройки сохранены в библиотеке и YAML (#{yaml_name})', 'success');")
            rescue StandardError => e
              dialog.execute_script("window.app && window.app.showNotification('Ошибка сохранения: #{e.message}', 'error');")
            end
          end

          # Запуск экспорта в PDF
          dialog.add_action_callback("startExport") do |_action_context, data_json|
            begin
              payload = JSON.parse(data_json, symbolize_names: true)
              model = Sketchup.active_model
              project_data = Model::ProjectData.new
              project_data.project_info.merge!(payload[:project_info]) if payload[:project_info]
              project_data.pdf_settings.merge!(payload[:pdf_settings]) if payload[:pdf_settings]
              project_data.history = payload[:history] if payload[:history]

              if payload[:scenes].is_a?(Array)
                project_data.scenes = payload[:scenes].map { |h| Model::SceneItem.from_h(h) }
              end

              project_data.sync_with_model_scenes(model)
              project_data.save_auto(model)

              controller = Controller::ExportController.new(project_data, model)
              
              pdf_file = controller.export do |curr, total, msg|
                percent = (curr.to_f / total * 100).round
                dialog.execute_script("window.app && window.app.updateProgress(#{percent}, #{JSON.generate(msg)});")
              end

              escaped_path = JSON.generate(pdf_file)
              new_rev = project_data.project_info[:revision] || 1
              dialog.execute_script("window.app && window.app.onExportSuccess(#{escaped_path}, #{new_rev});")
            rescue StandardError => e
              dialog.execute_script("window.app && window.app.onExportError(#{JSON.generate(e.message)});")
            end
          end

          # Открыть папку с PDF
          dialog.add_action_callback("openFolder") do |_action_context, file_path|
            if file_path && File.exist?(file_path)
              folder = File.dirname(file_path)
              UI.openURL("file:///#{folder}")
            end
          end

          # Экспорт настроек в YAML
          dialog.add_action_callback("exportYaml") do |_action_context, data_json|
            save_path = UI.savepanel("Экспортировать настройки в YAML", "", "project_config.yaml")
            if save_path
              begin
                payload = JSON.parse(data_json, symbolize_names: true)
                project_data = Model::ProjectData.new
                project_data.project_info.merge!(payload[:project_info]) if payload[:project_info]
                project_data.pdf_settings.merge!(payload[:pdf_settings]) if payload[:pdf_settings]
                project_data.history = payload[:history] if payload[:history]
                if payload[:scenes].is_a?(Array)
                  project_data.scenes = payload[:scenes].map { |h| Model::SceneItem.from_h(h) }
                end

                project_data.save_to_yaml(save_path)
                dialog.execute_script("window.app && window.app.showNotification('YAML успешно сохранен', 'success');")
              rescue StandardError => e
                dialog.execute_script("window.app && window.app.showNotification('Ошибка: #{e.message}', 'error');")
              end
            end
          end

          # Импорт настроек из YAML
          dialog.add_action_callback("importYaml") do |_action_context|
            yaml_file = UI.openpanel("Открыть файл YAML конфигурации", "", "YAML Files|*.yaml;*.yml||")
            if yaml_file && File.exist?(yaml_file)
              project_data = Model::ProjectData.new
              if project_data.load_from_yaml(yaml_file)
                model = Sketchup.active_model
                project_data.sync_with_model_scenes(model)
                json_str = JSON.generate(project_data.to_h)
                dialog.execute_script("window.app && window.app.loadData(#{json_str});")
                dialog.execute_script("window.app && window.app.showNotification('Настройки загружены из YAML', 'success');")
              end
            end
          end
        end
      end
    end
  end
end
