# frozen_string_literal: true

# -------------------------------------------------------------------------------
# Проверка списка стадий проекта по умолчанию (config/settings.yaml -> default_stadia).
#
# Регрессия: @workflow[:stadia] строился в initialize ДО load_program_settings,
# поэтому первый новый проект после перезапуска SketchUp получал встроенный
# заводской список, а не сохранённый кнопкой «Сохранить» (saveStadiaDefault).
#
# Запуск отдельно:
#   ruby -I dn1c_export_pdf2 dn1c_export_pdf2/test/test_stadia_default.rb
# -------------------------------------------------------------------------------

require_relative "mock_sketchup"
require_relative "../main"
require "tmpdir"
require "fileutils"
require "yaml"

module DN1Code
  module ExportPdf2
    class StadiaDefaultRunner
      PD = ::DN1Code::ExportPdf2::Model::ProjectData

      ORIGINAL_CONFIG_DIR     = PD::PLUGIN_CONFIG_DIR
      ORIGINAL_SETTINGS_FILE  = PD::PROGRAM_SETTINGS_FILE
      ORIGINAL_LAYOUT_FILE    = PD::PROGRAM_LAYOUT_FILE

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

      # Перенаправляет конфиг плагина во временную папку и сбрасывает классовую
      # переменную стадий — имитация свежего запуска SketchUp
      def with_fresh_config(settings_yaml = nil)
        Dir.mktmpdir do |tmp|
          PD.send(:remove_const, :PLUGIN_CONFIG_DIR)
          PD.send(:remove_const, :PROGRAM_SETTINGS_FILE)
          PD.send(:remove_const, :PROGRAM_LAYOUT_FILE)
          PD.const_set(:PLUGIN_CONFIG_DIR, tmp)
          PD.const_set(:PROGRAM_SETTINGS_FILE, File.join(tmp, "settings.yaml"))
          PD.const_set(:PROGRAM_LAYOUT_FILE, File.join(tmp, "layout.yaml"))

          if settings_yaml
            FileUtils.mkdir_p(tmp)
            File.write(PD::PROGRAM_SETTINGS_FILE, settings_yaml)
          end

          PD.instance_variable_set(:@stadia_default_names, nil)
          yield
        end
      ensure
        PD.send(:remove_const, :PLUGIN_CONFIG_DIR)
        PD.send(:remove_const, :PROGRAM_SETTINGS_FILE)
        PD.send(:remove_const, :PROGRAM_LAYOUT_FILE)
        PD.const_set(:PLUGIN_CONFIG_DIR, ORIGINAL_CONFIG_DIR)
        PD.const_set(:PROGRAM_SETTINGS_FILE, ORIGINAL_SETTINGS_FILE)
        PD.const_set(:PROGRAM_LAYOUT_FILE, ORIGINAL_LAYOUT_FILE)
      end

      def stadia_names(pd)
        pd.workflow[:stadia].map { |s| s[:name] }
      end

      def run_all
        run_init_order_regression
        run_save_restart_cycle
        run_builtin_fallback
        run_normalize_keeps_statuses

        puts "=========================================================="
        puts "  ИТОГИ ТЕСТИРОВАНИЯ: Успешно: #{@passed}, Ошибок: #{@failed}"
        puts "=========================================================="
        exit(@failed.zero? ? 0 : 1)
      end

      # --- Главный регресс: yaml уже сохранён, но это первая ProjectData  -----
      # сессии (классовая переменная пуста до initialize)
      def run_init_order_regression
        puts "=========================================================="
        puts "  Регрессия порядка инициализации: settings.yaml -> новый проект"
        puts "=========================================================="

        yaml = { "pdf_settings" => {}, "api_targets" => [],
                 "default_stadia" => ["Эскиз", "Согласование"] }.to_yaml
        with_fresh_config(yaml) do
          pd = PD.new
          assert(stadia_names(pd) == ["Эскиз", "Согласование"],
                 "новый ProjectData берёт стадии из settings.yaml (получилось #{stadia_names(pd).inspect})")
          assert(pd.workflow[:stadia].all? { |s| s[:status] == false },
                 "галочки сохранённого дефолта сброшены")
        end
      end

      # --- Полный цикл пользователя: сохранить -> «перезапуск» -> новый проект
      def run_save_restart_cycle
        puts "=========================================================="
        puts "  Цикл: set_stadia_default -> save -> свежая сессия -> ProjectData"
        puts "=========================================================="

        with_fresh_config(nil) do
          pd = PD.new
          saved = PD.set_stadia_default(["Каркас", "Чистовая сборка", " Монтаж "])
          assert(saved == ["Каркас", "Чистовая сборка", "Монтаж"],
                 "set_stadia_default нормализует имена (получилось #{saved.inspect})")
          assert(pd.save_program_settings == true, "save_program_settings пишет settings.yaml")

          written = YAML.safe_load(File.read(PD::PROGRAM_SETTINGS_FILE))
          assert(written["default_stadia"] == ["Каркас", "Чистовая сборка", "Монтаж"],
                 "в settings.yaml записан сохранённый список")

          # Перезапуск SketchUp: классовая переменная пуста
          PD.instance_variable_set(:@stadia_default_names, nil)
          fresh = PD.new
          assert(stadia_names(fresh) == ["Каркас", "Чистовая сборка", "Монтаж"],
                 "после «перезапуска» новый проект получает сохранённый список (получилось #{stadia_names(fresh).inspect})")
        end
      end

      # --- Пустой/отсутствующий ключ -> встроенный список ----------------------
      def run_builtin_fallback
        puts "=========================================================="
        puts "  Фолбэк: пустой default_stadia -> встроенный список"
        puts "=========================================================="

        with_fresh_config({ "pdf_settings" => {}, "api_targets" => [], "default_stadia" => [] }.to_yaml) do
          pd = PD.new
          builtin = pd.default_builtin_stadia.map { |s| s[:name] }
          assert(stadia_names(pd) == builtin,
                 "пустой default_stadia даёт встроенный список (#{builtin.size} шт.)")
        end

        with_fresh_config(nil) do
          pd = PD.new
          assert(pd.default_stadia == pd.default_builtin_stadia,
                 "без settings.yaml используется встроенный список")
        end
      end

      # --- Галочки существующего проекта не сбрасываются ------------------------
      def run_normalize_keeps_statuses
        puts "=========================================================="
        puts "  normalize_stadia сохраняет статусы непустого списка проекта"
        puts "=========================================================="

        with_fresh_config(nil) do
          pd = PD.new
          pd.workflow[:stadia] = [{ name: "Утвержден", status: true }, { name: "Оплачен", status: false }]
          norm = pd.normalize_stadia(pd.workflow[:stadia])
          assert(norm == [{ name: "Утвержден", status: true }, { name: "Оплачен", status: false }],
                 "normalize_stadia не трогает существующий список и галочки (получилось #{norm.inspect})")
        end
      end
    end
  end
end

DN1Code::ExportPdf2::StadiaDefaultRunner.new.run_all
