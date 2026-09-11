# frozen_string_literal: true

require_relative "../model/project_data"

module DN1Code
  module ExportPdf2
    module Service
      module ObserverService
        @app_observer          = nil
        @model_observer        = nil
        @attached_models       = {}
        @session_opened_models = {}

        class << self
          attr_accessor :session_opened_models
        end

        class AppObserverHandler < (defined?(Sketchup::AppObserver) ? Sketchup::AppObserver : Object)
          def onNewModel(model)
            ObserverService.attach_model_observer(model)
            if defined?(OverlayService)
              OverlayService.on_model_opened(model)
            end
            Dialog::ExportDialog.refresh_if_open(model) if defined?(Dialog::ExportDialog)
          end

          def onOpenModel(model)
            ObserverService.attach_model_observer(model)
            # Сбрасываем кэш сессии для только что открытой модели, чтобы повторная обработка не блокировалась
            if model && model.respond_to?(:path) && !model.path.to_s.empty?
              clean_p = model.path.to_s.tr("\\", "/").downcase
              ObserverService.session_opened_models.delete(clean_p)
            end

            # В SketchUp на Windows при onOpenModel данные модели могут инициализироваться асинхронно
            if defined?(UI) && UI.respond_to?(:start_timer)
              UI.start_timer(0.05, false) do
                active = defined?(Sketchup) && Sketchup.respond_to?(:active_model) ? (Sketchup.active_model || model) : model
                ObserverService.handle_model_opened(active, true)
              end
            else
              ObserverService.handle_model_opened(model, true)
            end
          end

          def onActivateModel(model)
            ObserverService.attach_model_observer(model)
            if defined?(UI) && UI.respond_to?(:start_timer)
              UI.start_timer(0.05, false) do
                active = defined?(Sketchup) && Sketchup.respond_to?(:active_model) ? (Sketchup.active_model || model) : model
                ObserverService.handle_model_opened(active, false)
              end
            else
              ObserverService.handle_model_opened(model, false)
            end
          end

          def onPreSaveModel(model)
            ObserverService.handle_pre_save(model)
          end

          def onPostSaveModel(model)
            ObserverService.handle_post_save(model)
          end

          def onSaveModel(model)
            ObserverService.handle_post_save(model)
          end
        end

        class ModelObserverHandler < (defined?(Sketchup::ModelObserver) ? Sketchup::ModelObserver : Object)
          def onPreSaveModel(model)
            ObserverService.handle_pre_save(model)
          end

          def onPostSaveModel(model)
            ObserverService.handle_post_save(model)
          end

          def onSaveModel(model)
            ObserverService.handle_post_save(model)
          end
        end

        class << self
          def register!
            return unless defined?(Sketchup)

            # Регистрация AppObserver
            if Sketchup.respond_to?(:add_observer)
              @app_observer ||= AppObserverHandler.new
              Sketchup.add_observer(@app_observer)
            end

            # Прикрепление к текущей активной модели и инициализация сессии открытия
            if Sketchup.respond_to?(:active_model) && Sketchup.active_model
              model = Sketchup.active_model
              attach_model_observer(model)
              handle_model_opened(model, false) if model.respond_to?(:path) && !model.path.to_s.empty?
            end
          end

          def attach_model_observer(model)
            return unless model && model.respond_to?(:add_observer)

            # Предотвращение повторного прикрепления наблюдателя к одной и той же модели
            model_id = model.object_id
            return if @attached_models[model_id]

            @model_observer ||= ModelObserverHandler.new
            model.add_observer(@model_observer)
            @attached_models[model_id] = true
          end

          # Обработка открытия модели: загрузка настроек проекта и синхронизация данных.
          # Параметр force позволяет принудительно повторить обработку для уже открытой в сессии модели.
          def handle_model_opened(model, force = false)
            return unless model

            model_path = model.respond_to?(:path) ? model.path.to_s.tr("\\", "/") : ""
            return if model_path.empty?

            norm_path = model_path.downcase
            # Если модель уже обработана в текущей сессии SketchUp и не запрошен принудительный инкремент
            return if @session_opened_models[norm_path] && !force

            @session_opened_models[norm_path] = true

            project_data = Model::ProjectData.new
            project_data.load_auto(model)

            # Актуализация оверлея с открытой моделью (4:3 если в файле не сохранено другое)
            if defined?(OverlayService)
              OverlayService.on_model_opened(model, project_data)
            end

            # Историю правок автоматически не создаем при открытии модели
            Dialog::ExportDialog.refresh_if_open(model) if defined?(Dialog::ExportDialog)

            if defined?(Sketchup) && Sketchup.respond_to?(:status_text=)
              yaml_name = project_data.yaml_filename(model)
              rev = project_data.project_info[:revision]
              Sketchup.status_text = "DN1C Export PDF: Открыт проект #{yaml_name} (Ревизия r#{sprintf('%03d', rev)})"
            end
          rescue StandardError => e
            warn "[DN1C Export PDF] Ошибка при автозагрузке проекта: #{e.message}"
          end

          # Обработка перед сохранением: сохранение в словарь атрибутов модели
          def handle_pre_save(model)
            return unless model

            project_data = Model::ProjectData.new
            has_data = project_data.load_from_model(model)
            project_data.load_auto(model) unless has_data
            project_data.sync_with_model_scenes(model)
            project_data.save_to_model(model)
          rescue StandardError => e
            warn "[DN1C Export PDF] Ошибка при pre-save синхронизации: #{e.message}"
          end

          # Обработка после сохранения: сохранение YAML рядом с файлом SketchUp
          def handle_post_save(model)
            return unless model && model.respond_to?(:path) && !model.path.to_s.empty?

            project_data = Model::ProjectData.new
            # Загружаем текущие атрибуты модели
            project_data.load_from_model(model)
            project_data.sync_with_model_scenes(model)

            # Сохраняем в библиотеку модели и в YAML файл рядом с SKP
            project_data.save_auto(model)

            yaml_name = project_data.yaml_filename(model)
            if defined?(Sketchup) && Sketchup.respond_to?(:status_text=)
              Sketchup.status_text = "DN1C Export PDF: Конфигурация сохранена (#{yaml_name})"
            end
          rescue StandardError => e
            warn "[DN1C Export PDF] Ошибка при автосохранении YAML: #{e.message}"
          end
        end
      end
    end
  end
end
