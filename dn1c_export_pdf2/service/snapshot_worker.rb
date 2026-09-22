# frozen_string_literal: true

require "fileutils"

module DN1Code
  module ExportPdf2
    module Service
      # Фоновый пул потоков для конвертации PNG-снимков в WebP (через VipsService).
      #
      # Зачем: экспорт PDF не должен ждать конвертации снимков. Контроллер синхронно
      # раскладывает PNG-исходники в <Артикул>/images и передает задания сюда; PDF
      # открывается сразу, конвертация идет в фоне и не трогает SketchUp API
      # (только файлы и libvips — она потокобезопасна, DLL/vips_init прогреваются
      # в главном потоке до старта пула).
      #
      # Потокобезопасность: @lock защищает состояние, но никогда не держится во время
      # длительных операций (join, конвертация) — поэтому дедлоков нет. Прогресс
      # показывается в статусной строке SketchUp через UI.start_timer (колбэк таймера
      # исполняется в главном потоке — API вызывается только оттуда).
      #
      # Повторный экспорт во время конвертации: каждая партия несет номер поколения.
      # Новый submit увеличивает поколение — оставшиеся задания старой партии
      # отбрасываются, а «задумавшийся» посреди конвертации воркер выбрасывает свой
      # результат, не трогая файлы новой партии. Поэтому экспорт никогда не ждет
      # завершения прошлой конвертации.
      module SnapshotWorker
        extend self

        # Задание на конвертацию: { src:, dst:, quality:, lossless: }
        # @param jobs [Array<Hash>]
        # @return [Hash] статус партии (см. .status)
        def submit(jobs)
          jobs = Array(jobs).reject { |j| j.nil? || j[:src].to_s.empty? || j[:dst].to_s.empty? }
          return status if jobs.empty? || !defined?(Service::VipsService) || !Service::VipsService.ensure_started!

          queue = Queue.new
          generation = nil
          @lock.synchronize do
            @generation += 1
            generation  = @generation
            @total      = jobs.size
            @done       = 0
            @failed     = 0
            @errors     = []
            jobs.each { |j| queue << j.merge(generation: generation) }
          end

          count = [pool_size, jobs.size].min
          threads = count.times.map { Thread.new(queue) { |q| work_loop(q) } }
          @lock.synchronize { @threads = threads }

          start_status_timer
          status
        end

        # Дождаться завершения текущей партии (no-op, если ничего не выполняется).
        # @param timeout [Float, nil] ограничение суммарного ожидания; nil — ждать до конца.
        #   Экспорт вызывает drain(3.0): обычно партия уже закончилась (мгновенный возврат),
        #   а остаток дождаться нельзя — чтобы не замораживать SketchUp, поколения
        #   гарантируют корректность и без ожидания.
        # @return [Hash] статус
        def drain(timeout = nil)
          deadline = timeout ? Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout : nil
          threads = @lock.synchronize { @threads.dup }
          threads.each do |t|
            next unless t.alive?

            remain = deadline ? deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC) : nil
            break if remain && remain <= 0

            t.join(remain)
          end
          status
        end

        # Состояние текущей/последней партии
        # @return [Hash] { running:, total:, done:, failed:, errors: }
        def status
          @lock.synchronize do
            {
              running: @threads.any?(&:alive?),
              total:   @total,
              done:    @done,
              failed:  @failed,
              errors:  @errors.dup
            }
          end
        end

        private

        def initialize_state
          @lock       = Mutex.new
          @threads    = []
          @generation = 0
          @total      = 0
          @done       = 0
          @failed     = 0
          @errors     = []
          @timer_id   = nil
        end

        # Размер пула: половина логических ядер, зажата в 2..4. Каждая конвертация
        # одноядерная (VIPS_CONCURRENCY=1 в VipsService), так что пул = число занятых ядер.
        def pool_size
          require "etc" unless defined?(Etc)
          [[Etc.nprocessors.to_i / 2, 2].max, 4].min
        rescue StandardError
          2
        end

        # Цикл рабочего потока: разбирает свою очередь до опустошения
        def work_loop(queue)
          loop do
            job = begin
              queue.pop(true)
            rescue ThreadError
              break
            end
            next if stale?(job)

            begin
              ok = run_job(job)
              @lock.synchronize do
                if ok
                  @done += 1
                else
                  @failed += 1
                  @errors << "#{File.basename(job[:src].to_s)}: конвертация не удалась, снимок оставлен в PNG"
                end
              end
            rescue StandardError => e
              @lock.synchronize do
                @failed += 1
                @errors << "#{File.basename(job[:src].to_s)}: #{e.message}"
              end
              warn "SnapshotWorker: ошибка конвертации #{job[:src]}: #{e.message}"
            end
          end
        end

        # Партия устарела (шел новый экспорт) — задание больше не актуально
        def stale?(job)
          generation = job[:generation]
          @lock.synchronize { generation != @generation }
        end

        # Конвертация одного снимка. Запись идет во временный <имя>.tmp.webp с
        # атомарным переименованием: при обрыве (закрытие SketchUp) не остается
        # битого целевого файла. При неудаче PNG-исходник остается на месте —
        # это снимок сцены (фолбэк, как и раньше при недоступной libvips).
        # Поколение проверяется и после конвертации: результат устаревшей партии
        # выбрасывается, файлы новой партии не перезаписываются.
        # @return [Boolean]
        def run_job(job)
          src = job[:src].to_s
          dst = job[:dst].to_s
          tmp = dst.sub(/\.webp$/i, ".tmp.webp")
          return false unless File.exist?(src)

          ok = VipsService.png_to_webp(src, tmp, quality: job[:quality], lossless: job[:lossless])
          return false unless ok && File.exist?(tmp)

          if stale?(job)
            File.delete(tmp) rescue nil
            return true
          end

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

        # ------------------------------------------------------------------
        # Индикация в статусной строке SketchUp: колбэк UI.start_timer
        # исполняется в главном потоке, поэтому Sketchup.status_text= отсюда безопасен
        # ------------------------------------------------------------------
        def start_status_timer
          return if @timer_id
          return unless defined?(UI) && UI.respond_to?(:start_timer)

          @timer_id = UI.start_timer(0.5, true) { status_tick }
        end

        def status_tick
          st = status
          if st[:running]
            set_status_text("DN1C Export PDF: WebP-снимки: #{st[:done]}/#{st[:total]}…")
            return true
          end

          stop_status_timer
          if st[:total].to_i.positive?
            msg = if st[:failed].to_i.zero?
                    "DN1C Export PDF: WebP-снимки готовы (#{st[:total]})"
                  else
                    "DN1C Export PDF: WebP-снимки: готово #{st[:done]}, с ошибками #{st[:failed]} (эти сцены сохранены в PNG)"
                  end
            set_status_text(msg)
          end
          false # остановка повторяющегося таймера
        end

        def stop_status_timer
          timer = @timer_id
          @timer_id = nil
          UI.stop_timer(timer) if timer && defined?(UI) && UI.respond_to?(:stop_timer)
        end

        def set_status_text(text)
          Sketchup.status_text = text if defined?(Sketchup) && Sketchup.respond_to?(:status_text=)
        end

        initialize_state
      end
    end
  end
end
