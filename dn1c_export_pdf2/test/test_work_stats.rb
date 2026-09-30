# frozen_string_literal: true

# -------------------------------------------------------------------------------
# Проверка статистики активной работы над проектом (вкладка «Статистика»).
#
# Покрывается чистая логика Model::WorkStats (начисление по дням/часам,
# нормализация, очистка hourly, агрегации для графиков часы/дни/недели/месяцы/
 # годы) и интеграция с ProjectData: round-trip через project.yaml, сброс,
# игнорирование секции при импорте YAML.
#
# Запуск отдельно:
#   ruby -I dn1c_export_pdf2 dn1c_export_pdf2/test/test_work_stats.rb
# -------------------------------------------------------------------------------

require_relative "mock_sketchup"
require_relative "../main"
require "tmpdir"
require "fileutils"

module DN1Code
  module ExportPdf2
    class WorkStatsStandaloneRunner
      PD     = ::DN1Code::ExportPdf2::Model::ProjectData
      STATS  = ::DN1Code::ExportPdf2::Model::WorkStats

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
        run_work_stats_tests
        run_project_data_tests

        puts "=========================================================="
        puts "  ИТОГИ ТЕСТИРОВАНИЯ: Успешно: #{@passed}, Ошибок: #{@failed}"
        puts "=========================================================="
        exit(@failed.zero? ? 0 : 1)
      end

      def run_work_stats_tests
        puts "=========================================================="
        puts "  Model::WorkStats: начисление, нормализация, report"
        puts "=========================================================="

        # --- Начисление в бакеты дня и часа ---
        data = STATS.blank_data
        STATS.accrue!(data, 3600, Time.new(2026, 9, 29, 14, 30, 0))
        assert(data[:daily]["2026-09-29"] == 3600, "accrue! кладет секунды в дневной бакет")
        assert(data[:hourly]["2026-09-29 14"] == 3600, "accrue! кладет секунды в часовой бакет")
        assert(data[:total_seconds] == 3600, "accrue! наращивает total_seconds")
        assert(data[:first_tracked] == "2026-09-29" && data[:last_tracked] == "2026-09-29", "accrue! обновляет first/last_tracked")

        # --- Переход через час и сутки ---
        STATS.accrue!(data, 600, Time.new(2026, 9, 29, 23, 50, 0))
        STATS.accrue!(data, 300, Time.new(2026, 9, 30, 0, 10, 0))
        assert(data[:daily]["2026-09-29"] == 4200 && data[:daily]["2026-09-30"] == 300, "суточные бакеты разделяются по полуночи")
        assert(data[:hourly]["2026-09-29 23"] == 600 && data[:hourly]["2026-09-30 00"] == 300, "часовые бакеты разделяются по часам")
        assert(data[:total_seconds] == 4500, "total_seconds учитывает все начисления (4500)")
        assert(data[:last_tracked] == "2026-09-30", "last_tracked смещается на поздний день")

        # --- Отбрасывание некорректных начислений ---
        before = data[:total_seconds]
        STATS.accrue!(data, 0, Time.new(2026, 9, 30, 1, 0, 0))
        STATS.accrue!(data, -5, Time.new(2026, 9, 30, 1, 0, 0))
        assert(data[:total_seconds] == before, "accrue! игнорирует неположительные секунды")

        # --- Нормализация из строкового YAML (ключи-даты приходят символами) ---
        raw = { "version" => 1, "total_seconds" => "12", "first_tracked" => "2026-09-01",
                "last_tracked" => "2026-09-02",
                "daily" => { "2026-09-01" => "7", :"2026-09-02" => 5 },
                "hourly" => { :"2026-09-02 10" => 5 } }
        norm = STATS.normalize(raw)
        assert(norm[:daily]["2026-09-01"] == 7 && norm[:daily]["2026-09-02"] == 5, "normalize приводит ключи и значения к строкам/числам")
        assert(norm[:total_seconds] == 12, "normalize парсит total_seconds")

        # --- Очистка hourly ---
        old = (Time.new(2026, 9, 30) - (STATS::HOURLY_KEEP_DAYS + 5) * 86_400)
        STATS.accrue!(data, 60, old)
        STATS.prune!(data, Time.new(2026, 9, 30, 12, 0, 0))
        assert(!data[:hourly].key?(old.strftime("%Y-%m-%d %H")), "prune! удаляет hourly старше HOURLY_KEEP_DAYS")
        assert(data[:daily].key?(old.strftime("%Y-%m-%d")), "prune! не трогает дневные бакеты")

        # --- report: сводные окна и серии ---
        now = Time.new(2026, 9, 30, 14, 0, 0) # вторник
        rep = STATS.report(data, now)
        assert(rep[:total_seconds] == 4560, "report.total_seconds = 4560 (получилось #{rep[:total_seconds]})")
        assert(rep[:today_seconds] == 300, "report.today_seconds берет текущий день (300)")
        assert(rep[:series][:hourly].size == 24, "hourly-серия содержит 24 точки")
        assert(rep[:series][:hourly].last[:label] == "14:00", "hourly-серия заканчивается текущим часом (14:00)")
        hourly_sum = rep[:series][:hourly].sum { |p| p[:seconds] }
        assert(hourly_sum == 900, "hourly-серия берет данные из hourly-бакетов: 600 (29.09 23) + 300 (30.09 00) = 900 (получилось #{hourly_sum})")
        assert(rep[:series][:hourly][8][:label] == "29.09 23:00" && rep[:series][:hourly][8][:seconds] == 600, "вчерашний час подписан с датой и содержит 600 сек")
        assert(rep[:series][:hourly][9][:label] == "00:00" && rep[:series][:hourly][9][:seconds] == 300, "сегодняшний час 00:00 подписан без даты и содержит 300 сек")
        assert(rep[:series][:hourly][0][:label] == "29.09 15:00", "старейшая точка hourly-серии — 29.09 15:00")
        assert(rep[:series][:daily].size == 30, "daily-серия содержит 30 точек")
        assert(rep[:series][:daily].last[:seconds] == 300, "последняя точка daily — сегодня (300)")
        assert(rep[:series][:weekly].size == 12, "weekly-серия содержит 12 точек")
        current_week = rep[:series][:weekly].last
        assert(current_week[:seconds] == 4500, "текущая ISO-неделя содержит начисления 29.09 (4200) + 30.09 (300) = 4500 (получилось #{current_week[:seconds]})")
        assert(rep[:series][:monthly].size == 12, "monthly-серия содержит 12 точек")
        assert(rep[:series][:monthly].last[:seconds] == 4500, "текущий месяц содержит сентябрьские начисления (4500)")
        assert(rep[:series][:yearly].last[:label] == "2026" && rep[:series][:yearly].last[:seconds] == 4560, "годовая серия содержит 2026 = 4560")
        assert(rep[:empty] == false, "report.empty = false после начислений")

        # --- report на пустой статистике ---
        empty_rep = STATS.report(STATS.blank_data, now)
        assert(empty_rep[:empty] == true && empty_rep[:total_seconds] == 0, "report пустой статистики: empty = true")
        assert(empty_rep[:series][:daily].size == 30, "пустой report все равно отдает серии нужной длины")
        assert(STATS.blank?(STATS.blank_data) == true, "blank? распознает пустую статистику")
      end

      def run_project_data_tests
        puts "=========================================================="
        puts "  ProjectData: round-trip work_stats через project.yaml"
        puts "=========================================================="

        Dir.mktmpdir do |tmp|
          yaml_path = File.join(tmp, "project.yaml")

          # --- Начисление и сохранение ---
          pd = PD.new
          assert(pd.work_stats[:total_seconds] == 0, "новый ProjectData имеет пустую статистику")
          pd.accrue_work_stats(1500, Time.new(2026, 9, 29, 10, 0, 0))
          pd.accrue_work_stats(300, Time.new(2026, 9, 30, 11, 30, 0))
          assert(pd.work_stats[:total_seconds] == 1800, "accrue_work_stats суммирует начисления")
          pd.save_to_yaml(yaml_path, include_settings: false)

          written = YAML.safe_load(File.read(yaml_path))
          assert(written.key?("work_stats"), "save_to_yaml пишет секцию work_stats")
          assert(written["work_stats"]["total_seconds"] == 1800, "в YAML записано total_seconds = 1800")

          # --- Загрузка своего project.yaml ---
          pd2 = PD.new
          assert(pd2.load_from_yaml(yaml_path, include_settings: false), "load_from_yaml читает файл")
          assert(pd2.work_stats[:total_seconds] == 1800, "load_from_yaml восстанавливает total_seconds")
          assert(pd2.work_stats[:daily]["2026-09-29"] == 1500, "load_from_yaml восстанавливает дневные бакеты")
          rep = pd2.work_stats_report(Time.new(2026, 9, 30, 12, 0, 0))
          assert(rep[:today_seconds] == 300 && rep[:total_seconds] == 1800, "work_stats_report отдает сводные данные")

          # --- Импорт YAML: статистика не переносится ---
          pd3 = PD.new
          pd3.accrue_work_stats(9999, Time.new(2026, 9, 28, 9, 0, 0))
          assert(pd3.load_from_yaml(yaml_path, include_settings: false, include_work_stats: false), "импорт читает файл (include_work_stats: false)")
          assert(pd3.work_stats[:total_seconds] == 9999, "импорт YAML игнорирует чужую секцию work_stats")

          # --- Сброс: секция не пишется вовсе ---
          pd2.reset_work_stats!
          assert(STATS.blank?(pd2.work_stats), "reset_work_stats! очищает статистику")
          pd2.save_to_yaml(yaml_path, include_settings: false)
          assert(!YAML.safe_load(File.read(yaml_path)).key?("work_stats"), "пустая статистика не попадает в project.yaml")

          # --- Отчет пустого проекта ---
          empty_payload = pd2.work_stats_report
          assert(empty_payload[:empty] == true, "work_stats_report нового проекта помечен пустым")
        end

        puts "=========================================================="
        puts "  Автозаполнение workflow.total_duration из статистики"
        puts "=========================================================="

        # --- Форматирование длительности ---
        assert(STATS.format_duration(0) == "", "format_duration(0) — пустая строка")
        assert(STATS.format_duration(45 * 60) == "45 мин", "format_duration меньше часа — минуты")
        assert(STATS.format_duration(3600) == "1 ч", "format_duration час ровно — без минут")
        assert(STATS.format_duration(2 * 3600 + 30 * 60) == "2 ч 30 мин", "format_duration часы + минуты")
        assert(STATS.format_duration(26 * 3600) == "1 д 2 ч", "format_duration больше суток — дни и часы")
        assert(STATS.format_duration(24 * 3600) == "1 д", "format_duration сутки ровно — без часов")

        # --- Начисление заполняет поле, ручное значение затирается ---
        pd4 = PD.new
        pd4.workflow[:total_duration] = "ручное значение"
        pd4.accrue_work_stats(9000, Time.new(2026, 9, 29, 10, 0, 0)) # 2 ч 30 мин
        assert(pd4.workflow[:total_duration] == "2 ч 30 мин", "accrue_work_stats записывает итог в workflow.total_duration")
        assert(pd4.project_info[:total_duration] == "2 ч 30 мин", "прокси project_info синхронизирован с автозначением")

        # --- apply_payload! не затирает автозначение данными формы ---
        pd4.accrue_work_stats(26 * 3600, Time.new(2026, 9, 30, 10, 0, 0)) # итого 28 ч 30 мин
        assert(pd4.workflow[:total_duration] == "1 д 4 ч", "после новых начислений длительность пересчитана (1 д 4 ч)")
        pd4.apply_payload!(workflow: { total_duration: "вручную из формы" })
        assert(pd4.workflow[:total_duration] == "1 д 4 ч", "apply_payload! сохраняет автозначение из статистики")

        # --- Payload статистики для диалога несет автозначение длительности ---
        stats_payload = Dialog::ExportDialog.build_work_stats_payload(pd4)
        assert(stats_payload[:total_duration] == "1 д 4 ч", "build_work_stats_payload отдает автозначение total_duration из статистики")

        # --- Пустая статистика: поле остается ручным ---
        pd5 = PD.new
        pd5.apply_payload!(workflow: { total_duration: "9 дней / 45 часов" })
        assert(pd5.workflow[:total_duration] == "9 дней / 45 часов", "при пустой статистике ручное значение сохраняется")
        manual_payload = Dialog::ExportDialog.build_work_stats_payload(pd5)
        assert(manual_payload[:total_duration] == "9 дней / 45 часов", "payload статистики при пустом учете отдает ручное значение длительности")

        # --- Payload без проекта (нет активной модели) ---
        nil_payload = Dialog::ExportDialog.build_work_stats_payload(nil)
        assert(nil_payload[:total_duration] == "", "payload статистики без проекта отдает пустую total_duration")

        # --- Загрузка project.yaml восстанавливает автозначение ---
        Dir.mktmpdir do |tmp|
          yaml_path = File.join(tmp, "project.yaml")
          pd4.save_to_yaml(yaml_path, include_settings: false)
          written = YAML.safe_load(File.read(yaml_path))
          assert(written["workflow"]["total_duration"] == "1 д 4 ч", "в project.yaml пишется автозначение длительности")

          pd6 = PD.new
          pd6.load_from_yaml(yaml_path, include_settings: false)
          assert(pd6.workflow[:total_duration] == "1 д 4 ч", "load_from_yaml восстанавливает автозначение")

          # Сброс статистики возвращает полю ручное управление
          pd6.reset_work_stats!
          pd6.apply_payload!(workflow: { total_duration: "снова вручную" })
          assert(pd6.workflow[:total_duration] == "снова вручную", "после сброса статистики поле снова ручное")
        end
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  DN1Code::ExportPdf2::WorkStatsStandaloneRunner.new.run_all
end
