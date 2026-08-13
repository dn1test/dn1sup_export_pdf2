# frozen_string_literal: true

require_relative "../model/project_data"

module DN1Code
  module ExportPdf2
    module Service
      module ObserverService
        @app_observer   = nil
        @model_observer = nil
        @attached_models = {}

        class AppObserverHandler < (defined?(Sketchup::AppObserver) ? Sketchup::AppObserver : Object)
          def onNewModel(model)
            ObserverService.attach_model_observer(model)
          end

          def onOpenModel(model)
            ObserverService.attach_model_observer(model)
            ObserverService.handle_model_opened(model)
          end

          def onActivateModel(model)
            ObserverService.attach_model_observer(model)
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

            # Прикрепление к текущей активной модели
            if Sketchup.respond_to?(:active_model) && Sketchup.active_model
              attach_model_observer(Sketchup.active_model)
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

          # Обработка открытия модели: загрузка настроек (YAML первично, библиотека вторично)
          def handle_model_opened(model)
            return unless model

            project_data = Model::ProjectData.new
            project_data.load_auto(model)
          rescue StandardError => e
            warn "[DN1C Export PDF] Ошибка при автозагрузке проекта: #{e.message}"
          end

          # Обработка перед сохранением: сохранение в словарь атрибутов модели
          def handle_pre_save(model)
            return unless model

            project_data = Model::ProjectData.new
            project_data.load_from_model(model)
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
