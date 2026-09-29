# frozen_string_literal: true

require "weakref"

module DN1Code
  module ExportPdf2
    module Service
      # Трекер активной работы: считает время активной работы пользователя
      # в SketchUp и начисляет его в статистику активной модели
      # (Model::ProjectData#work_stats → project.yaml в папке артикула).
      #
      # Активность = события наблюдателей SketchUp (смена инструмента,
      # коммиты транзакций, undo/redo) и пульсы из HtmlDialog
      # (колбэк activityPing: мышь/клавиатура/колесо в панели). Бездействие
      # дольше IDLE_TIMEOUT секунд не учитывается, начисляемый интервал
      # ограничен той же величиной (сон/потеря событий не раздувает статистику).
      #
      # Запись на диск — штатные точки flush (кнопка «Сохранить», экспорт PDF,
      # закрытие SketchUp) плюс периодический flush каждые
      # PERSIST_EVERY_TICKS тиков при неначисленном хвосте.
      module StatsTracker
        TICK_INTERVAL       = 30  # сек между тиками таймера
        IDLE_TIMEOUT        = 300 # порог бездействия, сек
        PERSIST_EVERY_TICKS = 10  # тиков между периодическими записями (≈5 мин)

        @timer_id            = nil
        @last_activity       = nil
        @last_accrue_at      = nil
        @unflushed           = false
        @ticks_since_persist = 0
        @tools_observer      = nil
        @model_observer      = nil
        @observed_tools      = []
        @observed_models     = []

        class << self
          # Запуск трекера при загрузке плагина: таймер начисления + наблюдатели
          # текущей модели. Повторный вызов (hot reload) безопасен.
          # @return [void]
          def register!
            return unless defined?(Sketchup) && defined?(UI) && UI.respond_to?(:start_timer)
            return if @timer_id

            now = Time.now
            @last_activity  = now
            @last_accrue_at = now

            attach_to_model(active_model)

            @timer_id = UI.start_timer(TICK_INTERVAL, true) { tick }
          rescue StandardError => e
            warn "[DN1C Export PDF] StatsTracker: не удалось запустить: #{e.message}"
          end

          # Отметка активности (из наблюдателей SketchUp и пульсов диалога)
          # @return [void]
          def heartbeat
            @last_activity = Time.now
          rescue StandardError
            nil
          end

          # Смена активной модели: пульс + подключение наблюдателей новой модели
          # (вызывается из AppObserver: onNewModel, onOpenModel, onActivateModel)
          # @param model [Sketchup::Model, nil]
          # @return [void]
          def on_model_activated(model)
            heartbeat
            attach_to_model(model)
          rescue StandardError => e
            warn "[DN1C Export PDF] StatsTracker: ошибка активации модели: #{e.message}"
          end

          # Подключает наблюдателей активности к модели (без дублей — по образцу
          # attach_pages_observer: WeakRef + очистка умерших ссылок)
          # @param model [Sketchup::Model, nil]
          # @return [void]
          def attach_to_model(model)
            return unless model

            prune_weakrefs!

            if model.respond_to?(:tools) && model.tools.respond_to?(:add_observer)
              unless @observed_tools.any? { |wr| weakref_equals?(wr, model.tools) }
                tools = model.tools
                tools.add_observer(tools_observer_instance)
                @observed_tools << WeakRef.new(tools)
              end
            end

            return unless model.respond_to?(:add_observer)

            unless @observed_models.any? { |wr| weakref_equals?(wr, model) }
              model.add_observer(model_observer_instance)
              @observed_models << WeakRef.new(model)
            end
          rescue StandardError => e
            warn "[DN1C Export PDF] StatsTracker: не удалось подключить наблюдателей: #{e.message}"
          end

          # ----------------------------------------------------------------
          private

          # Тик таймера: начисление времени активной модели + периодическая запись
          def tick
            now = Time.now

            if @last_activity.nil? || (now - @last_activity) > IDLE_TIMEOUT
              # Бездействие: окно начисления сбрасывается, время не растет
              @last_accrue_at = now
            else
              delta = @last_accrue_at ? (now - @last_accrue_at).round : 0
              @last_accrue_at = now
              delta = delta.clamp(0, IDLE_TIMEOUT)
              accrue_delta(delta, now) if delta.positive?
            end

            persist_periodically
          rescue StandardError => e
            warn "[DN1C Export PDF] StatsTracker: ошибка тика: #{e.message}"
          end

          def accrue_delta(delta, now)
            model = active_model
            return unless model

            project_data = begin
              Model::SessionStore.data(model)
            rescue StandardError
              nil
            end
            return unless project_data.respond_to?(:accrue_work_stats)

            project_data.accrue_work_stats(delta, now)
            Model::SessionStore.mark_dirty!(model)
            @unflushed = true
            @ticks_since_persist += 1
          end

          def persist_periodically
            return unless @unflushed && @ticks_since_persist >= PERSIST_EVERY_TICKS

            @ticks_since_persist = 0
            model = active_model
            ok = model ? flush_model(model) : false
            @unflushed = !ok
          end

          def flush_model(model)
            return false unless defined?(Model::SessionStore)

            Model::SessionStore.flush(model)
          rescue StandardError => e
            warn "[DN1C Export PDF] StatsTracker: периодическая запись не удалась: #{e.message}"
            false
          end

          def active_model
            return nil unless defined?(Sketchup) && Sketchup.respond_to?(:active_model)

            Sketchup.active_model
          rescue StandardError
            nil
          end

          def tools_observer_instance
            return nil unless defined?(ToolsActivityObserver)

            @tools_observer ||= ToolsActivityObserver.new
          end

          def model_observer_instance
            return nil unless defined?(ModelActivityObserver)

            @model_observer ||= ModelActivityObserver.new
          end

          def prune_weakrefs!
            @observed_tools.reject! { |wr| !wr.weakref_alive? }
            @observed_models.reject! { |wr| !wr.weakref_alive? }
          end

          # WeakRef делегирует == цели — работает и на Ruby 3.x (SketchUp),
          # и на Ruby 4.x (офлайн-тесты)
          def weakref_equals?(wr, obj)
            wr == obj
          rescue StandardError
            false
          end
        end

        # Наблюдатель инструментов: смена активного инструмента (в т.ч.
        # навигация орбитой/панорамой) — самый частый сигнал работы в модели
        if defined?(Sketchup::ToolsObserver)
          class ToolsActivityObserver < Sketchup::ToolsObserver
            def onActiveToolChanged(*_args)
              StatsTracker.heartbeat
            end
          end
        end

        # Наблюдатель модели: коммиты транзакций (любые правки геометрии),
        # undo/redo — сигналы редактирования
        if defined?(Sketchup::ModelObserver)
          class ModelActivityObserver < Sketchup::ModelObserver
            def onTransactionCommit(*_args)
              StatsTracker.heartbeat
            end

            def onTransactionEmpty(*_args)
              StatsTracker.heartbeat
            end

            def onTransactionUndo(*_args)
              StatsTracker.heartbeat
            end

            def onTransactionRedo(*_args)
              StatsTracker.heartbeat
            end
          end
        end
      end
    end
  end
end
