# frozen_string_literal: true

# -------------------------------------------------------------------------------
# Очередь WebP-снимков Service::SnapshotWorker.
#
# Покрывается кооперативная обработка на главном потоке: submit/drain/status,
# тики таймера UI.start_timer (по одному снимку за тик), замена очереди при
# повторном submit, учет done/failed/errors, имена tmp с поколением и фолбэк
# при недоступном libvips.
#
# Запуск отдельно:
#   ruby -I dn1sup_export_pdf2 dn1sup_export_pdf2/test/test_snapshot_worker.rb
# -------------------------------------------------------------------------------

require_relative "mock_sketchup"
require "tmpdir"
require "fileutils"

# Заглушка VipsService: реальный не нужен, конвертация эмулируется копированием
module DN1Code
  module ExportPdf2
    module Service
      module VipsService
        extend self

        class << self
          attr_accessor :mode, :delay
        end
        @mode  = :ok   # :ok | :fail | :raise
        @delay = nil

        def calls
          @calls ||= []
        end

        def available? = true
        def started? = true
        def ensure_started! = true

        def png_to_webp(src, dst, quality: nil, lossless: false)
          calls << { src: src, dst: dst, quality: quality }
          sleep(delay) if delay
          case mode
          when :fail
            nil
          when :raise
            raise "libvips boom"
          else
            FileUtils.cp(src, dst)
            dst
          end
        end
      end
    end
  end
end

require_relative "../service/snapshot_worker"

