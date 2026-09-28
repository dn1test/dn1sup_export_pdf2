# frozen_string_literal: true

# -------------------------------------------------------------------------------
# Проверка наборов шаблонов (вкладка «Шаблоны» → низ сайдбара «Наборы шаблонов»):
# сохранение/загрузка/удаление снимков custom_layouts в config/layout_sets/*.yaml.
#
# Схема файла набора повторяет layout.yaml (корневой ключ layout) + метаданные
# name/saved_at, поэтому набор читается штатным load_from_layout_yaml, а загрузка
# набора сразу перезаписывает layout.yaml.
#
# Тест перенаправляет папку наборов и PROGRAM_LAYOUT_FILE во временную папку,
# чтобы не трогать реальные config-файлы пользователя.
#
# Запуск отдельно:
#   ruby -I dn1c_export_pdf2 dn1c_export_pdf2/test/test_template_sets.rb
# -------------------------------------------------------------------------------

require_relative "mock_sketchup"
require_relative "../main"
require "tmpdir"
require "fileutils"
require "yaml"

module DN1Code
  module ExportPdf2
    class TemplateSetsStandaloneRunner
      PD = ::DN1Code::ExportPdf2::Model::ProjectData

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

      def make_layouts(extra = {})
        base = {
          cover: {
            name: "Титульный лист", _name: "Титульный лист",
            image_4_3: { x: 25.0, y: 12.0, w: 50.0, h: 82.0, visible: true,
                         content: "render_viewport", aspect_ratio: "4:3", scale_pct: 100 },
            params: []
          },
          general: {
            name: "Общий вид", _name: "Общий вид",
            image_4_3: { x: 20.0, y: 10.0, w: 60.0, h: 85.0, visible: true,
                         content: "render_viewport", aspect_ratio: "16:9", scale_pct: 100 },
            params: [{ id: "room", label: "Помещение", source: "project.room_name",
                       show_label: true, font_size: 8, visible: true }]
          }
        }
        base.merge(extra)
      end

      def run_all
        Dir.mktmpdir do |tmp|
          sets_dir    = File.join(tmp, "layout_sets")
          layout_file = File.join(tmp, "layout.yaml")

          # Перенаправляем PROGRAM_LAYOUT_FILE и template_sets_dir во временную папку
          orig_layout_const = PD::PROGRAM_LAYOUT_FILE
          orig_sets_method  = PD.instance_method(:template_sets_dir)
          PD.send(:remove_const, :PROGRAM_LAYOUT_FILE)
          PD.const_set(:PROGRAM_LAYOUT_FILE, layout_file)
          PD.class_eval { define_method(:template_sets_dir) { sets_dir } }

          begin
            run_tests(sets_dir, layout_file)
          ensure
            PD.send(:remove_const, :PROGRAM_LAYOUT_FILE)
            PD.const_set(:PROGRAM_LAYOUT_FILE, orig_layout_const)
            PD.class_eval { define_method(:template_sets_dir, orig_sets_method) }
          end
        end

        puts "=========================================================="
        puts "  ИТОГИ ТЕСТИРОВАНИЯ: Успешно: #{@passed}, Ошибок: #{@failed}"
        puts "=========================================================="
        exit(@failed.zero? ? 0 : 1)
      end

      def run_tests(sets_dir, layout_file)
        puts "=========================================================="
        puts "  Проверка наборов шаблонов (config/layout_sets)"
        puts "=========================================================="

        # --- Очистка имени набора ---
        pd = PD.new
        clean = pd.sanitize_template_set_name('  Проект: "Кухни" <v2>  ')
        assert(!clean.match?(/[\\\/:*?"<>|]/), "sanitize_template_set_name убирает недопустимые символы (#{clean.inspect})")
        assert(pd.sanitize_template_set_name("x" * 100).length == 80, "sanitize_template_set_name ограничивает длину 80 символами")

        # --- Сохранение и список ---
        assert(pd.save_template_set("Кухни", make_layouts), "save_template_set сохраняет набор")
        assert(File.exist?(File.join(sets_dir, "Кухни.yaml")), "файл набора создан (Кухни.yaml)")

        sets = pd.list_template_sets
        assert(sets.size == 1, "list_template_sets видит один набор")
        assert(sets[0][:name] == "Кухни", "имя набора в списке совпадает")
        assert(sets[0][:templates_count] == 2, "число шаблонов в наборе верное (2)")
        assert(!sets[0][:saved_at].to_s.empty?, "дата сохранения заполнена")

        # --- Загрузка набора заменяет текущие шаблоны и пишет layout.yaml ---
        pd.pdf_settings[:custom_layouts] = make_layouts(bedroom: {
                                                          name: "Спальня", _name: "Спальня",
                                                          image_4_3: { x: 30.0, y: 15.0, w: 40.0, h: 70.0,
                                                                       visible: true, content: "render_viewport",
                                                                       aspect_ratio: "4:3", scale_pct: 100 },
                                                          params: []
                                                        })
        loaded = pd.load_template_set("кухни")
        assert(!loaded.nil?, "load_template_set находит набор без учета регистра")
        keys = loaded.keys.map(&:to_s).sort
        assert(keys == %w[cover general], "загрузка заменяет ВСЕ шаблоны содержимым набора (#{keys.inspect})")
        assert(loaded[:cover].key?(:image_4_3), "загруженный шаблон содержит блок image_4_3")
        assert(loaded[:cover][:image_4_3][:scale_pct] == 100, "нормализация image_4_3 выполнена (scale_pct)")

        yaml = YAML.safe_load(File.read(layout_file))
        assert(yaml.is_a?(Hash) && yaml["layout"].key?("cover"), "загрузка набора сразу перезаписывает layout.yaml")

        # --- Перезапись существующего набора ---
        single = { blank: { name: "Пустой", _name: "Пустой",
                            image_4_3: { x: 10.0, y: 10.0, w: 80.0, h: 80.0, visible: true,
                                         content: "render_viewport", aspect_ratio: "4:3", scale_pct: 100 },
                            params: [] } }
        assert(pd.save_template_set("Кухни", single), "повторное сохранение с тем же именем перезаписывает файл")
        sets = pd.list_template_sets
        assert(sets.size == 1, "после перезаписи в списке по-прежнему один набор")
        assert(sets[0][:templates_count] == 1, "перезаписанный набор содержит новое число шаблонов")
        assert(pd.load_template_set("Кухни").keys.map(&:to_s) == ["blank"], "загрузка возвращает перезаписанное содержимое")

        # --- Битый YAML пропускается ---
        File.write(File.join(sets_dir, "broken.yaml"), "{ [ : некорректный yaml")
        sets = pd.list_template_sets
        assert(sets.size == 1 && sets[0][:name] == "Кухни", "битый файл набора не попадает в список")
        assert(pd.load_template_set("broken").nil?, "загрузка битого файла возвращает nil (fallback по имени файла допустим)")

        # --- Удаление ---
        assert(pd.delete_template_set("Кухни"), "delete_template_set удаляет набор")
        assert(pd.list_template_sets.empty?, "после удаления список пуст")
        assert(!File.exist?(File.join(sets_dir, "Кухни.yaml")), "файл набора удален с диска")
        assert(pd.delete_template_set("Кухни") == false, "повторное удаление отсутствующего набора возвращает false")
        assert(pd.load_template_set("Кухни").nil?, "загрузка отсутствующего набора возвращает nil")

        # --- Пустое имя не сохраняется ---
        assert(pd.save_template_set("   ", make_layouts) == false, "сохранение с пустым именем отклоняется")
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  DN1Code::ExportPdf2::TemplateSetsStandaloneRunner.new.run_all
end
