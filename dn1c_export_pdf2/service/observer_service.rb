# frozen_string_literal: true

require_relative "../model/project_data"
require_relative "../model/session_store"

module DN1Code
  module ExportPdf2
    module Service
      module ObserverService
        @app_observer          = nil
        @session_opened_models = {}

        class << self
          attr_accessor :session_opened_models
        end

        class AppObserverHandler < (defined?(Sketchup::AppObserver) ? Sketchup::AppObserver : Object)
          def onNewModel(model)
            if defined?(OverlayService)
              OverlayService.on_model_opened(model)
            end
            Dialog::ExportDialog.refresh_if_open(model) if defined?(Dialog::ExportDialog)
          end

          def onOpenModel(model)
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

          # Закрытие SketchUp: принудительная запись всех измененных сессий в YAML
          def onQuit
            ObserverService.handle_quit
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

            # Инициализация сессии для текущей активной модели
            if Sketchup.respond_to?(:active_model) && Sketchup.active_model
              model = Sketchup.active_model
              handle_model_opened(model, false) if model.respond_to?(:path) && !model.path.to_s.empty?
            end
          end

          # Обработка открытия модели: загрузка данных проекта из YAML в сессию памяти.
          # Параметр force позволяет принудительно повторить обработку для уже открытой в сессии модели.
          def handle_model_opened(model, force = false)
            return unless model

            model_path = model.respond_to?(:path) ? model.path.to_s.tr("\\", "/") : ""
            return if model_path.empty?

            norm_path = model_path.downcase
            # Если модель уже обработана в текущей сессии SketchUp и не запрошен принудительный инкремент
            return if @session_opened_models[norm_path] && !force

            @session_opened_models[norm_path] = true

            project_data = Model::SessionStore.on_model_opened(model)

            # Актуализация оверлея с открытой моделью
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

          # Закрытие SketchUp: запись всех измененных сессий в YAML файлы
          def handle_quit
            saved = Model::SessionStore.flush_all
            warn "[DN1C Export PDF] При закрытии сохранено сессий: #{saved}" if saved.positive?
          rescue StandardError => e
            warn "[DN1C Export PDF] Ошибка сохранения при закрытии: #{e.message}"
          end
        end
      end
    end
  end
end
