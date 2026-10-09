# frozen_string_literal: true

require "fileutils"

module DN1Code
  module ExportPdf2
    module Service
      # Очередь конвертации PNG/JPG-снимков в WebP (через VipsService).
      #
      # Почему таймер на главном потоке, а не фоновые потоки: вызовы libvips из
      # фоновых Ruby-потоков в SketchUp воспроизводимо зависают — кодирование
      # завершается и .webp файл записан на диск, но C-вызов через Fiddle не
      # возвращается: воркер остается «жив» навсегда (индикатор в статусной
      # строке горит вечно), а новые Ruby-потоки перестают планироваться.
      # Вне SketchUp тот же код на тех же DLL конвертирует за 0.06 c, а в
      # главном потоке SketchUp — тоже (0.05-0.2 c на снимок). Поэтому обработка
      # кооперативная: UI.start_timer берет по одному заданию за тик на главном
      # потоке — PDF открывается сразу, SketchUp остается отзывчивым между
      # снимками, а Sketchup.status_text= безопасен по определению.
      #
      # Повторный экспорт во время конвертации: submit заменяет очередь целиком
      # (обработка однопоточная, «задумавшихся» воркеров нет), а drain добирает
      # остаток синхронно — перед очисткой папки images экспорт гарантированно
      # знает, что файлы больше не двигаются.
      module SnapshotWorker
        extend self

        # Интервал тика обработки очереди, секунд
        TICK_INTERVAL = 0.25

        # Задание на конвертацию: { src:, dst:, quality:, lossless: }
        # @param jobs [Array<Hash>]
        # @return [Hash] статус партии (см. .status)
        def submit(jobs)
          jobs = Array(jobs).reject { |j| j.nil? || j[:src].to_s.empty? || j[:dst].to_s.empty? }
          return status if jobs.empty? || !defined?(Service::VipsService) || !Service::VipsService.ensure_started!

          @generation += 1
          @total  = jobs.size
          @done   = 0
          @failed = 0
          @errors = []
          @queue  = jobs.map { |j| j.merge(generation: @generation) }

          start_worker_timer
          status
        end

        # Добработать текущую партию синхронно. Все точки вызова (экспорт, тесты)
        # работают на главном потоке, так что конкуренции с тиком таймера нет.
        # Ограничение timeout не дает заморозить SketchUp на большой партии:
        # остаток остается в очереди и дообрабатывается тиками.
        # @param timeout [Float, nil] ограничение суммарного времени; nil — до конца партии
        # @return [Hash] статус
        def drain(timeout = nil)
          deadline = timeout ? Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout : nil
          until @queue.empty?
            break if deadline && Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

            tick_job
          end
          status
        end

        # Состояние текущей/последней партии
        # @return [Hash] { running:, total:, done:, failed:, errors: }
        def status
          {
            running: running?,
            total:   @total,
            done:    @done,
            failed:  @failed,
            errors:  @errors.dup
          }
        end

        private

        def initialize_state
          @generation = 0
          @total      = 0
          @done       = 0
          @failed     = 0
          @errors     = []
          @queue      = []
          @timer_id   = nil
        end

        def running?
          !@queue.empty?
        end

        # ------------------------------------------------------------------
        # Обработка очереди таймером на главном потоке: по одному снимку за тик
        # ------------------------------------------------------------------
        def start_worker_timer
          return if @timer_id
          return unless defined?(UI) && UI.respond_to?(:start_timer)

          @timer_id = UI.start_timer(TICK_INTERVAL, true) { tick }
        end

        # Колбэк UI.start_timer: конвертирует один снимок, обновляет статусную строку
        def tick
          return finish_batch_and_stop unless running?

          tick_job
          set_status_text("DN1Sup Export PDF: WebP-снимки: #{@done + @failed}/#{@total}…") if @total.positive?
          true # таймер продолжается
        end

        # Один шаг обработки (используется тиком таймера и drain)
        def tick_job
          job = @queue.shift
          begin
            if run_job(job)
              @done += 1
            else
              @failed += 1
              @errors << "#{File.basename(job[:src].to_s)}: конвертация не удалась, снимок оставлен в PNG"
            end
          rescue StandardError => e
            @failed += 1
            @errors << "#{File.basename(job[:src].to_s)}: #{e.message}"
            warn "SnapshotWorker: ошибка конвертации #{job[:src]}: #{e.message}"
          end
        end

        def finish_batch_and_stop
          stop_worker_timer
          if @total.positive?
            msg =
              if @failed.zero?
                "DN1Sup Export PDF: WebP-снимки готовы (#{@total})"
              else
                "DN1Sup Export PDF: WebP-снимки: готово #{@done}, с ошибками #{@failed} (эти сцены сохранены в PNG)"
              end
            set_status_text(msg)
          end
          false # остановка повторяющегося таймера
        end

        def stop_worker_timer
          timer = @timer_id
          @timer_id = nil
          UI.stop_timer(timer) if timer && defined?(UI) && UI.respond_to?(:stop_timer)
        end

        def set_status_text(text)
          Sketchup.status_text = text if defined?(Sketchup) && Sketchup.respond_to?(:status_text=)
        end

        # Конвертация одного снимка. Запись идет во временный файл с номером
        # поколения (<имя>.<поколение>.tmp.webp) и атомарным переименованием:
        # при обрыве (закрытие SketchUp) не остается битого целевого файла, а
        # tmp от предыдущей партии не путается с новой. При неудаче PNG/JPG-
        # исходник остается на месте — это снимок сцены (фолбэк, как и раньше
        # при недоступной libvips).
        # @return [Boolean]
        def run_job(job)
          src = job[:src].to_s
          dst = job[:dst].to_s
          tmp = dst.sub(/\.webp$/i, ".#{job[:generation]}.tmp.webp")
          return false unless File.exist?(src)

          ok = VipsService.png_to_webp(src, tmp, quality: job[:quality], lossless: job[:lossless])
          return false unless ok && File.exist?(tmp)

          File.delete(dst) if File.exist?(dst) rescue nil
          begin
            File.rename(tmp, dst)
          rescue StandardError
            FileUtils.mv(tmp, dst)
          end
          unless File.exist?(dst)
            File.delete(tmp) rescue nil
            return false
          end

          File.delete(src) if File.exist?(src) rescue nil
          true
        end

        initialize_state
      end
    end
  end
end
