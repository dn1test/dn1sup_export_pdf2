# frozen_string_literal: true

# -------------------------------------------------------------------------------
# Проверка параметров секций «Заголовок страницы (Шапка) / Средний блок /
# Подвал страницы (Footer)» вкладки «Настройка шаблона».
#
# В отличие от старых тестов (структура конфига + факт генерации PDF), здесь
# каждый параметр проверяется по ФАКТИЧЕСКОМУ результату в документе LayOut
# (мок): тексты, позиции (bounds), стили (размер/цвет/выравнивание/якорь),
# чекбоксы стадий.
#
# Запуск отдельно:
#   ruby -I dn1c_export_pdf2 dn1c_export_pdf2/test/test_template_params.rb
# В составе общего прогона подключается из comprehensive_test.rb
# (TestRunner подмешивает TemplateParamsTests).
# -------------------------------------------------------------------------------

require_relative "mock_sketchup"
require_relative "../main"
require "json"

module DN1Code
  module ExportPdf2
    module TestSupport
      module TemplateParamsTests
        LB = ::DN1Code::ExportPdf2::Service::LayoutBuilder

        # Геометрия мок-листа A4 landscape (in → pt)
        PAGE_W_PT  = 11.6929 * 72.0
        PAGE_H_PT  = 8.2677 * 72.0
        MARGIN_PT  = 0.2     * 72.0
        CONTENT_W  = PAGE_W_PT - (MARGIN_PT * 2)
        CONTENT_H  = PAGE_H_PT - (MARGIN_PT * 2)

        # ------------------------------------------------------------------
        # Хелперы
        # ------------------------------------------------------------------

        def tp_make_project
          pd = ::DN1Code::ExportPdf2::Model::ProjectData.new
          # Тест не должен зависеть от локального config/layout.yaml пользователя
          # (ProjectData.new подгружает его и мержит поверх дефолтов) — сбрасываем
          pd.pdf_settings[:custom_layouts] = pd.send(:default_custom_layouts)
          pd.project_info.merge!(
            furniture_name: "Шкаф-купе АЛЬФА",
            room_name:      "Прихожая",
            address:        "г. Москва, ул. Ленина, 10",
            name_customer:  "Иванов И.И.",
            company:        "ООО «МебельПроект»",
            articul:        "CF#260922_100000"
          )
          pd.workflow[:version]         = "02"
          pd.workflow[:revision]        = "003"
          pd.workflow[:last_edit_date]  = "22.09.2026"
          # Канонический порядок истории: новые записи сверху (как в Ruby-памяти)
          pd.workflow[:history_edit]    = [
            ["2026-09-10 12:00", "Правка фасадов"],
            ["2026-08-01 10:00", "Первичная выдача"]
          ]
          pd
        end

        def tp_layout(pd, tpl, slot)
          pd.pdf_settings[:custom_layouts][tpl][slot]
        end

        # Рендер одной страницы в мок-документ; возвращает Document
        def tp_render(pd, scene_type: :cover, page_index: 1, total_pages: 4)
          doc   = ::Layout::Document.new
          ctx   = LB.send(:build_context, pd, nil, "Sofia Sans Condensed")
          scene = ::DN1Code::ExportPdf2::Model::SceneItem.new(name: "01. Тестовая сцена", page_type: scene_type)
          scene.viewport_visible = false # без видового экрана — только текстовые блоки
          LB.send(:render_modular_page, doc, doc.pages.first, doc.layers.first, scene,
                  page_index, total_pages,
                  doc.page_info.width, doc.page_info.height, doc.page_info.left_margin,
                  ctx, [])
          doc
        end

        def tp_texts(doc)
          doc.entities.map { |rec| rec[:entity] }.grep(::Layout::FormattedText)
        end

        # Строки заголовка — единственные, кто идёт через RTF
        def tp_rtf_texts(doc)
          tp_texts(doc).select { |t| t.rtf_data.to_s.start_with?("{\\rtf1") }
        end

        def tp_find_text(doc, fragment)
          tp_texts(doc).find { |t| t.plain_text.to_s.include?(fragment) }
        end

        def tp_rects(doc)
          doc.entities.map { |rec| rec[:entity] }.grep(::Layout::Rectangle)
        end

        def tp_paths(doc)
          doc.entities.map { |rec| rec[:entity] }.grep(::Layout::Path)
        end

        # Отключить всё, кроме исследуемого блока (чистая выдача сущностей)
        def tp_isolate(pd, tpl, keep: :slot_1)
          %i[header slot_1 slot_2 slot_3 slot_4 footer].each do |b|
            tp_layout(pd, tpl, b)[:visible] = (b == keep)
          end
        end

        # ------------------------------------------------------------------
        # 79. Шапка: Вкл, valign ↑⇕↓, состав строк, «стр.», «пт.», цвет
        # ------------------------------------------------------------------
        def test_79_template_params_header
          puts "\n--- 79. Параметры шапки: Вкл / valign / строки / стр. / пт. / цвет ---"

          # 1. Чекбокс «Вкл» (header.visible)
          pd = tp_make_project
          tp_layout(pd, :cover, :header)[:lines] = ["furniture_name"]
          doc = tp_render(pd)
          assert(!tp_rtf_texts(doc).empty?, "Шапка по умолчанию (Вкл) рисует RTF-строки")
          assert(tp_find_text(doc, "Шкаф-купе АЛЬФА"), "Название мебели попадает в шапку")

          tp_layout(pd, :cover, :header)[:visible] = false
          doc_off = tp_render(pd)
          assert(tp_rtf_texts(doc_off).empty?, "Чекбокс «Вкл» off (header.visible=false) убирает шапку целиком")

          # 2. Вертикальное выравнивание ↑/⇕/↓ (header.valign) — позиции по bounds
          tops = {}
          %w[top center bottom].each do |va|
            pd_va = tp_make_project
            hdr_va = tp_layout(pd_va, :cover, :header)
            hdr_va[:lines] = ["furniture_name"]
            hdr_va[:valign] = va
            ent = tp_rtf_texts(tp_render(pd_va)).first
            tops[va] = ent.bounds.y * 72.0 # LayOut: y вниз от верхнего края
          end
          assert(tops["top"] < tops["center"] && tops["center"] < tops["bottom"],
                 "valign ↑/⇕/↓ смещает шапку вниз по странице " \
                 "(top=#{tops['top'].round(1)} < center=#{tops['center'].round(1)} < bottom=#{tops['bottom'].round(1)} pt)")
          assert(tops["bottom"] - tops["top"] > 60.0,
                 "Разнос позиций valign достаточный (#{(tops['bottom'] - tops['top']).round(1)} pt)")

          # 3. Чекбоксы строк (header.lines): включена одна — рисуется одна
          pd_one = tp_make_project
          hdr_one = tp_layout(pd_one, :cover, :header)
          hdr_one[:lines] = ["furniture_name"]
          hdr_one[:line_rows] = { "furniture_name" => 1 }
          ents_one = tp_rtf_texts(tp_render(pd_one))
          assert(ents_one.size == 1, "Включена одна строка — рисуется ровно одна строка шапки")
          assert(ents_one.first.plain_text.include?("Шкаф-купе АЛЬФА"), "В строке — название мебели")

          pd_two = tp_make_project
          hdr_two = tp_layout(pd_two, :cover, :header)
          hdr_two[:lines] = %w[furniture_name place_address]
          hdr_two[:line_rows] = { "furniture_name" => 1, "place_address" => 2 }
          ents_two = tp_rtf_texts(tp_render(pd_two))
          assert(ents_two.size == 2, "Строки на стр.1 и стр.2 — два отдельных блока")
          assert(ents_two.map(&:plain_text).join(" ").include?("Прихожая"),
                 "Вторая строка содержит «Место установки» (room|address)")
          tp_isolate(pd_two, :cover, keep: :header)
          assert(tp_rtf_texts(tp_render(pd_two)).size == 2 &&
                 tp_rects(tp_render(pd_two)).size == 1,
                 "Между стр.1 и стр.2 рисуется один разделитель")

          # 4. Группировка «стр.»: все на стр.1 — одна строка через « | »
          pd_grp = tp_make_project
          hdr_grp = tp_layout(pd_grp, :cover, :header)
          hdr_grp[:lines] = %w[furniture_name place_address customer_or_company]
          hdr_grp[:line_rows] = { "furniture_name" => 1, "place_address" => 1, "customer_or_company" => 1 }
          grp = tp_rtf_texts(tp_render(pd_grp))
          assert(grp.size == 1, "Все три пункта на стр.1 — объединены в одну строку")
          gtxt = grp.first.plain_text
          assert(gtxt.include?("Шкаф-купе АЛЬФА") && gtxt.include?("Прихожая") && gtxt.include?("Иванов И.И."),
                 "В объединённую строку вошли все включённые пункты")
          assert(gtxt.include?(" | "), "Пункты внутри строки разделяются « | »")
          i_fn  = gtxt.index("Шкаф-купе АЛЬФА")
          i_pa  = gtxt.index("Прихожая")
          i_cu  = gtxt.index("Иванов И.И.")
          assert(i_fn < i_pa && i_pa < i_cu, "Порядок пунктов внутри строки следует порядку списка lines")

          # 5. Кегль «пт.» (line_font_sizes) — \fs = pt*2 в RTF
          pd_sz = tp_make_project
          hdr_sz = tp_layout(pd_sz, :cover, :header)
          hdr_sz[:lines] = %w[furniture_name place_address]
          hdr_sz[:line_rows] = { "furniture_name" => 1, "place_address" => 2 }
          hdr_sz[:line_font_sizes] = { "furniture_name" => 20, "place_address" => 14 }
          sz_ents = tp_rtf_texts(tp_render(pd_sz))
          rtf_fn = sz_ents.find { |t| t.plain_text.include?("Шкаф-купе") }.rtf_data
          rtf_pa = sz_ents.find { |t| t.plain_text.include?("Прихожая") }.rtf_data
          assert(rtf_fn.include?("\\fs40"), "«пт.» 20 для названия → \\fs40 в RTF")
          assert(rtf_pa.include?("\\fs28"), "«пт.» 14 для адреса → \\fs28 в RTF")

          # 6. Цвет строки (line_colors) → colortbl в RTF
          pd_col = tp_make_project
          hdr_col = tp_layout(pd_col, :cover, :header)
          hdr_col[:lines] = ["furniture_name"]
          hdr_col[:line_rows] = { "furniture_name" => 1 }
          hdr_col[:line_colors] = { "furniture_name" => "FF0000" }
          rtf_col = tp_rtf_texts(tp_render(pd_col)).first.rtf_data
          assert(rtf_col.include?("\\red255\\green0\\blue0;"), "Цвет строки FF0000 попадает в палитру RTF (colortbl)")
          assert(rtf_col.include?("\\cf1"), "Фрагмент строки ссылается на свой цвет (\\cf1)")
        end

        # ------------------------------------------------------------------
        # 80. Средний блок: Вкл, Все/Снять, Заголовок, ⇤⇥, ↑⇕↓, Aa, цвет,
        #     расстояние мм, стадии с чекбоксами
        # ------------------------------------------------------------------
        def test_80_template_params_middle
          puts "\n--- 80. Параметры среднего блока: Вкл / Все/Снять / Заголовок / ⇤⇥ / ↑⇕↓ / Aa / цвет / расстояние / стадии ---"

          # 1. Чекбокс «Вкл» (slot_1.visible)
          pd = tp_make_project
          tp_isolate(pd, :cover, keep: :slot_1)
          s1 = tp_layout(pd, :cover, :slot_1)
          s1[:lines] = %w[workflow_revision workflow_version]
          s1[:line_aligns]  = {}
          s1[:line_valigns] = { "workflow_revision" => "top", "workflow_version" => "top" }
          doc = tp_render(pd)
          assert(tp_find_text(doc, "Ревизия") && tp_find_text(doc, "Версия"),
                 "Средний блок по умолчанию (Вкл) выводит строки")

          s1[:visible] = false
          doc_off = tp_render(pd)
          assert(tp_texts(doc_off).empty?, "Чекбокс «Вкл» off (slot_1.visible=false) убирает средний блок")

          # 2. «Все» / «Снять» (lines: полный список / [])
          s1[:visible] = true
          s1[:lines] = []
          doc_empty = tp_render(pd)
          assert(tp_texts(doc_empty).empty?, "«Снять» (lines=[]) — строки среднего блока не рисуются")
          s1[:lines] = %w[workflow_revision]
          assert(tp_find_text(tp_render(pd), "Ревизия"), "«Все» (lines заполнен) — строка возвращается")

          # 3. Чекбокс «Заголовок» (show_titles): префикс названия строки
          s1[:lines] = ["workflow_revision"]
          s1[:show_titles] = true
          with_title = tp_find_text(tp_render(pd), "Ревизия")
          assert(with_title && with_title.plain_text.include?("003"),
                 "«Заголовок» on — строка содержит название «Ревизия» и значение")
          s1[:show_titles] = false
          doc_no_title = tp_render(pd)
          no_title = tp_texts(doc_no_title).find { |t| t.plain_text.strip == "003" }
          assert(no_title, "«Заголовок» off — выводится только значение (003)")
          assert(!tp_texts(doc_no_title).any? { |t| t.plain_text.include?("Ревизия") },
                 "«Заголовок» off — названия строки на странице нет")
          s1[:show_titles] = true

          # 4. Горизонтальный сдвиг ⇤/⇥ (line_aligns: left/right) — колонки
          pd_lr = tp_make_project
          tp_isolate(pd_lr, :cover, keep: :slot_1)
          s1lr = tp_layout(pd_lr, :cover, :slot_1)
          s1lr[:lines] = %w[workflow_revision workflow_version]
          s1lr[:line_aligns]  = { "workflow_revision" => "left", "workflow_version" => "right" }
          s1lr[:line_valigns] = { "workflow_revision" => "top", "workflow_version" => "top" }
          doc_lr = tp_render(pd_lr)
          x_rev = tp_find_text(doc_lr, "Ревизия").bounds.x * 72.0
          x_ver = tp_find_text(doc_lr, "Версия").bounds.x * 72.0
          assert(x_ver - x_rev > CONTENT_W * 0.4,
                 "⇤/⇥ раскидывают строки по колонкам (левая x=#{x_rev.round(1)}, правая x=#{x_ver.round(1)} pt)")

          # 5. Вертикальные зоны ↑/⇕/↓ (line_valigns: top/bottom)
          pd_tb = tp_make_project
          tp_isolate(pd_tb, :cover, keep: :slot_1)
          s1tb = tp_layout(pd_tb, :cover, :slot_1)
          s1tb[:lines] = %w[workflow_revision workflow_version]
          s1tb[:line_aligns]  = {}
          s1tb[:line_valigns] = { "workflow_revision" => "top", "workflow_version" => "bottom" }
          doc_tb = tp_render(pd_tb)
          y_rev = tp_find_text(doc_tb, "Ревизия").bounds.y * 72.0
          y_ver = tp_find_text(doc_tb, "Версия").bounds.y * 72.0
          assert(y_ver - y_rev > CONTENT_H * 0.2,
                 "↑/↓ разносят строки по вертикали (верх y=#{y_rev.round(1)}, низ y=#{y_ver.round(1)} pt)")

          # 6. Кегль строки «Aa» (line_font_sizes) и кегль блока (font_size)
          pd_fs = tp_make_project
          tp_isolate(pd_fs, :cover, keep: :slot_1)
          s1fs = tp_layout(pd_fs, :cover, :slot_1)
          s1fs[:lines] = %w[workflow_revision workflow_version]
          s1fs[:line_aligns]  = {}
          s1fs[:line_valigns] = {}
          s1fs[:font_size] = 10.0
          s1fs[:line_font_sizes] = { "workflow_revision" => 12.0 }
          doc_fs = tp_render(pd_fs)
          sz_rev = tp_find_text(doc_fs, "Ревизия").style.font_size
          sz_ver = tp_find_text(doc_fs, "Версия").style.font_size
          assert((sz_rev - 12.0).abs < 0.01, "«Aa» 12 для Ревизии → font_size=12 (получено #{sz_rev})")
          assert((sz_ver - 10.0).abs < 0.01, "Без своего кегля строка берёт кегль блока 10 (получено #{sz_ver})")

          # 7. Цвет строки (line_colors)
          s1fs[:line_colors] = { "workflow_revision" => "005EB0" }
          doc_col = tp_render(pd_fs)
          c = tp_find_text(doc_col, "Ревизия").style.text_color
          assert(c.is_a?(::Sketchup::Color) && c.red == 0 && c.green == 0x5E && c.blue == 0xB0,
                 "Цвет строки #005EB0 применяется к тексту (rgb=#{c.is_a?(::Sketchup::Color) ? "#{c.red},#{c.green},#{c.blue}" : c.inspect})")

          # 8. «Расстояние ... мм» (item_gap_mm) — зазор между соседними строками
          gap_of = lambda do |mm|
            pd_g = tp_make_project
            tp_isolate(pd_g, :cover, keep: :slot_1)
            s1g = tp_layout(pd_g, :cover, :slot_1)
            s1g[:lines] = %w[workflow_revision workflow_version articul]
            s1g[:line_aligns]  = {}
            s1g[:line_valigns] = {}
            s1g[:item_gap_mm]  = mm
            d = tp_render(pd_g)
            t1 = tp_find_text(d, "Ревизия")
            t2 = tp_find_text(d, "Версия")
            (t2.bounds.y - (t1.bounds.y + t1.bounds.height)) * 72.0
          end
          gap_2mm  = gap_of.call(2.0)
          gap_20mm = gap_of.call(20.0)
          expected = (20.0 - 2.0) * 72.0 / 25.4
          assert((gap_20mm - gap_2mm - expected).abs < 1.5,
                 "«Расстояние мм» линейно меняет зазор: Δ=#{(gap_20mm - gap_2mm).round(1)} pt, " \
                 "ожидание 18 мм = #{expected.round(1)} pt")

          # 9. «Стадия проекта» — чекбоксы [✓]/[ ] (draw_stadia_check_rows)
          pd_st = tp_make_project
          tp_isolate(pd_st, :cover, keep: :slot_1)
          pd_st.workflow[:stadia] = [
            { name: "Эскизный проект",      status: true  },
            { name: "Рабочая документация", status: false },
            { name: "Детализация",          status: false }
          ]
          s1st = tp_layout(pd_st, :cover, :slot_1)
          s1st[:lines] = ["workflow_stadia"]
          s1st[:line_aligns]  = {}
          s1st[:line_valigns] = {}
          s1st[:show_titles]  = true
          doc_st = tp_render(pd_st)
          assert(tp_find_text(doc_st, "Стадия проекта"), "«Заголовок» on — выводится заголовок «Стадия проекта»")
          assert(tp_find_text(doc_st, "Эскизный проект") && tp_find_text(doc_st, "Рабочая документация"),
                 "Названия стадий выводятся строками")
          assert(tp_rects(doc_st).size == 3, "На каждую стадию рисуется квадрат-чекбокс (3 шт)")
          assert(tp_paths(doc_st).size == 1, "Галочка-ломаная рисуется только для отмеченной стадии (1 шт)")

          s1st[:show_titles] = false
          doc_st_nt = tp_render(pd_st)
          assert(!tp_texts(doc_st_nt).any? { |t| t.plain_text.include?("Стадия проекта") },
                 "«Заголовок» off — заголовка стадий нет, строки остаются")
          assert(tp_rects(doc_st_nt).size == 3 && tp_paths(doc_st_nt).size == 1,
                 "Чекбоксы стадий не зависят от чекбокса «Заголовок»")
        end

        # ------------------------------------------------------------------
        # 81. Подвал: Вкл, размер шрифта, Слева/Центр/Справа, нумерация страниц
        # ------------------------------------------------------------------
        def test_81_template_params_footer
          puts "\n--- 81. Параметры подвала: Вкл / размер / Слева-Центр-Справа / якорь / нумерация ---"

          # 1. Чекбокс «Вкл» (footer.visible)
          pd = tp_make_project
          tp_isolate(pd, :cover, keep: :footer)
          doc = tp_render(pd, page_index: 1, total_pages: 4)
          assert(tp_find_text(doc, "Страница 1 | 4"), "Подвал по умолчанию (Вкл) выводит нумерацию страниц")

          tp_layout(pd, :cover, :footer)[:visible] = false
          assert(tp_texts(tp_render(pd)).empty?, "Чекбокс «Вкл» off (footer.visible=false) убирает подвал")

          tp_layout(pd, :cover, :footer)[:visible] = true

          # 2. Бакеты по умолчанию: Слева/Центр/Справа (line_aligns)
          doc2 = tp_render(pd, page_index: 2, total_pages: 3)
          ents = tp_texts(doc2)
          assert(ents.size == 3, "Три группы (слева/центр/справа) — три текстовых блока (получено #{ents.size})")
          left, center, right = ents.sort_by { |t| t.bounds.x }
          ltxt, ctxt, rtxt = left.plain_text, center.plain_text, right.plain_text

          assert(ltxt.include?("Последние изменения: 2026-09-10 12:00 Правка фасадов"),
                 "Слева — «Последние изменения» из НОВЕЙШЕЙ записи истории")
          assert(!ltxt.include?("Первичная выдача"), "Старые записи истории в подвал не попадают")
          assert(ctxt.include?("Версия 02 # Ревизия 003"), "Центр — «Версия 02 # Ревизия 003»")
          assert(ctxt.include?("Артикул: CF#260922_100000"), "Центр — артикул")
          assert(ctxt.include?("Дата: 22.09.2026"), "Центр — дата из last_edit_date (dd.mm.yyyy)")
          assert(rtxt.include?("Страница 2 | 3"), "Справа — нумерация «Страница 2 | 3» текущей страницы")

          assert(left.style.text_alignment   == ::Layout::Style::ALIGN_LEFT,
                 "Левая группа имеет выравнивание ALIGN_LEFT")
          assert(center.style.text_alignment == ::Layout::Style::ALIGN_CENTER,
                 "Центральная группа имеет выравнивание ALIGN_CENTER")
          assert(right.style.text_alignment  == ::Layout::Style::ALIGN_RIGHT,
                 "Правая группа имеет выравнивание ALIGN_RIGHT")
          assert(ents.all? { |t| t.style.text_anchor == ::Layout::Style::ANCHOR_BOTTOM },
                 "Все строки подвала привязаны к нижнему краю (ANCHOR_BOTTOM)")

          # 3. Переключатели «Слева/Центр/Справа» у строк (footer.line_aligns)
          ftr = tp_layout(pd, :cover, :footer)
          ftr[:line_aligns] = { "footer_last_edit" => "right", "footer_page_total" => "left" }
          doc3 = tp_render(pd, page_index: 1, total_pages: 4)
          page_ent = tp_find_text(doc3, "Страница 1 | 4")
          edit_ent = tp_find_text(doc3, "Последние изменения")
          assert(page_ent.bounds.x < edit_ent.bounds.x,
                 "Перенос строки в другую группу меняет её колонку (Страница теперь левее Последних изменений)")
          assert(page_ent.style.text_alignment == ::Layout::Style::ALIGN_LEFT,
                 "Строка, переведённая в «Слева», печатается с ALIGN_LEFT")

          # 4. Размер шрифта подвала (footer.font_size)
          ftr[:line_aligns] = {}
          ftr[:font_size] = 9.5
          doc4 = tp_render(pd)
          assert(tp_texts(doc4).all? { |t| (t.style.font_size - 9.5).abs < 0.01 },
                 "«Размер шрифта» применяется ко всем строкам подвала (9.5 пт)")
        end

        # ------------------------------------------------------------------
        # 82. Контракт данных для диалога + guard-тесты исправлений app.js
        # ------------------------------------------------------------------
        def test_82_template_params_data_contract_and_js_guards
          puts "\n--- 82. Контракт данных (stadia → JSON) и guard-тесты app.js ---"

          # 1. Ruby отдаёт стадионы массивом объектов {name, status} —
          #    именно эту форму ждёт диалог (раньше из-за этого был [object Object])
          pd = tp_make_project
          pd.workflow[:stadia] = [
            { name: "Эскизный проект", status: true },
            { name: "РД",              status: false }
          ]
          payload = JSON.parse(JSON.generate(pd.to_h))
          stadia  = payload.dig("workflow", "stadia")
          assert(stadia.is_a?(Array) && !stadia.empty?, "workflow.stadia сериализуется массивом")
          assert(stadia.all? { |st| st.is_a?(Hash) && st.key?("name") && st.key?("status") },
                 "Каждая стадия — объект {name, status} (легаси-кортежи не отдаются)")
          assert(stadia.first["name"] == "Эскизный проект", "Имена стадий передаются как строки")

          # 2. Guard-тесты исправленного app.js
          js_path = File.join(__dir__, "../dialog/html/app.js")
          js = File.read(js_path, encoding: "utf-8")

          assert(js.include?("const stadiaName =") && js.include?("const stadiaMark ="),
                 "app.js умеет читать стадионы-объекты {name, status} (stadiaName/stadiaMark)")
          assert(js.include?('s.map(st => stadiaMark(st)).join(" • ")'),
                 "Превью стадий (WYSIWYG) форматируется через stadiaMark")
          assert(js.include?('wf.stadia.map(st => stadiaName(st)).join(", ")'),
                 "Список «Средний блок» форматирует стадионы через stadiaName (не String(st))")
          assert(!js.include?("toLocaleDateString"), "В превью нет локального формата даты (9/22/2026)")
          assert(js.include?("const previewDate ="), "app.js использует единый хелпер даты previewDate")
          assert(js.include?("Array.isArray(h[0]) ? `${h[0][0]} ${h[0][1]}` : h[0]"),
                 "«Последние изменения» в превью берут первую (новейшую) запись истории, как Ruby-экспорт")
        end
        # ------------------------------------------------------------------
        # 83. «Вкл» среднего блока — главный выключатель всех инфо-слотов:
        # при выключении параметры блока не выводятся в PDF вовсе
        # ------------------------------------------------------------------
        def test_83_middle_block_master_switch
          puts "\n--- 83. «Вкл» среднего блока гасит ВСЕ инфо-слоты шаблона (слоты 2–4 не самостоятельны) ---"

          # 1. Шаблон description: slot_1 ВКЛ — работает зонная система slot_1;
          #    собственные строки slot_3 (видим по умолчанию) игнорируются
          pd = tp_make_project
          pd.project_info[:materials]   = "Фасады МДФ, Blum"
          pd.project_info[:appliances]  = "Вытяжка"
          pd.project_info[:lighting]    = "LED 3000K"
          tp_isolate(pd, :description, keep: :slot_1)
          s3 = tp_layout(pd, :description, :slot_3)
          s3[:visible] = true
          s3[:lines]   = ["articul"] # уникальная строка, которой нет в списке slot_1
          doc_on = tp_render(pd, scene_type: :description)
          assert(tp_find_text(doc_on, "Материалы и фурнитура"),
                 "slot_1 ВКЛ: строки среднего блока выводятся")
          assert(!tp_texts(doc_on).any? { |t| t.plain_text.include?("Артикул") },
                 "slot_1 ВКЛ: собственные строки slot_3 не отрисовываются (управляет зонная система slot_1)")

          # 2. «Вкл» ВЫКЛ — параметры среднего блока исчезают со страницы ЦЕЛИКОМ,
          #    даже если slot_3/slot_4 видимы и заполнены (легаси-конфиги)
          tp_layout(pd, :description, :slot_1)[:visible] = false
          doc_off = tp_render(pd, scene_type: :description)
          assert(tp_texts(doc_off).empty?,
                 "«Вкл» ВЫКЛ: ни один параметр среднего блока не попадает на страницу " \
                 "(включая видимый slot_3 с собственными строками)")

          # 3. Guard: чекбокс «Вкл» синхронизирует слоты 2–4 в конфиге
          js = File.read(File.join(__dir__, "../dialog/html/app.js"), encoding: "utf-8")
          assert(js.include?('["slot_2", "slot_3", "slot_4"].forEach'),
                 "app.js: переключение «Вкл» среднего блока синхронизирует видимость слотов 2–4")
        end
      end
    end
  end
end

# -------------------------------------------------------------------------------
# Автономный запуск: ruby -I dn1c_export_pdf2 dn1c_export_pdf2/test/test_template_params.rb
# -------------------------------------------------------------------------------
if __FILE__ == $PROGRAM_NAME
  if defined?(Sketchup) && Sketchup.respond_to?(:version)
    puts "Тесты параметров шаблона предназначены для запуска через терминал вне SketchUp GUI."
  else
    class StandaloneParamsRunner
      include DN1Code::ExportPdf2::TestSupport::TemplateParamsTests

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
        puts "=========================================================="
        puts "  Проверка параметров: Шапка / Средний блок / Подвал"
        puts "=========================================================="

        test_79_template_params_header
        test_80_template_params_middle
        test_81_template_params_footer
        test_82_template_params_data_contract_and_js_guards
        test_83_middle_block_master_switch

        puts "=========================================================="
        puts "  ИТОГИ ТЕСТИРОВАНИЯ: Успешно: #{@passed}, Ошибок: #{@failed}"
        puts "=========================================================="
        exit(@failed.zero? ? 0 : 1)
      end
    end

    StandaloneParamsRunner.new.run_all
  end
end
