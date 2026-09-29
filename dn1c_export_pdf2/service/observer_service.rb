# frozen_string_literal: true

require "weakref"

require_relative "../model/project_data"
require_relative "../model/session_store"

module DN1Code
  module ExportPdf2
    module Service
      module ObserverService
        @app_observer          = nil
        @pages_observer        = nil
        @observed_pages        = []
        @session_opened_models = {}

        class << self
          attr_accessor :session_opened_models
        end

        class AppObserverHandler < (defined?(Sketchup::AppObserver) ? Sketchup::AppObserver : Object)
          def onNewModel(model)
            Service::StatsTracker.on_model_activated(model) if defined?(Service::StatsTracker)
            attach_pages_observer(model)
            if defined?(OverlayService)
              OverlayService.on_model_opened(model)
            end
            Dialog::ExportDialog.refresh_if_open(model) if defined?(Dialog::ExportDialog)
          end

          def onOpenModel(model)
            Service::StatsTracker.on_model_activated(model) if defined?(Service::StatsTracker)

            # Сбрасываем кэш сессии для только что открытой модели, чтобы повторная обработка не блокировалась
            if model && model.respond_to?(:path) && !model.path.to_s.empty?
              clean_p = model.path.to_s.tr("\\", "/").downcase
              ObserverService.session_opened_models.delete(clean_p)
            end

            attach_pages_observer(model)

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

          # Активация уже открытой модели (актуально на Mac, вызовы защищены)
          def onActivateModel(model)
            Service::StatsTracker.on_model_activated(model) if defined?(Service::StatsTracker)
          end
        end

        # Наблюдатель коллекции страниц модели: SketchUp уведомляет PagesObserver
        # #onContentsModified при переключении активной страницы (вкладки сцен,
        # программное selected_page=, панель расширения)
        class PagesObserverHandler < (defined?(Sketchup::PagesObserver) ? Sketchup::PagesObserver : Object)
          def onContentsModified(pages)
            model = pages.respond_to?(:parent) ? pages.parent : nil
            model ||= (defined?(Sketchup) && Sketchup.respond_to?(:active_model) ? Sketchup.active_model : nil)
            return unless defined?(OverlayService)

            info = OverlayService.on_page_changed(model)
            Dialog::ExportDialog.notify_active_scene(info) if info && defined?(Dialog::ExportDialog)
          rescue StandardError => e
            warn "[DN1C Export PDF] Ошибка обработки смены страницы: #{e.message}"
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
              attach_pages_observer(model)
              handle_model_opened(model, false) if model.respond_to?(:path) && !model.path.to_s.empty?
            end
          end

          # Подключает наблюдатель страниц к коллекции страниц модели (без дублей:
          # SketchUp уведомляет через один и тот же экземпляр наблюдателя)
          # @param model [Sketchup::Model, nil]
          # @return [Boolean] true если наблюдатель подключен (или уже был)
          def attach_pages_observer(model)
            return false unless model && model.respond_to?(:pages) && model.pages.respond_to?(:add_observer)

            pages = model.pages
            return true if pages_observer_attached?(pages)

            @pages_observer ||= PagesObserverHandler.new
            pages.add_observer(@pages_observer)
            @observed_pages << WeakRef.new(pages)
            @observed_pages.reject! { |wr| !wr.weakref_alive? }
            true
          rescue StandardError => e
            warn "[DN1C Export PDF] Не удалось подключить наблюдатель страниц: #{e.message}"
            false
          end

          # Проверяет, подключен ли уже наблюдатель к этой коллекции страниц
          # @param pages [Sketchup::Pages]
          # @return [Boolean]
          def pages_observer_attached?(pages)
            @observed_pages.any? do |wr|
              next false unless wr.is_a?(WeakRef) && wr.weakref_alive?

              begin
                # WeakRef делегирует == цели и на Ruby 3.x (SketchUp), и на Ruby 4.x (тесты)
                wr == pages
              rescue StandardError
                false
              end
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
              yaml_name = Model::ProjectData::PROJECT_YAML_NAME
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