module DN1Code
  module ExportPdf2
    class SnapshotWorkerStandaloneRunner
      WORKER = Service::SnapshotWorker

      def initialize
        @passed = 0
        @failed = 0
      end

      def assert(condition, message)
        if condition
          puts "  [PASS] #{message}"
          @passed += 1
        else
          puts "  [FAIL] #{message}"
          @failed += 1
        end
      end

      def run_all
        Dir.mktmpdir do |tmp|
          @tmp = tmp
          run_ok_batch_tests(tmp)
          run_timer_tick_tests(tmp)
          run_failure_tests(tmp)
          run_replace_queue_tests(tmp)
          run_guard_tests(tmp)
        end

        puts "=========================================================="
        puts "  ИТОГИ ТЕСТИРОВАНИЯ: Успешно: #{@passed}, Ошибок: #{@failed}"
        puts "=========================================================="
        exit(@failed.zero? ? 0 : 1)
      end

      private

      # 16x16 PNG (содержимое не важно: конвертация мокается)
      def make_png(name)
        require "zlib"
        path = File.join(@tmp, name)
        chunk = lambda do |type, data|
          [data.bytesize].pack("N") + type + data + [Zlib.crc32(type + data)].pack("N")
        end
        raw = (([0] + [255, 0, 0] * 15) * 16).pack("C*")
        png = "\x89PNG\r\n\x1a\n".b +
              chunk.call("IHDR", [16, 16, 8, 2, 0, 0, 0].pack("NNCCCCC")) +
              chunk.call("IDAT", Zlib::Deflate.deflate(raw)) +
              chunk.call("IEND", "")
        File.binwrite(path, png)
        path
      end

      def jobs_for(names)
        names.map do |n|
          src = make_png("#{n}.png")
          { src: src, dst: File.join(@tmp, "#{n}.webp"), quality: 85, lossless: false }
        end
      end

      def reset_worker
        WORKER.send(:initialize_state)
        Service::VipsService.mode  = :ok
        Service::VipsService.delay = nil
        Service::VipsService.calls.clear
        UI.timers.clear
      end

      # --- Базовая партия через drain ---
      def run_ok_batch_tests(tmp)
        puts "----------------------------------------------------------"
        puts "  drain: полная партия, учет, удаление исходников"
        puts "----------------------------------------------------------"
        reset_worker
        jobs = jobs_for(%w[a1 a2 a3])
        st = WORKER.submit(jobs)
        assert(st[:running] == true && st[:total] == 3, "submit: партия принята, running=true (3 задания)")
        assert(UI.timers.size == 1, "submit: запущен ровно один таймер")

        st = WORKER.drain
        assert(st[:done] == 3 && st[:failed].zero?, "drain: все 3 конвертации успешны")
        assert(st[:running] == false, "drain: партия завершена (running=false)")
        assert(jobs.all? { |j| File.exist?(j[:dst]) }, "drain: .webp файлы на месте")
        assert(jobs.none? { |j| File.exist?(j[:src]) }, "drain: PNG-исходники удалены после успеха")
        assert(st[:errors].empty?, "drain: без ошибок")

        dst_regexp = /\.(\d+)\.tmp\.webp$/i
        assert(Service::VipsService.calls.all? { |c| c[:dst] =~ dst_regexp },
               "tmp имя содержит поколение (<имя>.N.tmp.webp)")
        assert(Service::VipsService.calls.none? { |c| c[:dst] == c[:src] },
               "конвертация пишет во временный файл, не в целевой напрямую")
      end

      # --- Тики таймера: по одному снимку за тик, финальное сообщение ---
      def run_timer_tick_tests(tmp)
        puts "----------------------------------------------------------"
        puts "  таймер: по одному снимку за тик, остановка и статус"
        puts "----------------------------------------------------------"
        reset_worker
        jobs = jobs_for(%w[t1 t2])
        WORKER.submit(jobs)
        timer_id = UI.timers.keys.first

        result = UI.fire_timer(timer_id)
        assert(result == true, "тик: таймер продолжается, пока есть задания")
        assert(WORKER.status[:done] == 1, "тик: за тик обработан один снимок (done=1)")
        assert(WORKER.status[:running] == true, "тик: партия еще идет")
        assert(Sketchup.status_text.to_s.include?("1/2"), "тик: статусная строка показывает 1/2")

        3.times { UI.fire_timer(timer_id) }
        assert(WORKER.status[:done] == 2 && WORKER.status[:running] == false, "тики: партия доделана")
        assert(UI.timers.empty?, "тики: таймер остановлен после завершения партии")
        assert(Sketchup.status_text.to_s.include?("готовы (2)"),
               "тики: финальное сообщение «WebP-снимки готовы (2)»")

        # Тик по пустой очереди без партии не должен ничего сломать
        reset_worker
        assert(UI.timers.empty? || WORKER.status[:running] == false, "после сброса очередей нет")
      end

      # --- Ошибки конвертации: фолбэк на PNG, партия продолжается ---
      def run_failure_tests(tmp)
        puts "----------------------------------------------------------"
        puts "  ошибки: failed учет, исходник остается, партия идет дальше"
        puts "----------------------------------------------------------"
        reset_worker
        Service::VipsService.mode = :fail
        jobs = jobs_for(%w[f1 f2])
        st = WORKER.submit(jobs)
        st = WORKER.drain
        assert(st[:done].zero? && st[:failed] == 2, "mode=fail: оба задания в failed")
        assert(jobs.all? { |j| File.exist?(j[:src]) }, "mode=fail: PNG-исходники сохранены (фолбэк)")
        assert(st[:errors].any? { |e| e.include?("конвертация не удалась") },
               "mode=fail: в errors понятное сообщение")

        reset_worker
        Service::VipsService.mode = :raise
        jobs = jobs_for(%w[r1 r2])
        WORKER.submit(jobs)
        st = WORKER.drain
        assert(st[:failed] == 2 && st[:errors].any? { |e| e.include?("libvips boom") },
               "mode=raise: исключение ловится, партия не падает")
        Service::VipsService.mode = :ok
      end

      # --- Повторный submit во время обработки: очередь заменяется ---
      def run_replace_queue_tests(tmp)
        puts "----------------------------------------------------------"
        puts "  повторный submit: новая партия заменяет старую"
        puts "----------------------------------------------------------"
        reset_worker
        Service::VipsService.delay = 0.02
        old_jobs = jobs_for(%w[q1 q2 q3])
        WORKER.submit(old_jobs)
        WORKER.drain(0.0) # не двигает очередь, она остается заполненной
        queued_before = WORKER.status[:total]
        assert(queued_before == 3 && WORKER.status[:running] == true, "после drain(0) старая партия еще идет")

        new_jobs = jobs_for(%w[q4])
        st = WORKER.submit(new_jobs)
        assert(st[:total] == 1 && st[:done].zero? && st[:failed].zero?,
               "submit: счетчики сброшены под новую партию")
        st = WORKER.drain
        assert(st[:done] == 1 && st[:total] == 1, "drain: доделана только новая партия")
        assert(old_jobs.none? { |j| File.exist?(j[:dst]) },
               "старая партия не дописывалась после замены очереди")
        Service::VipsService.delay = nil
      end

      # --- Защитные пути: мусорные задания и недоступный libvips ---
      def run_guard_tests(tmp)
        puts "----------------------------------------------------------"
        puts  "  защита: пустые задания, сбой ensure_started!"
        puts "----------------------------------------------------------"
        reset_worker
        st = WORKER.submit([])
        assert(st[:running] == false && st[:total].zero?, "submit([]): пустая партия не запускает очередь")

        st = WORKER.submit([{ src: "", dst: "x.webp" }, nil, { src: make_png("g1.png"), dst: "" }])
        assert(st[:running] == false, "submit: задания без src/dst отбрасываются")

        svc = Service::VipsService
        def svc.ensure_started!
          false
        end
        jobs = jobs_for(%w[g2])
        st = WORKER.submit(jobs)
        assert(st[:running] == false && st[:total].zero?, "submit: при сбое ensure_started! очередь не наполняется")
        assert(jobs.all? { |j| File.exist?(j[:src]) }, "submit: исходники не тронуты при сбое libvips")
      ensure
        def svc.ensure_started!
          true
        end
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  DN1Code::ExportPdf2::SnapshotWorkerStandaloneRunner.new.run_all
end
