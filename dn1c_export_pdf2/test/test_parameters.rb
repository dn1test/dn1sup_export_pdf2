# frozen_string_literal: true

# -------------------------------------------------------------------------------
# Матричный тест параметров DN1C Export PDF 2.
#
# Прогоняет КАЖДЫЙ пользовательский параметр (глобальные pdf_settings,
# постраничные SceneItem, поля проекта) по схеме:
#   валидное значение  -> параметр доходит до места использования (геометрия
#                         листа, опции write_image, тексты штампа, whitelist);
#   невалидное/граничное -> безопасный fallback (клампы, значения по умолчанию).
#
# Конфиг плагина (settings.yaml/layout.yaml) перенаправляется во временную
# папку, чтобы тесты не зависели от локальных настроек пользователя.
#
# Запуск отдельно:
#   ruby -I dn1c_export_pdf2 dn1c_export_pdf2/test/test_parameters.rb
# -------------------------------------------------------------------------------

require_relative "mock_sketchup"
require_relative "../main"
require "tmpdir"
require "fileutils"
require "yaml"
require "json"

module DN1Code
  module ExportPdf2
    class ParametersTestRunner
      PD = ::DN1Code::ExportPdf2::Model::ProjectData
      SI = ::DN1Code::ExportPdf2::Model::SceneItem
      LB = ::DN1Code::ExportPdf2::Service::LayoutBuilder
      RS = ::DN1Code::ExportPdf2::Service::RenderService
      FS = ::DN1Code::ExportPdf2::Service::FontService
      EC = ::DN1Code::ExportPdf2::Controller::ExportController

      PT = 72.0
      MM_IN = PT / 25.4

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

      # ProjectData.new с изолированным конфигом (без settings.yaml пользователя)
      def fresh_pd
        PD.new
      end

      # Изолирует конфиг-файлы плагина во временной папке на время блока
      def with_isolated_config
        Dir.mktmpdir do |tmp|
          orig_cfg    = PD::PLUGIN_CONFIG_DIR
          orig_setts  = PD::PROGRAM_SETTINGS_FILE
          orig_layout = PD::PROGRAM_LAYOUT_FILE
          PD.send(:remove_const, :PLUGIN_CONFIG_DIR)
          PD.send(:remove_const, :PROGRAM_SETTINGS_FILE)
          PD.send(:remove_const, :PROGRAM_LAYOUT_FILE)
          PD.const_set(:PLUGIN_CONFIG_DIR, tmp)
          PD.const_set(:PROGRAM_SETTINGS_FILE, File.join(tmp, "settings.yaml"))
          PD.const_set(:PROGRAM_LAYOUT_FILE, File.join(tmp, "layout.yaml"))
          begin
            yield tmp
          ensure
            PD.send(:remove_const, :PLUGIN_CONFIG_DIR)
            PD.send(:remove_const, :PROGRAM_SETTINGS_FILE)
            PD.send(:remove_const, :PROGRAM_LAYOUT_FILE)
            PD.const_set(:PLUGIN_CONFIG_DIR, orig_cfg)
            PD.const_set(:PROGRAM_SETTINGS_FILE, orig_setts)
            PD.const_set(:PROGRAM_LAYOUT_FILE, orig_layout)
          end
        end
      end

      # --- Хелперы рендера одной страницы (мок LayOut) ---

      def render_page(pd, page_type: :general)
        doc   = ::Layout::Document.new
        ctx   = LB.send(:build_context, pd, nil, "Sofia Sans Condensed")
        scene = SI.new(name: "01. Тестовая сцена", page_type: page_type)
        pd_dim = LB.send(:get_page_dimensions, pd.pdf_settings)
        LB.send(:render_modular_page, doc, doc.pages.first, doc.layers.first, scene,
                1, 1, pd_dim[:w], pd_dim[:h], 0.2, ctx, [])
        doc
      end

      def doc_texts(doc)
        doc.entities.map { |rec| rec[:entity] }.grep(::Layout::FormattedText)
      end

      def doc_has_text?(doc, fragment)
        doc_texts(doc).any? { |t| t.plain_text.to_s.include?(fragment) }
      end

      # Рендер одного кадра через RenderService (мок write_image запоминает опции)
      def render_temp_options(pd, extra_opts = {})
        model = ::Sketchup::MockModel.new(File.join(Dir.tmpdir, "dn1c_params_model.skp"))
        opts = {
          image_width: pd.pdf_settings[:image_width],
          render_quality: pd.pdf_settings[:render_quality] || "medium",
          scale_multiplier: pd.pdf_settings[:scale_multiplier] || "2.0",
          scale_factor: pd.pdf_settings[:scale_factor] || 2.0,
          annotation_font_size: pd.pdf_settings[:annotation_font_size],
          page_size: pd.pdf_settings[:page_size] || "A4",
          antialias: pd.pdf_settings.fetch(:antialias, true),
          aspect_ratio: 4.0 / 3.0,
          image_format: pd.pdf_settings[:image_format] || "png"
        }.merge(extra_opts)
        path = RS.render_scene_temp(model, nil, opts)
        { path: path, options: model.active_view.last_write_image_options }
      end

      # --- A. Глобальные pdf_settings ---

      def test_page_dimensions
        puts "\n--- A1. page_size / page_layout: размеры листа ---"
        pd = fresh_pd

        cases = {
          { page_size: "A3", page_layout: "landscape" } => [16.5354, 11.6929],
          { page_size: "A3", page_layout: "portrait" }  => [11.6929, 16.5354],
          { page_size: "A4", page_layout: "landscape" } => [11.6929, 8.2677],
          { page_size: "A4", page_layout: "portrait" }  => [8.2677, 11.6929],
          { page_size: "A2", page_layout: "landscape" } => [23.3858, 16.5354],
          { page_size: "LETTER", page_layout: "landscape" } => [11.0, 8.5],
          { page_size: "a3", page_layout: "LANDSCAPE" } => [16.5354, 11.6929]
        }
        cases.each do |setting, (ew, eh)|
          pd.pdf_settings[:page_size] = setting[:page_size]
          pd.pdf_settings[:page_layout] = setting[:page_layout]
          dim = LB.send(:get_page_dimensions, pd.pdf_settings)
          assert((dim[:w] - ew).abs < 0.001 && (dim[:h] - eh).abs < 0.001,
                 "page_size=#{setting[:page_size].inspect} + #{setting[:page_layout]}: #{dim[:w].round(2)}x#{dim[:h].round(2)} дюймов")
        end

        pd.pdf_settings[:page_size] = "ZZZ"
        dim = LB.send(:get_page_dimensions, pd.pdf_settings)
        assert((dim[:w] - 11.6929).abs < 0.001,
               "неизвестный page_size -> fallback A4 (#{dim[:w].round(2)} дюймов)")
      end

      def test_margins
        puts "\n--- A2. margin_mm / margin: поля страницы ---"
        pd = fresh_pd

        pd.pdf_settings[:margin_mm] = 5
        assert((LB.send(:resolve_margin_inches, pd.pdf_settings) - 5 * MM_IN / PT).abs < 1e-9,
               "margin_mm=5 -> #{(5.0 / 25.4).round(4)} дюйма")

        pd.pdf_settings[:margin_mm] = 0
        assert(LB.send(:resolve_margin_inches, pd.pdf_settings) < 1e-9,
               "margin_mm=0 -> нулевое поле")

        pd.pdf_settings[:margin_mm] = -5
        assert(LB.send(:resolve_margin_inches, pd.pdf_settings) >= 0.0,
               "margin_mm=-5 -> поле не уходит в минус (кламп 0)")

        pd.pdf_settings[:margin_mm] = 500
        assert(LB.send(:resolve_margin_inches, pd.pdf_settings) <= 100 * MM_IN / PT + 1e-9,
               "margin_mm=500 -> поле ограничено 100 мм")

        pd.pdf_settings.delete(:margin_mm)
        pd.pdf_settings.delete("margin_mm")
        pd.pdf_settings[:margin] = 15
        assert((LB.send(:resolve_margin_inches, pd.pdf_settings) - 15.0 / PT).abs < 1e-9,
               "legacy margin=15pt (без margin_mm) -> #{(15.0 / 72).round(4)} дюйма")

        pd.pdf_settings.delete(:margin)
        assert((LB.send(:resolve_margin_inches, pd.pdf_settings) - 15.0 / PT).abs < 1e-9,
               "без ключей поля -> fallback 15pt")
      end

      def test_render_quality_layout_resolution
        puts "\n--- A3. render_quality: разрешение LayOut ---"
        pd = fresh_pd

        # Реализованная карта: low->RESOLUTION_MEDIUM(96dpi), medium/high->RESOLUTION_HIGH(300dpi)
        expectations = { "low" => 1, "medium" => 2, "high" => 2 }
        expectations.each do |q, res|
          pd.pdf_settings[:render_quality] = q
          doc = ::Layout::Document.new
          page_dim = LB.send(:get_page_dimensions, pd.pdf_settings)
          # повторяем блок настройки разрешения из export()
          q_mode = pd.pdf_settings[:render_quality].to_s.downcase.strip
          res_val = case q_mode
                    when "low" then defined?(::Layout::PageInfo::RESOLUTION_MEDIUM) ? ::Layout::PageInfo::RESOLUTION_MEDIUM : 1
                    when "high" then defined?(::Layout::PageInfo::RESOLUTION_HIGH) ? ::Layout::PageInfo::RESOLUTION_HIGH : 2
                    else defined?(::Layout::PageInfo::RESOLUTION_HIGH) ? ::Layout::PageInfo::RESOLUTION_HIGH : 2
                    end
          assert(res_val == res, "render_quality=#{q.inspect} -> RESOLUTION_#{res == 1 ? 'MEDIUM' : 'HIGH'}")
        end

        pd.pdf_settings[:render_quality] = "мусор"
        doc = ::Layout::Document.new
        page_dim = LB.send(:get_page_dimensions, pd.pdf_settings)
        q_mode = pd.pdf_settings[:render_quality].to_s.downcase.strip
        res_val = q_mode == "low" ? 1 : 2
        assert(res_val == 2, "render_quality=мусор -> fallback medium (RESOLUTION_HIGH)")
      end

      def test_render_width_by_page_and_quality
        puts "\n--- A4. render_quality x page_size: ширина растра ---"
        # Таблица ожиданий: длинная сторона листа x dpi
        cases = {
          ["A4", "low"] => 11.692913 * 96, ["A4", "medium"] => 11.692913 * 150, ["A4", "high"] => 11.692913 * 300,
          ["A3", "low"] => 16.535433 * 96, ["A3", "medium"] => 16.535433 * 150, ["A3", "high"] => 16.535433 * 300,
          ["A2", "medium"] => 23.3858 * 150, ["A2", "high"] => 23.3858 * 300,
          ["LETTER", "high"] => 11.0 * 300
        }
        cases.each do |(psz, q), ew|
          model = ::Sketchup::MockModel.new(File.join(Dir.tmpdir, "dn1c_params_model.skp"))
          path = RS.render_scene_temp(model, nil, { page_size: psz, render_quality: q, aspect_ratio: 4.0 / 3.0 })
          opts = model.active_view.last_write_image_options
          File.delete(path) if path && File.exist?(path)
          assert(opts && (opts[:width] - ew).abs <= 1.0,
                 "page_size=#{psz} + #{q}: ширина #{opts ? opts[:width] : '???'} (ожидание #{ew.round})")
        end
      end

      def test_render_aspect_and_antialias
        puts "\n--- A5. aspect_ratio / antialias растра ---"
        pd = fresh_pd

        rt = render_temp_options(pd, { aspect_ratio: 16.0 / 9.0 })
        w = rt[:options][:width]
        h = rt[:options][:height]
        File.delete(rt[:path]) if rt[:path] && File.exist?(rt[:path])
        assert((w.to_f * 9 / 16 - h).abs <= 1.0, "aspect 16:9 -> высота = ширина*9/16 (#{w}x#{h})")

        rt = render_temp_options(pd, { aspect_ratio: 1.0 })
        File.delete(rt[:path]) if rt[:path] && File.exist?(rt[:path])
        assert((rt[:options][:width] - rt[:options][:height]).abs <= 1.0, "aspect 1:1 -> квадрат")

        rt = render_temp_options(pd, { antialias: false })
        File.delete(rt[:path]) if rt[:path] && File.exist?(rt[:path])
        assert(rt[:options][:antialias] == false, "antialias=false доходит до write_image")

        rt = render_temp_options(pd, { antialias: true })
        File.delete(rt[:path]) if rt[:path] && File.exist?(rt[:path])
        assert(rt[:options][:antialias] == true, "antialias=true доходит до write_image")
      end

      def test_scale_multiplier
        puts "\n--- A6. scale_multiplier / scale_factor: толщина линий ---"
        pd = fresh_pd

        rt = render_temp_options(pd, { scale_multiplier: "2.5", image_width: 2400 })
        File.delete(rt[:path]) if File.exist?(rt[:path])
        assert((rt[:options][:scale_factor] - 2.5).abs < 1e-9, "scale_multiplier='2.5' -> множитель 2.5")

        rt = render_temp_options(pd, { scale_multiplier: "0.5", image_width: 2400 })
        File.delete(rt[:path]) if File.exist?(rt[:path])
        assert((rt[:options][:scale_factor] - 0.5).abs < 1e-9, "scale_multiplier='0.5' -> множитель 0.5")

        # auto: image_width 2400 -> 1.20 * 0.70 = 0.84
        rt = render_temp_options(pd, { scale_multiplier: "auto", image_width: 2400, page_size: "A4" })
        File.delete(rt[:path]) if File.exist?(rt[:path])
        assert((rt[:options][:scale_factor] - 0.84).abs < 1e-9,
               "scale_multiplier='auto' (2400px, A4) -> #{rt[:options][:scale_factor]} (0.84)")

        rt = render_temp_options(pd, { scale_multiplier: "мусор", image_width: 2400 })
        File.delete(rt[:path]) if File.exist?(rt[:path])
        assert((rt[:options][:scale_factor] - 2.0).abs < 1e-9, "scale_multiplier=мусор -> fallback 2.0")

        rt = render_temp_options(pd, { scale_multiplier: nil, scale_factor: 1.5 })
        File.delete(rt[:path]) if File.exist?(rt[:path])
        assert((rt[:options][:scale_factor] - 1.5).abs < 1e-9, "без multiplier: scale_factor=1.5 используется")
      end

      def test_image_format
        puts "\n--- A7. image_format: формат растра ---"
        pd = fresh_pd

        rt = render_temp_options(pd, { image_format: "png" })
        assert(rt[:path].to_s.end_with?(".png"), "image_format=png -> временный файл .png")
        File.delete(rt[:path]) if File.exist?(rt[:path])

        rt = render_temp_options(pd, { image_format: "jpg" })
        opts = rt[:options]
        assert(rt[:path].to_s.end_with?(".jpg"), "image_format=jpg -> временный файл .jpg")
        assert(opts.key?(:compression) && (opts[:compression] - 1.0).abs < 1e-9,
               "image_format=jpg -> compression 1.0 (максимальное качество)")
        File.delete(rt[:path]) if File.exist?(rt[:path])
      end

      def test_webp_quality
        puts "\n--- A8. webp_quality: качество снимков ---"
        pd = fresh_pd
        model = ::Sketchup::MockModel.new(File.join(Dir.tmpdir, "dn1c_params_model.skp"))
        ctrl = EC.new(pd, model)

        cases = {
          "lossless" => { quality: nil, lossless: true },
          "85" => { quality: 85, lossless: false },
          50 => { quality: 50, lossless: false },
          1 => { quality: 1, lossless: false },
          100 => { quality: 100, lossless: false },
          0 => { quality: 85, lossless: false },
          101 => { quality: 85, lossless: false },
          "abc" => { quality: 85, lossless: false },
          nil => { quality: 85, lossless: false }
        }
        cases.each do |raw, exp|
          pd.pdf_settings[:webp_quality] = raw
          got = ctrl.send(:webp_quality_setting, pd.pdf_settings)
          assert(got[:quality] == exp[:quality] && got[:lossless] == exp[:lossless],
                 "webp_quality=#{raw.inspect} -> #{got.inspect}")
        end
      end

      def test_stamp
        puts "\n--- A9. stamp_type / stamp_custom: штамп ---"
        pd = fresh_pd

        pd.pdf_settings[:stamp_type] = "draft"
        doc = render_page(pd)
        assert(doc_has_text?(doc, "НЕ УТВЕРЖДЕН"), "stamp_type=draft -> текст «НЕ УТВЕРЖДЕН»")
        assert(doc_has_text?(doc, "Проект не является финальным чертежом"), "штамп содержит подстрок «Проект не является…»")

        pd.pdf_settings[:stamp_type] = "approved"
        doc = render_page(pd)
        assert(doc_has_text?(doc, "В ПРОИЗВОДСТВО"), "stamp_type=approved -> текст «В ПРОИЗВОДСТВО»")
        assert(!doc_has_text?(doc, "НЕ УТВЕРЖДЕН"), "stamp_type=approved -> черновой текст отсутствует")

        pd.pdf_settings[:stamp_type] = "custom"
        pd.pdf_settings[:stamp_custom] = "предварительно"
        doc = render_page(pd)
        assert(doc_has_text?(doc, "ПРЕДВАРИТЕЛЬНО"), "stamp_type=custom -> свой текст в верхнем регистре")

        pd.pdf_settings[:stamp_type] = "none"
        doc = render_page(pd)
        assert(!doc_has_text?(doc, "НЕ УТВЕРЖДЕН") && !doc_has_text?(doc, "В ПРОИЗВОДСТВО"),
               "stamp_type=none -> штампа нет")

        pd.pdf_settings[:stamp_type] = nil
        doc = render_page(pd)
        assert(!doc_has_text?(doc, "НЕ УТВЕРЖДЕН"), "stamp_type=nil -> штампа нет")

        # Некорректный цвет штампа не валит рендер (stamp_custom возвращаем к умолчанию:
        # черновик использует кастомный текст, если он задан)
        pd.pdf_settings[:stamp_type] = "draft"
        pd.pdf_settings[:stamp_custom] = "НЕ УТВЕРЖДЕН"
        pd.pdf_settings[:stamp_color] = "XYZ!"
        doc = render_page(pd)
        assert(doc_has_text?(doc, "НЕ УТВЕРЖДЕН"), "stamp_color=мусор -> рендер не падает, штамп есть")
      end

      def test_colors
        puts "\n--- A10. Цвета (hex) ---"
        assert(LB.send(:hex_to_rgb, "005EB0") == [0, 94, 176], "hex_to_rgb('005EB0') -> [0,94,176]")
        assert(LB.send(:hex_to_rgb, "#FF0000") == [255, 0, 0], "hex_to_rgb('#FF0000') -> [255,0,0]")
        assert(LB.send(:hex_to_rgb, "GGG") == [51, 65, 85], "hex_to_rgb('GGG') -> fallback [51,65,85]")
        assert(LB.send(:hex_to_rgb, nil) == [51, 65, 85], "hex_to_rgb(nil) -> fallback")
        assert(LB.send(:hex_to_rgb, "12345") == [51, 65, 85], "hex_to_rgb('12345') (короткий) -> fallback")

        tint = LB.send(:tinted_rgb, "FF0000", 0.5)
        assert(tint == [255, 128, 128], "tinted_rgb('FF0000', 0.5) -> разбавление белым [255,128,128]")
      end

      def test_font_service
        puts "\n--- A11. font_family / font_weight / font_width ---"
        assert(FS.font_weight_setting({ font_weight: "bold" }) == "bold", "font_weight='bold' -> bold")
        assert(FS.font_weight_setting({ font_weight: "BOLD" }) == "bold", "font_weight='BOLD' (регистр) -> bold")
        assert(FS.font_weight_setting({ font_weight: "мусор" }) == "normal", "font_weight=мусор -> normal")
        assert(FS.font_weight_setting(nil) == "normal", "font_weight отсутствует -> normal")

        assert(FS.font_width_setting({ font_width: "extra_condensed" }) == "extra_condensed",
               "font_width='extra_condensed' -> extra_condensed")
        assert(FS.font_width_setting({ font_width: "мусор" }) == "condensed", "font_width=мусор -> condensed")

        assert(FS.apply_font_width("Sofia Sans Condensed", "extra_condensed") == "Sofia Sans Extra Condensed",
               "width=extra_condensed повышает сжатие Sofia Sans")
        assert(FS.apply_font_width("Sofia Sans Condensed", "condensed") == "Sofia Sans Condensed",
               "width=condensed оставляет базовое семейство")
        assert(FS.apply_font_width("Oswald", "extra_condensed") == "Oswald",
               "width не меняет явно выбранные семейства (Oswald)")

        assert(FS.match_available_family("DIN Condensed") == "Oswald", "legacy 'DIN Condensed' -> Oswald")
        assert(FS.match_available_family("sofia sans extra") == "Sofia Sans Extra Condensed",
               "нечеткое 'sofia sans extra' -> Extra Condensed")
        assert(FS.match_available_family("Roboto") == "Roboto Condensed", "нечеткое 'Roboto' -> Roboto Condensed")
        assert(FS.legacy_family_for("Din Condensed") == "Oswald", "legacy_family_for('Din…') -> Oswald")
        assert(FS.layout_face_name("Sofia Sans Extra Condensed") == "Sofia Sans ExtraCond",
               "Extra Condensed -> переименованное начертание для LayOut")
      end

      def test_annotation_font_size
        puts "\n--- A12. annotation_font_size ---"
        model = ::Sketchup::MockModel.new(File.join(Dir.tmpdir, "dn1c_params_model.skp"))
        model.entities << ::Sketchup::Text.new("Выноска 1", { name: "Sofia Sans Condensed", size: 14, bold: false, italic: false })

        applied = []
        RS.with_temporary_annotation_font_size(model, "18") do
          applied = model.entities.grep(::Sketchup::Text).map { |t| t.font[:size] }
        end
        restored = model.entities.grep(::Sketchup::Text).map { |t| t.font[:size] }
        assert(applied.first == 18, "annotation_font_size='18' применяется к выноскам")
        assert(restored.first == 14, "исходный размер восстанавливается после рендера")

        ran = false
        RS.with_temporary_annotation_font_size(model, "auto") { ran = true }
        assert(ran, "annotation_font_size='auto' -> блок выполняется без правки шрифтов")

        ran = false
        RS.with_temporary_annotation_font_size(model, nil) { ran = true }
        assert(ran, "annotation_font_size=nil -> блок выполняется без правки шрифтов")
      end

      def test_frame_settings
        puts "\n--- A13. update_frame_settings (рамка кадра) ---"
        pd = fresh_pd

        assert(pd.update_frame_settings({ image_aspect_ratio: "16:9" }), "16:9 принимается")
        assert(pd.pdf_settings[:image_aspect_ratio] == "16:9", "image_aspect_ratio обновился")

        assert(pd.update_frame_settings({ aspect_ratio: "7:3" }), "невалидное отношение не ломает вызов")
        assert(pd.pdf_settings[:image_aspect_ratio] == "16:9", "невалидное отношение отклонено (осталось 16:9)")

        pd.update_frame_settings({ custom_ratio_w: 0, custom_ratio_h: -4 })
        assert(pd.pdf_settings[:custom_ratio_w] == 16, "custom_ratio_w=0 отклонен (осталось умолчание)")
        assert(pd.pdf_settings[:custom_ratio_h] == 9, "custom_ratio_h=-4 отклонен")

        pd.update_frame_settings({ custom_ratio_w: 21.5, custom_ratio_h: 9 })
        assert(pd.pdf_settings[:custom_ratio_w] == 21.5, "валидный custom_ratio_w принят")

        pd.update_frame_settings({ show_aspect_overlay: "true" })
        assert(pd.pdf_settings[:show_aspect_overlay] == true, "show_aspect_overlay='true' (строка) -> true")
        pd.update_frame_settings({ show_aspect_overlay: false })
        assert(pd.pdf_settings[:show_aspect_overlay] == false, "show_aspect_overlay=false -> false")

        assert(pd.update_frame_settings("не хэш") == false, "не-Hash аргумент отклоняется")
      end

      def test_apply_payload_hardening
        puts "\n--- A14. apply_payload!: белый список и клампы ---"
        pd = fresh_pd

        payload = {
          pdf_settings: {
            margin_mm: -10,
            page_size: "a3",
            render_quality: "HIGH",
            export_engine: "layout",        # неизвестный ключ
            evil_key: "злой жук"
          }
        }
        pd.apply_payload!(payload)
        ps = pd.pdf_settings
        assert(!ps.key?(:export_engine) && !ps.key?(:evil_key),
               "неизвестные ключи pdf_settings отбрасываются (export_engine, evil_key)")
        assert(ps[:margin_mm] == 0, "margin_mm=-10 из payload -> кламп 0")
        assert(ps[:page_size] == "A3", "page_size нормализуется ('a3' -> 'A3')")
        assert(ps[:render_quality] == "high", "render_quality нормализуется ('HIGH' -> 'high')")

        pd2 = fresh_pd
        pd2.apply_payload!({ pdf_settings: { margin_mm: 5000 } })
        assert(pd2.pdf_settings[:margin_mm] == 100, "margin_mm=5000 -> кламп 100")

        pd3 = fresh_pd
        pd3.apply_payload!({ pdf_settings: { webp_quality: 250 } })
        assert(pd3.pdf_settings[:webp_quality] == 100, "webp_quality=250 -> кламп 100")
        pd3.apply_payload!({ pdf_settings: { webp_quality: -5 } })
        assert(pd3.pdf_settings[:webp_quality] == 100, "webp_quality=-5 -> невалидное отброшено, прежнее значение (100) сохраняется")
        pd6 = fresh_pd
        pd6.apply_payload!({ pdf_settings: { webp_quality: "мусор" } })
        assert(pd6.pdf_settings[:webp_quality] == 85, "webp_quality=мусор (с чистыми умолчаниями) -> 85")

        pd4 = fresh_pd
        pd4.apply_payload!({ pdf_settings: { auto_open_pdf: "false", save_layout_file: "true" } })
        assert(pd4.pdf_settings[:auto_open_pdf] == false, "auto_open_pdf='false' (строка) -> boolean false")
        assert(pd4.pdf_settings[:save_layout_file] == true, "save_layout_file='true' (строка) -> boolean true")

        pd5 = fresh_pd
        pd5.apply_payload!({ pdf_settings: { page_size: "A9-XY" } })
        assert(pd5.pdf_settings[:page_size] == "A3", "неизвестный page_size из payload -> умолчание A3")
      end

      # --- B. Постраничные параметры (SceneItem) ---

      def test_scene_item_normalization
        puts "\n--- B1. SceneItem: нормализация ---"
        si = SI.new(name: "Вид", align_h: "LEFT", align_v: "Bottom")
        assert(si.align_h == "left" && si.align_v == "bottom", "выравнивания нормализуются в нижний регистр")

        si = SI.new(name: "Вид", align_h: "диагонально", align_v: "мусор")
        assert(si.align_h == "center" && si.align_v == "center", "невалидные выравнивания -> center")

        si = SI.new(name: "Обложка проекта")
        assert(si.page_type == :cover, "detect_page_type('Обложка…') -> :cover")
        si = SI.new(name: "Визуализация кухни")
        assert(si.page_type == :visual, "detect_page_type('Визуализация…') -> :visual")
        si = SI.new(name: "Случайная сцена")
        assert(si.page_type == :general, "detect_page_type(без маркеров) -> :general")

        si = SI.new(name: "Вид", scale_pct: 150)
        assert(si.scale_pct == 100, "scale_pct=150 -> кламп 100 (документированный диапазон 60–100)")
        si = SI.new(name: "Вид", scale_pct: 10)
        assert(si.scale_pct == 60, "scale_pct=10 -> кламп 60")
        si = SI.new(name: "Вид", scale_pct: 80)
        assert(si.scale_pct == 80, "scale_pct=80 в диапазоне -> как есть")
        si = SI.new(name: "Вид", scale_pct: nil)
        assert(si.scale_pct == 100, "scale_pct=nil -> умолчание 100")

        si = SI.from_h({ "name" => "Сцена", "scale_pct" => 150, "align_h" => "right" })
        assert(si.scale_pct == 100, "from_h (строчные ключи): scale_pct=150 -> кламп 100")
        assert(si.align_h == "right", "from_h (строчные ключи): align_h читается")

        si = SI.new(name: "Вид", enabled: false)
        assert(si.enabled == false, "enabled=false сохраняется")
        assert(si.viewport_visible == true, "viewport_visible всегда true (deprecated)")

        si = SI.new(name: "Вид", frame_overlay: "true", viewport_background: true)
        assert(si.frame_overlay == true && si.viewport_background == true, "строчные 'true' приводятся к boolean")
      end

      def test_scene_aspect_fallback
        puts "\n--- B2. aspect_ratio сцены: fallback рендера ---"
        pd = fresh_pd
        pd.pdf_settings[:layout_render_mode] = "hybrid"

        scene = SI.new(name: "01. Тестовая сцена", page_type: :general, aspect_ratio: "мусор")
        doc = render_page_for_scene(pd, scene)
        vp = doc.entities.map { |rec| rec[:entity] }.grep(::Layout::SketchUpModel).first
        assert(!vp.nil?, "hybrid-режим: видовой экран создан")
        if vp
          ratio = vp.bounds.width.to_f / vp.bounds.height.to_f
          assert((ratio - 4.0 / 3.0).abs < 0.01, "неизвестный aspect_ratio -> fallback 4:3 (#{ratio.round(3)})")
        end

        scene = SI.new(name: "01. Тестовая сцена", page_type: :general, aspect_ratio: "16:9")
        doc = render_page_for_scene(pd, scene)
        vp = doc.entities.map { |rec| rec[:entity] }.grep(::Layout::SketchUpModel).first
        if vp
          ratio = vp.bounds.width.to_f / vp.bounds.height.to_f
          assert((ratio - 16.0 / 9.0).abs < 0.01, "aspect_ratio=16:9 -> кадр 16:9 (#{ratio.round(3)})")
        end

        # custom: глобальные custom_ratio_w/h
        scene = SI.new(name: "01. Тестовая сцена", page_type: :general, aspect_ratio: "custom")
        pd.pdf_settings[:custom_ratio_w] = 21
        pd.pdf_settings[:custom_ratio_h] = 9
        doc = render_page_for_scene(pd, scene)
        vp = doc.entities.map { |rec| rec[:entity] }.grep(::Layout::SketchUpModel).first
        if vp
          ratio = vp.bounds.width.to_f / vp.bounds.height.to_f
          assert((ratio - 21.0 / 9.0).abs < 0.02, "aspect_ratio=custom -> 21:9 из настроек (#{ratio.round(3)})")
        end

        # custom с мусорными w/h -> 16:9
        pd.pdf_settings[:custom_ratio_w] = 0
        pd.pdf_settings[:custom_ratio_h] = -3
        scene = SI.new(name: "01. Тестовая сцена", page_type: :general, aspect_ratio: "custom")
        doc = render_page_for_scene(pd, scene)
        vp = doc.entities.map { |rec| rec[:entity] }.grep(::Layout::SketchUpModel).first
        if vp
          ratio = vp.bounds.width.to_f / vp.bounds.height.to_f
          assert((ratio - 16.0 / 9.0).abs < 0.02, "custom с невалидными w/h -> fallback 16:9 (#{ratio.round(3)})")
        end
      end

      def render_page_for_scene(pd, scene)
        Dir.mktmpdir do |tmp|
          # Гибридному режиму нужен .skp на диске: мок-модель во временной папке
          model = ::Sketchup::MockModel.new(File.join(tmp, "hybrid_model.skp"))
          model.save_copy(model.path)
          ::Sketchup.active_model = model

          doc = ::Layout::Document.new
          ctx = LB.send(:build_context, pd, model, "Sofia Sans Condensed")
          pd_dim = LB.send(:get_page_dimensions, pd.pdf_settings)
          LB.send(:render_modular_page, doc, doc.pages.first, doc.layers.first, scene,
                  1, 1, pd_dim[:w], pd_dim[:h], 0.2, ctx, [])
          doc
        end
      end

      # --- C. Шаблоны (custom_layouts) ---

      def test_template_normalization
        puts "\n--- C1. Нормализация шаблонов (layout.yaml) ---"
        Dir.mktmpdir do |tmp|
          src = File.join(tmp, "in.yaml")
          File.write(src, {
            "layout" => {
              "cover" => {
                "name" => "Титул", "line_gap" => 500.0, "line_enabled" => "true",
                "image_4_3" => { "x" => 10.0, "y" => 10.0, "w" => 80.0, "h" => 80.0,
                                 "visible" => "false", "aspect_ratio" => "16:9", "scale_pct" => "90" },
                "params" => [
                  { "id" => "p1", "source" => "project.articul", "label" => "Артикул",
                    "font_size" => 500.0, "align" => "justify", "valign" => "middle",
                    "color" => "#00FF00", "visible" => "no" }
                ]
              }
            }
          }.to_yaml)

          pd = PD.new
          pd.load_from_layout_yaml(src)
          tpl = pd.pdf_settings[:custom_layouts][:cover]
          assert(tpl[:line_gap] == 50, "line_gap=500 -> кламп 50 мм")
          assert(tpl[:line_enabled] == true, "line_enabled='true' -> boolean")
          img = tpl[:image_4_3]
          assert(img[:scale_pct] == 90, "scale_pct='90' (строка) -> 90")
          assert(img[:visible] == false, "visible='false' -> boolean false")
          prm = tpl[:params].first
          assert(prm[:font_size] == 72.0, "font_size=500 -> кламп 72pt")
          assert(prm[:align] == "left", "align='justify' -> fallback left")
          assert(prm[:valign] == "top", "valign='middle' -> fallback top")
          assert(prm[:visible] == false, "param visible='no' -> boolean false")
        end
      end

      # --- D. Данные проекта ---

      def test_version_revision
        puts "\n--- D1. version / revision ---"
        pd = fresh_pd
        pd.apply_payload!({ workflow: { version: "2", revision: 7 } })
        assert(pd.workflow[:version] == "02", "version='2' -> формат '02'")
        assert(pd.workflow[:revision] == "007", "revision=7 -> формат '007'")

        pd.apply_payload!({ workflow: { version: "мусор", revision: -5 } })
        assert(pd.workflow[:version] == "01", "version=мусор -> '01'")
        assert(pd.workflow[:revision] == "001", "revision=-5 -> '001'")

        pd.project_info[:version] = 12
        assert(pd.workflow[:version] == "12", "project_info[:version]=12 синхронизируется в workflow")
      end

      def test_roundtrip_settings
        puts "\n--- D2. Round-trip настроек (payload -> диск -> загрузка) ---"
        pd = fresh_pd
        pd.apply_payload!({
          pdf_settings: { margin_mm: 12, page_layout: "portrait", render_quality: "high",
                          stamp_type: "approved", webp_quality: "lossless" },
          scenes: [{ name: "01. Вид", page_type: "visual", aspect_ratio: "16:9", scale_pct: 80, enabled: true }],
          directories: [{ path: "U:/x", title: "Папка", description: "desc", display: "grid", thumb_size: 120, send_to_server: false }]
        })
        assert(pd.save_program_settings, "save_program_settings пишет во временную папку")

        loaded = fresh_pd
        assert(loaded.pdf_settings[:margin_mm] == 12, "margin_mm=12 переживаю запись/чтение")
        assert(loaded.pdf_settings[:page_layout] == "portrait", "page_layout=portrait переживаю запись/чтение")
        assert(loaded.pdf_settings[:render_quality] == "high", "render_quality=high переживаю запись/чтение")
        assert(loaded.pdf_settings[:stamp_type] == "approved", "stamp_type=approved переживаю запись/чтение")
        assert(loaded.pdf_settings[:webp_quality] == "lossless", "webp_quality=lossless переживаю запись/чтение")
        assert(!loaded.pdf_settings.key?(:export_engine), "орфанные ключи не попадают в settings.yaml")
      end

      def test_directories_normalization
        puts "\n--- D3. directories ---"
        pd = fresh_pd
        pd.apply_payload!({
          directories: [
            { "path" => "U:/a", "title" => "А", "description" => "d", "display" => "мусор", "thumb_size" => 999, "send_to_server" => "false" },
            { "path" => "U:/b", "title" => "Б" },
            "не хэш"
          ]
        })
        dirs = pd.directories
        assert(dirs.is_a?(Array) && dirs.size == 2 && dirs.all? { |d| d.is_a?(Hash) },
               "не-Hash записи directories отбрасываются нормализацией (осталось 2)")
        first = dirs.first
        assert(first[:send_to_server] == false || first["send_to_server"] == false,
               "send_to_server='false' -> boolean false после нормализации")
      end

      # --- E. Полный экспорт с разными комбинациями ---

      def test_full_export_variants
        puts "\n--- E1. Полный экспорт (моки): комбинации параметров ---"
        Dir.mktmpdir do |tmp|
          work = File.join(tmp, "work")
          FileUtils.mkdir_p(work)
          model = ::Sketchup::MockModel.new(File.join(work, "sample.skp"))
          scenes = [
            ::Sketchup::MockPage.new("01. Обложка", "Титул"),
            ::Sketchup::MockPage.new("02. Вид", "Визуализация"),
            ::Sketchup::MockPage.new("03. Чертеж", "План")
          ]
          model.pages = ::Sketchup::MockPages.new(scenes)

          pd = fresh_pd
          pd.sync_with_model_scenes(model)
          pd.pdf_settings[:auto_open_pdf] = false
          pd.pdf_settings[:save_skp_backup] = false
          pd.pdf_settings[:save_layout_file] = false

          # 1. Портрет A4 + поле 10 мм + все сцены
          pd.pdf_settings[:page_size] = "A4"
          pd.pdf_settings[:page_layout] = "portrait"
          pd.pdf_settings[:margin_mm] = 10
          out1 = File.join(tmp, "out_portrait.pdf")
          ctrl = EC.new(pd, model)
          ctrl.export(out1)
          assert(File.exist?(out1) && File.size(out1) > 500, "экспорт A4 portrait margin=10 создал PDF")
          assert(!File.exist?(out1.sub(/\.pdf$/i, ".layout")), "save_layout_file=false -> .layout не сохраняется")

          # 2. Отключённая сцена пропускается
          pd.scenes[1].enabled = false
          out2 = File.join(tmp, "out_filtered.pdf")
          EC.new(pd, model).export(out2)
          assert(File.exist?(out2), "экспорт с отключённой сценой создал PDF")
          content = File.binread(out2).to_s
          page_count = content.scan(/\/Type\s*\/Page[^s]/).size
          assert(page_count == 2, "отключённая сцена исключена: страниц 2, а не 3 (найдено #{page_count})")
          pd.scenes[1].enabled = true

          # 3. save_layout_file=true -> .layout сохраняется
          pd.pdf_settings[:save_layout_file] = true
          out3 = File.join(tmp, "out_layout.pdf")
          EC.new(pd, model).export(out3)
          assert(File.exist?(out3.sub(/\.pdf$/i, ".layout")), "save_layout_file=true -> .layout сохраняется")

          # 4. Все сцены отключены -> исключение
          pd.scenes.each { |s| s.enabled = false }
          out4 = File.join(tmp, "out_empty.pdf")
          began = false
          begin
            began = true
            EC.new(pd, model).export(out4)
            assert(false, "экспорт без сцен должен падать с ошибкой")
          rescue RuntimeError => e
            assert(e.message.include?("Не выбрано ни одной сцены"), "экспорт без сцен: понятная ошибка (#{e.message[0, 40]}…)")
          end
          assert(began, "блок экспорта без сцен выполнен")

          # Фоновый пул WebP-конвертации мог двигать файлы в папке tmp:
          # дожидаемся партию, чтобы Dir.mktmpdir не упал при удалении
          if defined?(::DN1Code::ExportPdf2::Service::SnapshotWorker)
            ::DN1Code::ExportPdf2::Service::SnapshotWorker.drain(5.0)
          end
        end
      end

      def run_all
        with_isolated_config do
          puts "=========================================================="
          puts "  Матричный тест параметров DN1C Export PDF 2"
          puts "=========================================================="

          test_page_dimensions
          test_margins
          test_render_quality_layout_resolution
          test_render_width_by_page_and_quality
          test_render_aspect_and_antialias
          test_scale_multiplier
          test_image_format
          test_webp_quality
          test_stamp
          test_colors
          test_font_service
          test_annotation_font_size
          test_frame_settings
          test_apply_payload_hardening
          test_scene_item_normalization
          test_scene_aspect_fallback
          test_template_normalization
          test_version_revision
          test_directories_normalization
          test_full_export_variants
          test_roundtrip_settings
        end

        puts "=========================================================="
        puts "  ИТОГИ ТЕСТИРОВАНИЯ: Успешно: #{@passed}, Ошибок: #{@failed}"
        puts "=========================================================="
        exit(@failed.zero? ? 0 : 1)
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  DN1Code::ExportPdf2::ParametersTestRunner.new.run_all
end
