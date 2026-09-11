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
            width:           980,
            height:          700,
            left:            120,
            top:             80,
            min_width:       720,
            min_height:      520,
            style:           UI::HtmlDialog::STYLE_DIALOG
          }

          @dialog = UI::HtmlDialog.new(options)
          html_path = File.join(__dir__, "html", "index.html")
          @dialog.set_file(html_path)

          setup_callbacks(@dialog)
          @dialog.show
        end

        def self.populate_project_data(project_data, payload)
          return unless payload.is_a?(Hash)

          if payload[:project].is_a?(Hash)
            project_data.project.merge!(payload[:project])
          end
          if payload[:customer].is_a?(Hash)
            project_data.customer.merge!(payload[:customer])
          end
          if payload[:workflow].is_a?(Hash)
            project_data.workflow.merge!(payload[:workflow])
          end

          info_src = payload[:project] || payload[:project_info]
          project_data.project_info.merge!(info_src) if info_src

          if payload.key?(:api_targets) && payload[:api_targets].is_a?(Array)
            project_data.api_targets = payload[:api_targets].map(&:to_s).map(&:strip).reject(&:empty?)
          end
          project_data.directories = payload[:directories] if payload[:directories]
          project_data.pdf_settings.merge!(payload[:pdf_settings]) if payload[:pdf_settings]
          if payload[:history_edit] && payload[:history_edit].is_a?(Array)
            project_data.history = payload[:history_edit]
          elsif payload[:history]
            project_data.history = payload[:history]
          end

          if payload[:scenes].is_a?(Array)
            project_data.scenes = payload[:scenes].map { |h| Model::SceneItem.from_h(h) }
          end

          project_data.sync_project_fields!
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
            if defined?(Service::OverlayService)
              project_data.pdf_settings[:show_aspect_overlay] = Service::OverlayService.overlay_active?(model)
            end

            json_str = JSON.generate(project_data.to_h)
            dialog.execute_script("window.app && window.app.loadData(#{json_str});")
          end

          # Переключение видимости рамки пропорций кадра через Sketchup::Overlay
          dialog.add_action_callback("toggleAspectOverlay") do |_action_context, enabled_val|
            puts ">>> [CALLBACK toggleAspectOverlay]: enabled_val=#{enabled_val.inspect}"
            model = Sketchup.active_model
            is_on = enabled_val == true || enabled_val.to_s == "true"
            if defined?(Service::OverlayService)
              if is_on
                Service::OverlayService.enable(model)
              else
                Service::OverlayService.disable(model)
              end
              Model::ProjectData.save_default_frame_settings(show_aspect_overlay: is_on) if defined?(Model::ProjectData)
              active = Service::OverlayService.overlay_active?(model)
              dialog.execute_script("window.app && window.app.syncOverlayState && window.app.syncOverlayState(#{active});")
            end
          end

          # Обновление настроек пропорций кадра и перерисовка окна SketchUp
          dialog.add_action_callback("updateAspectSettings") do |_action_context, params_json|
            puts ">>> [CALLBACK updateAspectSettings]: params=#{params_json.inspect}"
            begin
              params = params_json.is_a?(Hash) ? params_json : (JSON.parse(params_json.to_s, symbolize_names: true) rescue {})
              model = Sketchup.active_model
              if defined?(Service::OverlayService)
                Service::OverlayService.update_settings(params, model)
                Model::ProjectData.save_default_frame_settings(params) if defined?(Model::ProjectData)
                info = Service::OverlayService.calculate_target_info(model)
                dialog.execute_script("window.app && window.app.syncOverlayState && window.app.syncOverlayState(true);")
                dialog.execute_script("window.app && window.app.updateAspectInfo && window.app.updateAspectInfo(#{JSON.generate(info)});")
                if defined?(UI) && UI.respond_to?(:start_timer)
                  UI.start_timer(0.02, false) do
                    begin
                      active = Service::OverlayService.overlay_active?(model)
                      dialog.execute_script("window.app && window.app.syncOverlayState && window.app.syncOverlayState(#{active});")
                    rescue StandardError
                    end
                  end
                end
              end
            rescue StandardError
            end
          end

          # Генератор артикула по стандарту CF# / HF#
          dialog.add_action_callback("generateArticul") do |_action_context, params_json|
            commercial = false
            index = 1
            if params_json && !params_json.to_s.empty?
              begin
                parsed = JSON.parse(params_json)
                commercial = parsed["commercial"] == true || parsed["commercial"] == "true" || parsed["commercial"] == 1 || parsed["commercial"] == "1"
                index = parsed["suffix"] || parsed["index"] || "01"
              rescue StandardError
              end
            end
            art = Model::ProjectData.generate_articul(commercial: commercial, index: index, suffix: index)
            dialog.execute_script("window.app && window.app.onArticulGenerated(#{JSON.generate(art)});")
          end

          # Генератор идентификатора заказчика (CUST-...)
          dialog.add_action_callback("generateCustomerId") do |_action_context, name|
            cid = Model::ProjectData.generate_customer_id(name: name)
            dialog.execute_script("window.app && window.app.onCustomerIdGenerated(#{JSON.generate(cid)});")
          end

          # Интерактивный диалог выбора папки проекта в проводнике
          dialog.add_action_callback("selectDirectory") do |_action_context, row_index|
            model = Sketchup.active_model
            default_dir = ""
            if model && model.respond_to?(:path) && !model.path.to_s.empty?
              default_dir = File.dirname(model.path)
            end

            chosen_folder = UI.select_directory(
              title:     "Выберите рабочую папку проекта",
              directory: default_dir
            )

            if chosen_folder && !chosen_folder.to_s.empty?
              rel_path = chosen_folder
              if !default_dir.empty?
                model_dir_norm = File.expand_path(default_dir).tr("\\", "/")
                chosen_norm    = File.expand_path(chosen_folder).tr("\\", "/")
                if chosen_norm.start_with?(model_dir_norm + "/")
                  rel_path = chosen_norm.sub(model_dir_norm + "/", "")
                elsif chosen_norm == model_dir_norm
                  rel_path = "./"
                end
              end

              idx = row_index.to_i
              dialog.execute_script("window.app && window.app.onDirectorySelected(#{idx}, #{JSON.generate(rel_path)});")
            end
          end

          # Получить список файлов и превью для заданной папки
          dialog.add_action_callback("getFolderFiles") do |_action_context, params_json|
            idx = 0
            folder_raw = ""
            begin
              params = if params_json.is_a?(Hash)
                         params_json
                       elsif params_json.is_a?(String)
                         (JSON.parse(params_json.to_s.force_encoding("UTF-8"), symbolize_names: true) rescue {})
                       else
                         {}
                       end
              idx = (params[:index] || params["index"] || 0).to_i
              folder_raw = (params[:path] || params["path"] || "").to_s.strip
              folder_rel = folder_raw.tr("\\", "/")

              model = Sketchup.active_model
              model_dir = ""
              if model && model.respond_to?(:path) && !model.path.to_s.empty?
                model_dir = File.dirname(model.path.to_s.tr("\\", "/"))
              end

              candidates = []
              candidates << folder_rel if File.directory?(folder_rel)
              candidates << File.expand_path(folder_rel) if File.directory?(File.expand_path(folder_rel))
              if !model_dir.empty?
                c_model = File.expand_path(File.join(model_dir, folder_rel))
                candidates << c_model if File.directory?(c_model)
              end
              c_pwd = File.expand_path(File.join(Dir.pwd, folder_rel))
              candidates << c_pwd if File.directory?(c_pwd)

              parent_dir = File.expand_path(File.join(__dir__, "../../.."))
              c_parent = File.expand_path(File.join(parent_dir, folder_rel))
              candidates << c_parent if File.directory?(c_parent)

              folder_abs = candidates.find { |p| Dir.exist?(p) }
              files_list = []
              exists = !folder_abs.nil?

              if exists
                require "base64" unless defined?(Base64)
                entries = begin
                            Dir.children(folder_abs)
                          rescue StandardError
                            Dir.entries(folder_abs).reject { |n| n == "." || n == ".." }
                          end

                total_b64_bytes = 0
                max_total_b64 = 4_500_000 # 4.5 MB base64 safety limit per folder to avoid CEF IPC stall

                entries.sort.each do |fname|
                  next if fname.start_with?(".") || fname.start_with?("~")
                  f = File.join(folder_abs, fname)
                  next unless File.file?(f)
                  ext = File.extname(f).downcase
                  is_img = %w[.jpg .jpeg .png .webp .bmp .gif].include?(ext)
                  norm_path = f.tr("\\", "/")
                  f_size = begin
                             File.size(f)
                           rescue StandardError
                             0
                           end

                  data_url = nil
                  if is_img && f_size > 0 && f_size <= 2_000_000 && (total_b64_bytes + f_size) <= max_total_b64
                    begin
                      mime = case ext
                             when ".jpg", ".jpeg" then "image/jpeg"
                             when ".png"          then "image/png"
                             when ".webp"         then "image/webp"
                             when ".gif"          then "image/gif"
                             when ".bmp"          then "image/bmp"
                             else "image/jpeg"
                             end
                      b64 = Base64.strict_encode64(File.binread(f))
                      total_b64_bytes += b64.bytesize
                      data_url = "data:#{mime};base64,#{b64}"
                    rescue StandardError
                      data_url = nil
                    end
                  end

                  files_list << {
                    name:     fname,
                    path:     norm_path,
                    url:      data_url || ("file:///" + norm_path),
                    size:     f_size,
                    ext:      ext.sub(/^\./, "").upcase,
                    is_image: is_img
                  }

                  break if files_list.size >= 50 # Limit preview cards to 50 items
                end
              end

              resp = {
                index:     idx,
                path:      folder_raw,
                exists:    exists,
                full_path: folder_abs ? folder_abs.tr("\\", "/") : "",
                files:     files_list
              }
              json_payload = JSON.generate(resp)
              dialog.execute_script("window.app && window.app.onFolderFilesLoaded(#{json_payload});")
            rescue StandardError => e
              puts "[getFolderFiles error]: #{e.message}"
              fallback = { index: idx || 0, path: folder_raw || "", exists: false, full_path: "", files: [], error: e.message }
              dialog.execute_script("window.app && window.app.onFolderFilesLoaded(#{JSON.generate(fallback)});") rescue nil
            end
          end

          # Открыть папку на диске через проводник
          dialog.add_action_callback("openDirectoryPath") do |_action_context, folder_raw|
            begin
              folder_rel = folder_raw.to_s.strip.tr("\\", "/")
              model = Sketchup.active_model
              model_dir = ""
              if model && model.respond_to?(:path) && !model.path.to_s.empty?
                model_dir = File.dirname(model.path.to_s.tr("\\", "/"))
              end

              candidates = []
              candidates << folder_rel if File.directory?(folder_rel)
              candidates << File.expand_path(folder_rel) if File.directory?(File.expand_path(folder_rel))
              if !model_dir.empty?
                c_model = File.expand_path(File.join(model_dir, folder_rel))
                candidates << c_model if File.directory?(c_model)
              end
              c_pwd = File.expand_path(File.join(Dir.pwd, folder_rel))
              candidates << c_pwd if File.directory?(c_pwd)

              parent_dir = File.expand_path(File.join(__dir__, "../../.."))
              c_parent = File.expand_path(File.join(parent_dir, folder_rel))
              candidates << c_parent if File.directory?(c_parent)

              folder_abs = candidates.find { |p| Dir.exist?(p) }

              if folder_abs && File.exist?(folder_abs)
                UI.openURL("file:///#{folder_abs.tr('\\', '/')}")
              else
                UI.messagebox("Папка не найдена на диске:\n#{folder_raw}")
              end
            rescue StandardError => e
              puts "[openDirectoryPath error]: #{e.message}"
            end
          end

          # Обновить все данные во всех хранилищах (модель, сцены, YAML)
          dialog.add_action_callback("refreshData") do |_action_context, data_json|
            begin
              payload = JSON.parse(data_json, symbolize_names: true)
              model = Sketchup.active_model
              project_data = Model::ProjectData.new
              populate_project_data(project_data, payload)

              # Синхронизация сцен из активной модели
              project_data.sync_with_model_scenes(model)

              # Сохранение во все хранилища (библиотека модели + YAML файл + edit_history.yaml)
              project_data.save_auto(model)
              project_data.save_program_settings

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

          # Сохранение данных проекта в YAML рядом с .skp и в атрибуты модели (без файлов настроек плагина)
          dialog.add_action_callback("saveProjectYaml") do |_action_context, data_json|
            begin
              payload = JSON.parse(data_json, symbolize_names: true)
              model = (defined?(Sketchup) && Sketchup.respond_to?(:active_model)) ? Sketchup.active_model : nil
              project_data = Model::ProjectData.new
              populate_project_data(project_data, payload)
              project_data.sync_with_model_scenes(model) if model

              # Определяем прежний артикульный YAML из атрибутов модели (до обновления).
              # Удалять можно только файл, названный по старому артикулу: общие файлы
              # (project_config.yaml, <модель>.yaml и найденные эвристикой) не трогаем
              old_articul_yamls = []
              if model && model.respond_to?(:get_attribute) && model.respond_to?(:path) && !model.path.to_s.empty?
                raw_info = model.get_attribute(Model::ProjectData::ATTR_DICT, "project_info", nil) rescue nil
                if raw_info
                  begin
                    old_art = JSON.parse(raw_info, symbolize_names: true)[:articul].to_s.strip
                    unless old_art.empty?
                      dir = File.dirname(model.path.to_s.tr("\\", "/"))
                      old_articul_yamls << File.join(dir, "#{Model::ProjectData.sanitize_filename(old_art)}.yaml")
                      old_articul_yamls << File.join(dir, "#{Model::ProjectData.sanitize_filename(old_art)}.yml")
                    end
                  rescue StandardError
                  end
                end
              end

              # Сохранение в библиотеку модели (атрибуты)
              project_data.save_to_model(model) if model

              yaml_path = nil
              if model && model.respond_to?(:path) && !model.path.to_s.empty?
                yaml_path = project_data.yaml_path_for_model(model)
                if yaml_path
                  project_data.save_to_yaml(yaml_path, include_settings: false)
                  target_norm = File.expand_path(yaml_path).tr("\\", "/").downcase
                  old_articul_yamls.uniq.each do |old_yaml|
                    next unless File.exist?(old_yaml)

                    old_norm = File.expand_path(old_yaml).tr("\\", "/").downcase
                    File.delete(old_yaml) rescue nil if old_norm != target_norm
                  end
                end
              end

              yaml_name = yaml_path ? File.basename(yaml_path) : project_data.yaml_filename(model)
              dialog.execute_script("window.app && window.app.showNotification('Данные проекта сохранены в #{yaml_name} и в модель SketchUp', 'success');")
              if defined?(Sketchup) && Sketchup.respond_to?(:status_text=)
                Sketchup.status_text = "DN1C Export PDF: Данные проекта сохранены (#{yaml_name})"
              end
            rescue StandardError => e
              dialog.execute_script("window.app && window.app.showNotification('Ошибка сохранения YAML: #{e.message}', 'error');")
            end
          end

          # Сохранение данных проекта только в атрибуты модели (.skp файл не перезаписывается)
          dialog.add_action_callback("saveProjectToSkp") do |_action_context, data_json|
            begin
              payload = JSON.parse(data_json, symbolize_names: true)
              model = (defined?(Sketchup) && Sketchup.respond_to?(:active_model)) ? Sketchup.active_model : nil
              project_data = Model::ProjectData.new
              populate_project_data(project_data, payload)
              project_data.sync_with_model_scenes(model) if model
              project_data.save_to_model(model) if model

              if model
                dialog.execute_script("window.app && window.app.showNotification('Данные проекта записаны в модель SketchUp (сохраните файл Ctrl+S)', 'success');")
              else
                dialog.execute_script("window.app && window.app.showNotification('Нет активной модели SketchUp', 'error');")
              end
            rescue StandardError => e
              dialog.execute_script("window.app && window.app.showNotification('Ошибка записи в модель: #{e.message}', 'error');")
            end
          end

          # Сохранение настроек из веб-интерфейса.
          # Автосейв (is_auto_save/silent) пишет только в библиотеку модели (атрибуты SketchUp),
          # YAML и файлы конфигурации обновляются при явных действиях:
          # кнопка "Обновить" (refreshData), экспорт PDF, сохранение .skp, exportYaml.
          save_handler = lambda do |_action_context, data_json|
            begin
              payload = JSON.parse(data_json, symbolize_names: true)
              model = (defined?(Sketchup) && Sketchup.respond_to?(:active_model)) ? Sketchup.active_model : nil
              project_data = Model::ProjectData.new
              populate_project_data(project_data, payload)

              is_auto = payload[:silent] == true || payload[:is_auto_save] == true

              if is_auto
                if model
                  project_data.sync_with_model_scenes(model)
                  project_data.save_to_model(model)
                end
                dialog.execute_script("window.app && window.app.onAutoSaved && window.app.onAutoSaved(#{JSON.generate("в модель SketchUp")});")
              else
                project_data.sync_with_model_scenes(model) if model
                project_data.save_auto(model) if model
                project_data.save_program_settings
                yaml_name = model ? project_data.yaml_filename(model) : "project.yaml"
                dialog.execute_script("window.app && window.app.showNotification('Настройки сохранены в плагине и файле проекта (#{yaml_name})', 'success');")
              end
            rescue StandardError => e
              dialog.execute_script("window.app && window.app.showNotification('Ошибка сохранения: #{e.message}', 'error');")
            end
          end

          dialog.add_action_callback("saveData", &save_handler)
          dialog.add_action_callback("autoSave", &save_handler)

          dialog.add_action_callback("testProbe") do |_action_context, data_json|
            $test_probe_result = data_json
          end

          # Запуск экспорта в PDF
          dialog.add_action_callback("startExport") do |_action_context, data_json|
            # Экспорт выполняется отложенно через таймер: колбэк CEF завершается сразу,
            # диалог не блокируется и прогресс-бар перерисовывается в реальном времени
            run_export = lambda do
              begin
                payload = JSON.parse(data_json, symbolize_names: true)
                model = Sketchup.active_model
                project_data = Model::ProjectData.new
                populate_project_data(project_data, payload)

                project_data.sync_with_model_scenes(model)
                project_data.save_auto(model)
                project_data.save_program_settings

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

            if defined?(UI) && UI.respond_to?(:start_timer)
              UI.start_timer(0.01, false) { run_export.call }
            else
              # Резерв для окружений без таймера (автономные тесты)
              run_export.call
            end
          end

          # Открыть папку с PDF
          dialog.add_action_callback("openFolder") do |_action_context, file_path|
            if file_path && File.exist?(file_path)
              folder = File.dirname(file_path.to_s.tr("\\", "/"))
              UI.openURL("file:///" + folder)
            end
          end

          # Открыть файл (изображение, документ, чертеж, текст) системной программой по умолчанию
          dialog.add_action_callback("openFile") do |_action_context, file_path|
            begin
              clean_path = file_path.to_s.strip.tr("\\", "/")
              if !clean_path.empty? && File.exist?(clean_path)
                UI.openURL("file:///" + clean_path)
              end
            rescue StandardError => e
              puts "[openFile error]: #{e.message}"
            end
          end

          # Экспорт настроек в YAML
          dialog.add_action_callback("exportYaml") do |_action_context, data_json|
            save_path = UI.savepanel("Экспортировать настройки в YAML", "", "project_config.yaml")
            if save_path
              begin
                payload = JSON.parse(data_json, symbolize_names: true)
                project_data = Model::ProjectData.new
                populate_project_data(project_data, payload)

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
