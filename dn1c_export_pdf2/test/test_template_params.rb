# frozen_string_literal: true

# -------------------------------------------------------------------------------
# Проверка пользовательских параметров шаблона (вкладка «Шаблоны» →
# «Параметры страницы» → «+ Создать параметр»).
#
# Готовых списков параметров больше нет: параметр создается из источника данных
# («Данные проекта», «Папки спецификации», сцена, страница). Размещение — одна из
# шести зон страницы: колонка слева/по центру/справа (align) × верх/низ (valign);
# в строке параметра задаются кегль, цвет, заголовок и флаг «Вкл».
#
# Каждый тест проверяет ФАКТИЧЕСКИЙ результат в документе LayOut (мок): тексты,
# позиции (bounds), стили (размер/цвет/выравнивание), чекбоксы стадий, а также
# нормализацию конфига при загрузке/сохранении layout.yaml.
#
# Запуск отдельно:
#   ruby -I dn1c_export_pdf2 dn1c_export_pdf2/test/test_template_params.rb
# В составе общего прогона подключается из comprehensive_test.rb
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
            articul:        "CF#260922_100000",
            price:          "150 000",
            total_duration: "45",
            start_date:     "01.09.2026",
            end_date:       "15.10.2026"
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

        # Список параметров шаблона (создается пользователем через модал)
        def tp_params(pd, tpl)
          tpl_cfg = pd.pdf_settings[:custom_layouts][tpl] ||= {}
          tpl_cfg[:params] ||= []
        end

        # Добавить параметр в шаблон (как это делает модал «Создать параметр»)
        def tp_add_param(pd, tpl, source, attrs = {})
          tp_params(pd, tpl) << {
            id:         "p_test_#{tp_params(pd, tpl).size}",
            source:     source,
            label:      "",
            show_label: true,
            align:      "left",
            valign:     "top",
            font_family: "",
            font_size:  10.0,
            color:      "#0F172A",
            visible:    true
          }.merge(attrs)
        end

        # Рендер одной страницы в мок-документ; возвращает Document
        def tp_render(pd, scene_type: :cover, page_index: 1, total_pages: 4)
          doc   = ::Layout::Document.new
          ctx   = LB.send(:build_context, pd, nil, "Sofia Sans Condensed")
          scene = ::DN1Code::ExportPdf2::Model::SceneItem.new(name: "01. Тестовая сцена", page_type: scene_type)
          LB.send(:render_modular_page, doc, doc.pages.first, doc.layers.first, scene,
                  page_index, total_pages,
                  doc.page_info.width, doc.page_info.height, doc.page_info.left_margin,
                  ctx, [])
          doc
        end

        # Сущности документа: мок возвращает записи {entity: ...}, реальный LayOut API
        # (SU 2026) — сущности постранично через Layout::Page#entities
        def tp_entities(doc)
          if doc.respond_to?(:entities) && doc.method(:entities).arity.zero?
            doc.entities.map { |rec| rec[:entity] }
          else
            doc.pages.flat_map { |page| page.entities.to_a }
          end
        end

        def tp_texts(doc)
          tp_entities(doc).grep(::Layout::FormattedText)
        end

        def tp_find_text(doc, fragment)
          tp_texts(doc).find { |t| t.plain_text.to_s.include?(fragment) }
        end

        def tp_rects(doc)
          tp_entities(doc).grep(::Layout::Rectangle)
        end

        def tp_paths(doc)
          tp_entities(doc).grep(::Layout::Path)
        end

        # ------------------------------------------------------------------
        # 79. Параметр страницы: Вкл, заголовок, X/Y, выравнивание, кегль, цвет
        # ------------------------------------------------------------------
        def test_79_template_params_placement
          puts "\n--- 79. Параметр страницы: Вкл / заголовок / X/Y / выравнивание / кегль / цвет ---"

          # 1. Параметр по умолчанию: «Заголовок: значение»
          pd = tp_make_project
          tp_add_param(pd, :cover, "project.furniture_name", label: "Изделие")
          doc = tp_render(pd)
          ent = tp_find_text(doc, "Шкаф-купе АЛЬФА")
          assert(ent, "Параметр с заполненным источником выводится на страницу")
          assert(ent.plain_text.include?("Изделие:"), "Заголовок параметра выводится перед значением")

          # 2. Чекбокс «Вкл» (param.visible)
          tp_params(pd, :cover).first[:visible] = false
          doc_off = tp_render(pd)
          assert(tp_texts(doc_off).empty?, "«Вкл» off (visible=false) убирает параметр со страницы")

          # 3. «Показывать» off — выводится только значение, без заголовка
          tp_params(pd, :cover).first[:visible] = true
          tp_params(pd, :cover).first[:show_label] = false
          doc_no_label = tp_render(pd)
          no_label = tp_texts(doc_no_label).find { |t| t.plain_text.strip == "Шкаф-купе АЛЬФА" }
          assert(no_label, "«Показывать» off — на листе только значение")
          assert(!tp_texts(doc_no_label).any? { |t| t.plain_text.include?("Изделие:") },
                 "«Показывать» off — заголовка «Изделие:» на листе нет")

          # 4. Пустое значение источника — параметр не выводится (без заглушек)
          pd_empty = tp_make_project
          tp_add_param(pd_empty, :cover, "customer.phone", label: "Телефон")
          assert(tp_texts(tp_render(pd_empty)).empty?,
                 "Незаполненный источник (телефон) → параметр не печатается, заглушки нет")

          # 5. Размещение по зонам: выравнивания задают колонку и привязку группы
          pd_z = tp_make_project
          tp_add_param(pd_z, :cover, "project.articul", label: "Артикул", align: "left", valign: "top")
          tp_add_param(pd_z, :cover, "project.room_name", label: "Помещение", align: "center", valign: "top")
          tp_add_param(pd_z, :cover, "workflow.version", label: "Версия", align: "right", valign: "bottom")
          doc_z = tp_render(pd_z)
          ent_left   = tp_find_text(doc_z, "CF#260922_100000")
          ent_center = tp_find_text(doc_z, "Прихожая")
          ent_right  = tp_find_text(doc_z, "v02")

          assert((ent_left.bounds.x * 72.0 - MARGIN_PT).abs < 6.0,
                 "Зона «слева вверху»: колонка от левого края рабочей области (#{(ent_left.bounds.x * 72.0).round(1)} ≈ #{MARGIN_PT.round(1)} pt)")
          assert((ent_left.bounds.y * 72.0 - MARGIN_PT).abs < 6.0,
                 "Зона «слева вверху»: группа начинается от верхнего края рабочей области")

          c_mid = (ent_center.bounds.x + ent_center.bounds.width / 2.0) * 72.0
          page_mid = MARGIN_PT + CONTENT_W / 2.0
          assert((c_mid - page_mid).abs < CONTENT_W * 0.1,
                 "Зона «по центру вверху»: текст центрирован на листе (#{c_mid.round(1)} ≈ #{page_mid.round(1)} pt)")

          r_edge = (ent_right.bounds.x + ent_right.bounds.width) * 72.0
          assert((r_edge - (MARGIN_PT + CONTENT_W)).abs < 6.0,
                 "Зона «справа внизу»: текст у правого края рабочей области (#{r_edge.round(1)} pt)")
          assert(((ent_right.bounds.y + ent_right.bounds.height) * 72.0 - (MARGIN_PT + CONTENT_H)).abs < 6.0,
                 "Зона «справа внизу»: группа прижата к нижнему краю рабочей области")

          # 6. Параметры одной зоны складываются в столбик в порядке списка
          pd_s = tp_make_project
          tp_add_param(pd_s, :cover, "project.articul", label: "Артикул", align: "left", valign: "top")
          tp_add_param(pd_s, :cover, "project.room_name", label: "Помещение", align: "left", valign: "top")
          doc_s = tp_render(pd_s)
          y_first = tp_find_text(doc_s, "CF#").bounds.y * 72.0
          y_second = tp_find_text(doc_s, "Прихожая").bounds.y * 72.0
          assert(y_second > y_first, "Параметры одной зоны идут друг под другом (#{y_first.round(1)} → #{y_second.round(1)} pt)")
          assert(y_second - y_first < 120.0,
                 "Отступ между параметрами зоны небольшой (#{(y_second - y_first).round(1)} pt)")

          # 7. Кегль параметра (font_size)
          pd_fs = tp_make_project
          tp_add_param(pd_fs, :cover, "project.room_name", label: "Помещение", font_size: 20.0)
          sz = tp_find_text(tp_render(pd_fs), "Прихожая").style.font_size
          assert((sz - 20.0).abs < 0.01, "Кегль параметра 20 → font_size=20 (получено #{sz})")

          # 8. Цвет параметра (color)
          pd_col = tp_make_project
          tp_add_param(pd_col, :cover, "project.room_name", label: "Помещение", color: "#005EB0")
          c = tp_find_text(tp_render(pd_col), "Прихожая").style.text_color
          assert(c.is_a?(::Sketchup::Color) && c.red == 0x00 && c.green == 0x5E && c.blue == 0xB0,
                 "Цвет #005EB0 применяется к тексту параметра (rgb=#{c.red},#{c.green},#{c.blue})")

          # 9. Выравнивание печатается в стиле текста (ALIGN_*)
          pd_al = tp_make_project
          tp_add_param(pd_al, :cover, "project.articul", label: "A", align: "center")
          tp_add_param(pd_al, :cover, "project.room_name", label: "B", align: "right")
          doc_al = tp_render(pd_al)
          assert(tp_find_text(doc_al, "CF#").style.text_alignment == ::Layout::Style::ALIGN_CENTER,
                 "Выравнивание «Центр» → ALIGN_CENTER в стиле")
          assert(tp_find_text(doc_al, "Прихожая").style.text_alignment == ::Layout::Style::ALIGN_RIGHT,
                 "Выравнивание «Справа» → ALIGN_RIGHT в стиле")

          # 10. Шрифт параметра (font_family); пусто — шрифт страницы
          pd_ff = tp_make_project
          tp_add_param(pd_ff, :cover, "project.room_name", label: "Помещение", font_family: "Oswald")
          tp_add_param(pd_ff, :cover, "project.articul", label: "A", font_family: "")
          doc_ff = tp_render(pd_ff)
          expected_ff = ::DN1Code::ExportPdf2::Service::FontService.layout_font_family("Oswald")
          assert(tp_find_text(doc_ff, "Прихожая").style.font_family == expected_ff,
                 "Шрифт параметра Oswald → font_family=#{expected_ff} (получено: #{tp_find_text(doc_ff, 'Прихожая').style.font_family.inspect})")
          assert(tp_find_text(doc_ff, "CF#").style.font_family == "Sofia Sans Condensed",
                 "Пустой шрифт → шрифт страницы (Sofia Sans Condensed)")
        end

        # ------------------------------------------------------------------
        # 80. Источники значений (зеркало InfoLineResolver#resolve_param)
        # ------------------------------------------------------------------
        def test_80_template_params_sources
          puts "\n--- 80. Источники параметров: проект / папки / сцена / страница / стадии ---"

          pd  = tp_make_project
          ctx = LB.send(:build_context, pd, nil, "Sofia Sans Condensed")
          rctx = LB.send(:resolver_context, ctx, nil, 2, 3)
          res = ::DN1Code::ExportPdf2::Service::InfoLineResolver

          # 1. Данные проекта
          assert(res.resolve_param(rctx, "project.articul") == "CF#260922_100000", "project.articul → артикул")
          assert(res.resolve_param(rctx, "project.room_name") == "Прихожая", "project.room_name → помещение")
          assert(res.resolve_param(rctx, "customer.name") == "Иванов И.И.", "customer.name → заказчик")
          assert(res.resolve_param(rctx, "workflow.price") == "150 000 руб.", "workflow.price → с «руб.»")
          assert(res.resolve_param(rctx, "workflow.duration") == "45 дн.", "workflow.duration → с «дн.»")
          assert(res.resolve_param(rctx, "workflow.version") == "v02", "workflow.version → v02")
          assert(res.resolve_param(rctx, "workflow.revision") == "#r003", "workflow.revision → #r003")
          assert(res.resolve_param(rctx, "workflow.author").nil?, "Пустой автор → nil")

          # 2. История: последние изменения = новейшая запись; полная история — построчно
          assert(res.resolve_param(rctx, "workflow.last_edit") == "2026-09-10 12:00 Правка фасадов",
                 "workflow.last_edit → первая (новейшая) запись истории")
          hist = res.resolve_param(rctx, "workflow.history")
          assert(hist.include?("Правка фасадов") && hist.include?("Первичная выдача"),
                 "workflow.history → все записи")
          assert(hist.include?("\n"), "История многострочная")

          # 3. Папки спецификации: название и описание по индексу
          pd.directories = [{ path: "C:/job", title: "Материалы", description: "ЛДСП 16 мм, Blum" }]
          dctx = LB.send(:resolver_context, ctx, nil, 1, 4)
          assert(res.resolve_param(dctx, "dir.0.title") == "Материалы", "dir.0.title → название папки")
          assert(res.resolve_param(dctx, "dir.0.description") == "ЛДСП 16 мм, Blum", "dir.0.description → спецификация папки")
          assert(res.resolve_param(dctx, "dir.5.description").nil?, "Несуществующая папка → nil")

          # 4. Сцена и страница (сцена берется из scene_item контекста текущей страницы)
          scene = ::DN1Code::ExportPdf2::Model::SceneItem.new(name: "01. Тестовая сцена", page_type: :cover)
          sctx = LB.send(:resolver_context, ctx, scene, 2, 3)
          assert(res.resolve_param(sctx, "scene.name") == "01. Тестовая сцена", "scene.name → имя сцены")
          assert(res.resolve_param(rctx, "page.number_total") == "Страница 2 | 3", "page.number_total → «Страница 2 | 3»")
          pd.directories = []
          pd.scenes = [
            ::DN1Code::ExportPdf2::Model::SceneItem.new(name: "01. Титул", page_type: :cover),
            ::DN1Code::ExportPdf2::Model::SceneItem.new(name: "02. Общий вид", page_type: :general)
          ]
          assert(res.resolve_param(dctx, "page.toc").include?("02. Общий вид"),
                 "page.toc → список включённых страниц")

          # 5. Стадии проекта: параметр рисуется чекбоксами
          pd_st = tp_make_project
          pd_st.workflow[:stadia] = [
            { name: "Эскизный проект",      status: true  },
            { name: "Рабочая документация", status: false },
            { name: "Детализация",          status: false }
          ]
          tp_add_param(pd_st, :cover, "workflow.stadia", label: "Стадии")
          doc_st = tp_render(pd_st)
          assert(tp_find_text(doc_st, "Эскизный проект") && tp_find_text(doc_st, "Рабочая документация"),
                 "Названия стадий выводятся строками")
          assert(tp_rects(doc_st).size == 3, "На каждую стадию рисуется квадрат-чекбокс (3 шт)")
          assert(tp_paths(doc_st).size == 1, "Галочка рисуется только для отмеченной стадии (1 шт)")

          # 5b. Стадии в центральной колонке: текст центрируется самим LayOut
          # на всю ширину зоны — точно по центру колонки при любой ширине строки
          pd_sc = tp_make_project
          pd_sc.workflow[:stadia] = [{ name: "Эскизный проект", status: true }, { name: "РД", status: false }]
          tp_add_param(pd_sc, :cover, "workflow.stadia", label: "Стадии", align: "center")
          doc_sc = tp_render(pd_sc)
          row = tp_find_text(doc_sc, "Эскизный проект")
          assert(row, "Стадия в центральной колонке выведена")
          assert(row.style.text_alignment == ::Layout::Style::ALIGN_CENTER,
                 "Стадия в центральной колонке: текст ALIGN_CENTER на всю ширину зоны")
          # Реальный Geom::Bounds2d хранит upper_left/lower_right, мок — x/width;
          # ширина страницы берётся из документа (дефолт реального LayOut — Letter,
          # у мока — A4): центр колонки всегда совпадает с центром страницы
          b = row.bounds
          cx = b.respond_to?(:upper_left) ? b.upper_left.x + b.width / 2.0 : b.x + b.width / 2.0
          box_c = cx * 72.0
          page_c = doc_sc.page_info.width * 36.0
          assert((box_c - page_c).abs < 1.0,
                 "Бокс строки стадии совпадает с центром колонки (#{box_c.round(1)} ≈ #{page_c.round(1)} pt)")

          # 6. Неизвестный источник → nil (параметр молча не выводится)
          assert(res.resolve_param(dctx, "legacy.unknown_key").nil?, "Неизвестный источник → nil")
          pd_unk = tp_make_project
          tp_add_param(pd_unk, :cover, "legacy.unknown_key", label: "X")
          assert(tp_texts(tp_render(pd_unk)).empty?, "Параметр с неизвестным источником не печатается")
        end

        # ------------------------------------------------------------------
        # 84. Блок объединения параметров: одна строка через « | », стиль блока
        # ------------------------------------------------------------------
        def test_84_template_params_group_block
          puts "\n--- 84. Блок параметров: объединение детей в строку через « | » ---"

          # 1. Блок рендерится одной строкой, стиль берется у блока
          pd = tp_make_project
          pd.project_info[:phone] = "+7 999 000-00-00"
          tp_params(pd, :cover) << {
            id: "g1", group: true, label: "", show_label: false,
            align: "left", valign: "top", font_family: "", font_size: 12.0,
            color: "#005EB0", visible: true,
            params: [
              { id: "c1", source: "project.room_name", label: "", show_label: false },
              { id: "c2", source: "project.articul", label: "", show_label: false },
              { id: "c3", source: "customer.phone", label: "", show_label: false }
            ]
          }
          doc = tp_render(pd)
          ent = tp_find_text(doc, "Прихожая")
          assert(ent, "Блок с заполненными детьми выводится на страницу")
          assert(ent.plain_text.include?(" | "), "Дети блока объединены разделителем « | »")
          assert(ent.plain_text.include?("Прихожая") && ent.plain_text.include?("CF#260922_100000") && ent.plain_text.include?("+7 999"),
                 "В строке блока все заполненные дети (#{ent.plain_text.inspect})")
          sz = ent.style.font_size
          assert((sz - 12.0).abs < 0.01, "Строка блока использует кегль блока (12, получено #{sz})")

          # 2. Пустые дети пропускаются: строка = только заполненные значения
          tp_params(pd, :cover).first[:params].last[:source] = "customer.email"
          ent2 = tp_find_text(tp_render(pd), "Прихожая")
          assert(ent2.plain_text == "Прихожая | CF#260922_100000",
                 "Пустой источник в блоке пропускается (получено: #{ent2.plain_text.inspect})")

          # 3. Заголовок блока выводится перед строкой значений
          g = tp_params(pd, :cover).first
          g[:label] = "Реквизиты"
          g[:show_label] = true
          ent3 = tp_find_text(tp_render(pd), "Реквизиты: Прихожая")
          assert(ent3, "Заголовок блока выводится перед объединенной строкой")

          # 4. Порядок детей внутри блока = порядок в строке
          c = g[:params]
          g[:params] = [c[1], c[0]]
          ent4 = tp_find_text(tp_render(pd), "CF#260922_100000 | Прихожая")
          assert(ent4, "Порядок детей в блоке задает порядок значений в строке")

          # 5. Полностью пустой блок не выводится
          g[:show_label] = false
          g[:params] = [{ id: "c9", source: "customer.email", label: "", show_label: false }]
          assert(tp_texts(tp_render(pd)).empty?, "Блок без заполненных детей не выводится")

          # 6. «Вкл» off убирает блок целиком
          g[:params] = [{ id: "c1", source: "project.room_name", label: "", show_label: false }]
          g[:visible] = false
          assert(tp_texts(tp_render(pd)).empty?, "«Вкл» off (visible=false) убирает блок со страницы")
        end

        # ------------------------------------------------------------------
        # 85. Авто-подписи заголовков: пустой label при включённом «Заголовок»
        # берётся из AUTO_PARAM_LABELS, у детей блока — аналогично
        # ------------------------------------------------------------------
        def test_85_template_params_auto_labels
          puts "\n--- 85. Авто-подписи заголовков (пустой label + «Заголовок») ---"

          # 1. Плоский параметр: «Заголовок» включен, label пуст — авто-подпись источника
          pd = tp_make_project
          tp_add_param(pd, :cover, "project.articul")
          ent = tp_find_text(tp_render(pd), "CF#260922_100000")
          assert(ent, "Параметр с авто-подписью выводится на страницу")
          assert(ent.plain_text.include?("Артикул: CF#260922_100000"),
                 "Пустой label заменяется авто-подписью «Артикул» (#{ent.plain_text.inspect})")

          # 2. «Заголовок» выключен — печатается только значение
          tp_params(pd, :cover).first[:show_label] = false
          ent2 = tp_find_text(tp_render(pd), "CF#260922_100000")
          assert(ent2 && ent2.plain_text == "CF#260922_100000",
                 "show_label=false печатает значение без заголовка (#{ent2&.plain_text.inspect})")

          # 3. Заданный label сильнее авто-подписи; хвостовые «:» срезаются
          tp_params(pd, :cover).first[:show_label] = true
          tp_params(pd, :cover).first[:label] = "Код проекта:"
          ent3 = tp_find_text(tp_render(pd), "CF#260922_100000")
          assert(ent3.plain_text.include?("Код проекта: CF#260922_100000") && !ent3.plain_text.include?("Артикул"),
                 "Явный label перекрывает авто-подпись (#{ent3.plain_text.inspect})")

          # 4. Дети блока: включённый «Заголовок» ребёнка печатается перед значением
          pd4 = tp_make_project
          pd4.project_info[:phone] = "+7 999 000-00-00"
          tp_params(pd4, :cover) << {
            id: "g85", group: true, label: "", show_label: false,
            align: "left", valign: "top", font_family: "", font_size: 10.0,
            color: "#0F172A", visible: true,
            params: [
              { id: "c85a", source: "project.room_name", label: "", show_label: true },
              { id: "c85b", source: "customer.phone",    label: "", show_label: false }
            ]
          }
          ent4 = tp_find_text(tp_render(pd4), "Прихожая")
          assert(ent4, "Блок с детьми и авто-подписями выводится")
          assert(ent4.plain_text.include?("Помещение: Прихожая"),
                 "Ребёнок с «Заголовок» печатается как «Помещение: значение» (#{ent4.plain_text.inspect})")
          assert(ent4.plain_text.include?("+7 999"),
                 "Ребёнок без «Заголовок» печатается просто значением")
          assert(ent4.plain_text.include?(" | "), "Дети блока по-прежнему объединены « | »")

          # 5. Папки спецификаций: авто-подпись из названия раздела
          pd5 = tp_make_project
          pd5.directories = [{ path: "C:/job", title: "Материалы", description: "ЛДСП 16 мм, Blum" }]
          tp_add_param(pd5, :cover, "dir.0.description")
          ent5 = tp_find_text(tp_render(pd5), "ЛДСП 16 мм, Blum")
          assert(ent5, "Параметр папки выводится на страницу")
          assert(ent5.plain_text.include?("Материалы — спецификация: ЛДСП 16 мм, Blum"),
                 "Авто-подпись папки = «<название> — спецификация» (#{ent5.plain_text.inspect})")
        end

        # ------------------------------------------------------------------
        # 81. Независимость шаблонов + дефолты + layout.yaml (чистый лист)
        # ------------------------------------------------------------------
        def test_81_template_params_per_template_and_yaml
          puts "\n--- 81. Параметры привязаны к шаблону; layout.yaml: чистый лист + нормализация ---"

          # 1. Параметры каждого шаблона независимы
          pd = tp_make_project
          tp_add_param(pd, :cover, "project.articul", label: "Артикул")
          doc_cover = tp_render(pd, scene_type: :cover)
          assert(tp_find_text(doc_cover, "CF#260922_100000"), "Параметр шаблона cover выводится на cover-странице")
          doc_general = tp_render(pd, scene_type: :general)
          assert(tp_texts(doc_general).empty?, "Параметры шаблона cover не попадают на страницы других шаблонов")

          # 2. Дефолтные шаблоны: только видовое окно + пустой список параметров
          pd.pdf_settings[:custom_layouts] = pd.send(:default_custom_layouts)
          %i[cover description explain general visual].each do |tpl|
            cfg = pd.pdf_settings[:custom_layouts][tpl]
            assert(cfg.is_a?(Hash) && cfg.key?(:image_4_3) && cfg[:params] == [],
                   "Дефолт шаблона #{tpl}: image_4_3 + пустой params, без старых блоков")
            assert(!cfg.key?(:header) && !cfg.key?(:slot_1) && !cfg.key?(:footer),
                   "Дефолт шаблона #{tpl}: блоков header/slot_1/footer больше нет")
          end

          # 3. load_from_layout_yaml: страница со СТАРОЙ структурой игнорируется целиком
          dir = File.expand_path("tp_yaml_dir", __dir__)
          require "fileutils"
          FileUtils.mkdir_p(dir)
          legacy_path = File.join(dir, "layout_legacy.yaml")
          File.write(legacy_path, <<~YAML, encoding: "utf-8")
            ---
            layout:
              cover:
                header:
                  x: 25.0
                  visible: true
                  lines:
                    - furniture_name
                slot_1:
                  x: 0.0
                  visible: true
                  lines:
                    - articul
          YAML
          pd2 = tp_make_project
          assert(pd2.send(:load_from_layout_yaml, legacy_path), "Старый layout.yaml читается без ошибок")
          cover2 = pd2.pdf_settings[:custom_layouts][:cover]
          assert(cover2.nil? || cover2[:params] == [],
                 "Чистый лист: старый layout.yaml не даёт параметров (запись без новой модели игнорируется)")
          assert(cover2.nil? || (!cover2.key?(:header) && !cover2.key?(:slot_1)), "Старые блоки в конфиг не попадают")

          # 4. load_from_layout_yaml: новая структура читается, params нормализуются
          new_path = File.join(dir, "layout_new.yaml")
          File.write(new_path, <<~YAML, encoding: "utf-8")
            ---
            layout:
              cover:
                line_gap: 99
                line_enabled: "true"
                image_4_3:
                  x: 25.0
                  visible: true
                  aspect_ratio: '16:9'
                  scale_pct: 120
                params:
                  - id: p1
                    source: project.room_name
                    label: Помещение
                    x: 150.0
                    y: -3.0
                    align: top
                    font_size: 99
                    color: "#005EB0"
                  - source: ""
                  - id: p2
                    source: dir.0.description
                    visible: "false"
                  - id: g9
                    group: true
                    label: Блок
                    x: 33.0
                    params:
                      - id: c1
                        source: project.room_name
                        x: 77.0
                      - source: ""
          YAML
          pd3 = tp_make_project
          assert(pd3.send(:load_from_layout_yaml, new_path), "Новый layout.yaml читается")
          cover3 = pd3.pdf_settings[:custom_layouts][:cover]
          params3 = cover3[:params]
          assert(params3.size == 3, "Параметр без источника отбрасывается, остальные нормализуются (3 шт)")
          p1 = params3.first
          assert(!p1.key?(:x) && !p1.key?(:y), "Координаты X/Y удалены из модели параметров (задаются выравниваниями)")
          assert(p1[:align] == "left", "Недопустимое выравнивание → left")
          assert(p1[:font_size] <= 72.0, "Кегль ограничен сверху (#{p1[:font_size]})")
          assert(p1[:color] == "#005EB0", "Цвет сохраняется")
          assert(cover3[:line_gap] == 50.0, "«Размер между строками» шаблона ограничен сверху (99 → 50 мм)")
          assert(cover3[:line_enabled] == true, "line_enabled: \"true\" → true (линия-разделитель включена)")
          assert(!p1.key?(:line_gap) && !p1.key?(:line_enabled),
                 "line_gap/line_enabled — не поля параметра, а общие настройки шаблона")
          assert(cover3[:image_4_3][:scale_pct] == 120 && cover3[:image_4_3][:aspect_ratio] == "16:9",
                 "Настройки видовоего окна сохраняются (ограничение масштаба — на рендере)")
          p2 = params3[1]
          assert(p2[:visible] == false, "visible: \"false\" → false")
          assert(p2[:font_size] == 10.0, "Отсутствующие поля получают дефолты")
          assert(p2[:valign] == "top" && p2[:font_family] == "", "valign и шрифт по умолчанию: top / «» (шрифт страницы)")
          assert(pd3.pdf_settings[:custom_layouts][:visual].nil?,
                 "Шаблоны, которых нет в YAML, не досоздаются: список шаблонов задаётся layout.yaml")

          # 6. Блок (group: true): нормализуется вместе с вложенными параметрами
          g = params3.find { |p| p[:group] == true }
          assert(g, "Блок (group: true) сохраняется при нормализации")
          assert(g[:params].size == 1, "Дитя блока без источника отбрасывается (1 шт)")
          child = g[:params].first
          assert(child[:source] == "project.room_name" && !child.key?(:x),
                 "Дитя блока нормализуется: источник сохранен, X/Y удалены")
          assert(child.key?(:id) && child.key?(:source) && child.key?(:label) && child.key?(:show_label) &&
                 !child.key?(:align) && !child.key?(:valign) && !child.key?(:font_size) && !child.key?(:color) &&
                 !child.key?(:visible),
                 "Дитя блока хранит только id/source/label/show_label — зона и стиль у самого блока")

          # 5. save_to_layout_yaml: параметры сохраняются и читаются обратно
          pd4 = tp_make_project
          tp_add_param(pd4, :cover, "customer.name", label: "Заказчик", align: "right")
          pd4.pdf_settings[:custom_layouts][:cover][:line_gap] = 4
          out_path = File.join(dir, "layout_out.yaml")
          assert(pd4.send(:save_to_layout_yaml, out_path), "layout.yaml сохраняется")
          pd5 = tp_make_project
          pd5.send(:load_from_layout_yaml, out_path)
          saved_cfg = pd5.pdf_settings[:custom_layouts][:cover]
          saved = saved_cfg[:params]
          assert(saved.size == 1 && saved.first[:source] == "customer.name" && saved.first[:align] == "right",
                 "Сохраненный параметр читается обратно без потерь")
          assert(saved_cfg[:line_gap] == 4.0, "«Размер между строками» шаблона переживает цикл сохранения/загрузки layout.yaml")

          FileUtils.rm_rf(dir)
        end

        # ------------------------------------------------------------------
        # 82. Контракт данных для диалога + guard-тесты новой модели app.js
        # ------------------------------------------------------------------
        def test_82_template_params_data_contract_and_js_guards
          puts "\n--- 82. Контракт данных (stadia → JSON) и guard-тесты app.js ---"

          # 1. Ruby отдаёт стадионы массивом объектов {name, status} —
          #    именно эту форму ждёт диалог
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

          # 2. Guard-тесты новой модели параметров в app.js
          js_path = File.join(__dir__, "../dialog/html/app.js")
          js = File.read(js_path, encoding: "utf-8")

          # 2a. Готовые списки полностью убраны
          assert(!js.include?("const PARAM_DEFS"), "app.js: готовый каталог PARAM_DEFS удален")
          assert(!js.include?("buildParamCatalog"), "app.js: buildParamCatalog удален")
          assert(!js.include?("mergePreservedLines"), "app.js: mergePreservedLines удален")
          assert(!js.include?("getInfoLineDef"), "app.js: getInfoLineDef удален")
          assert(!js.include?("DEFAULT_LINES_BY_CONTENT"), "app.js: DEFAULT_LINES_BY_CONTENT удален")
          assert(!js.include?("line_rows") && !js.include?("line_aligns") && !js.include?("line_valigns"),
                 "app.js: карты строк/зон старых блоков удалены")

          # 2b. Функция создания параметра на месте
          assert(js.include?("function buildParamSources"), "app.js: buildParamSources строит каталог источников из данных")
          assert(js.include?("function paramPreviewValue"), "app.js: paramPreviewValue дает живое превью значения")
          assert(js.include?("function normalizeTemplateParam"), "app.js: normalizeTemplateParam нормализует параметр")
          assert(js.include?("function openParamModal"), "app.js: openParamModal открывает модал создания/правки")
          assert(js.include?("btnCreateParam"), "app.js: кнопка «+ Создать параметр» на месте")
          assert(js.include?('dir.${idx}.description'), "app.js: источники папок строятся динамически (dir.N.description)")

          # 2c. Настройки параметра: источник/заголовок — в модале, остальное —
          #     в строке параметра; X/Y убраны, место задается выравниваниями
          html_text = File.read(File.join(__dir__, "../dialog/html/index.html"), encoding: "utf-8")
          %w[paramModalSource paramModalLabel].each do |id|
            assert(html_text.include?(id) && js.include?(id), "Поле модала #{id} присутствует в диалоге")
          end
          assert(!html_text.include?("paramModalX") && !html_text.include?("paramModalY"),
                 "Поля X/Y убраны из модала параметра")
          assert(!js.include?("DEFAULT_PARAM_SETTINGS.x") && !js.include?("num(p.x"),
                 "app.js: координаты X/Y убраны из модели параметра")
          assert(js.include?("function paramZoneLabel"), "app.js: сводка строки показывает зону размещения")
          assert(js.include?('tpl-param-zone'), "app.js: зона размещения — во второй строке (стиль и размещение)")
          assert(js.include?("tpl-param-preview-empty"), "app.js: пустые данные параметра помечены в строке «(нет данных)»")
          assert(js.include?("function setupParamDragAndDrop") && js.include?("tpl-param-drag"),
                 "app.js: параметры сортируются перетаскиванием за ручку ⠿ (drag-and-drop)")

          # 2e. Блок объединения параметров
          assert(js.include?("btnCreateParamGroup"), "app.js: кнопка «📦 Блок» создает блок объединения")
          assert(js.include?("function createParamGroup"), "app.js: createParamGroup создает пустой блок")
          assert(js.include?("tpl-param-group-list") && js.include?("tpl-param-child-out"),
                 "app.js: блок содержит перетаскиваемых детей с кнопкой вывода из блока")
          assert(js.include?("p.group === true"), "app.js: normalizeTemplateParam сохраняет блоки с детьми")
          lb_text = File.read(File.join(__dir__, "../service/layout_builder.rb"), encoding: "utf-8")
          assert(lb_text.include?('values.join(" | ")'), "layout_builder.rb: блок объединяет детей через « | »")
          pd_rb = File.read(File.join(__dir__, "../model/project_data.rb"), encoding: "utf-8")
          assert(pd_rb.include?("base.merge!(group: true, params: children)"),
                 "project_data.rb: normalize_template_params нормализует блоки вместе с детьми")
          %w[tpl-param-font tpl-param-size tpl-param-valign tpl-param-align tpl-param-color tpl-param-show-label].each do |cls|
            assert(js.include?(cls), "Контрол строки параметра #{cls} присутствует в app.js")
          end
          assert(js.include?("PARAM_FONT_FAMILIES"), "app.js: выбор шрифта параметра из комплекта плагина")
          assert(js.include?('["top", "bottom"].includes(valignRaw)'),
                 "app.js: вертикальная привязка параметра — верх/низ")
          assert(js.include?("PARAM_LINE_GAPS") && js.include?("tpl-header-linegap"),
                 "app.js: «размер между строками» (мм) — общий селект в шапке карточки")
          assert(js.include?("tpl-header-line") && js.include?("getTemplateLineSettings") && js.include?("setTemplateLineSettings"),
                 "app.js: «Линия» — общая галочка в шапке карточки, чтение/запись настроек шаблона")
          assert(!js.include?("tpl-param-linegap") && !js.include?("tpl-param-line"),
                 "app.js: у строки параметра нет отдельных контролов зазора/линии — настройка общая")
          assert(pd_rb.include?("def normalize_line_settings!") && pd_rb.include?("line_gap") && pd_rb.include?("line_enabled"),
                 "project_data.rb: line_gap/line_enabled — нормализация настроек уровня шаблона")
          assert(lb_text.include?("page_cfg[:line_gap] || page_cfg[\"line_gap\"]"),
                 "layout_builder.rb: зазор и линия читаются из настроек шаблона (page_cfg)")
          assert(lb_text.include?("def add_thin_line"),
                 "layout_builder.rb: тонкая линия-разделитель рисуется через add_thin_line")
          assert(js.include?('k !== "line_gap" && k !== "line_enabled"'),
                 "app.js: ensureCustomLayouts не стирает line_gap/line_enabled — настройки шапки не сбрасываются")
          assert(js.include?("cfg.line_gap") && js.include?("cfg.line_enabled"),
                 "app.js: line_gap/line_enabled нормализуются при каждом проходе ensureCustomLayouts")

          # 2d. Прочие гарантии качества
          assert(!js.include?("Фасады МДФ, ЛДСП, Blum") && !js.include?("CF#260905_160129"),
                 "В источниках параметров нет текстовых заглушек-примеров")
          assert(!js.include?("toLocaleDateString"), "В превью нет локального формата даты (9/22/2026)")
          assert(js.include?("const previewDate ="), "app.js использует единый хелпер даты previewDate")
          assert(js.include?("histEntryText(h[0])"),
                 "«Последние изменения» берут первую (новейшую) запись истории, как Ruby-экспорт")
        end

        # ------------------------------------------------------------------
        # 83. Сброс шаблона и хранение: layout_builder читает params нового формата
        # ------------------------------------------------------------------
        def test_83_template_params_render_reads_new_config_only
          puts "\n--- 83. Рендер читает только params; старые ключи игнорируются ---"

          # 1. Старые ключи в конфиге (легаси layout.yaml) не рендерятся
          pd = tp_make_project
          cover = pd.pdf_settings[:custom_layouts][:cover]
          cover[:header] = { visible: true, lines: ["furniture_name"] }
          cover[:slot_1] = { visible: true, lines: ["articul"] }
          cover[:footer] = { visible: true, lines: ["footer_page_total"] }
          doc = tp_render(pd)
          assert(tp_texts(doc).empty?,
                 "Старые блоки header/slot_1/footer в конфиге не рендерятся (чистый лист)")

          # 2. Новый параметр рендерится рядом с «мусорными» ключами
          tp_add_param(pd, :cover, "project.room_name", label: "Помещение")
          doc2 = tp_render(pd)
          assert(tp_find_text(doc2, "Прихожая"), "Новый параметр выводится независимо от легаси-ключей")
          assert(tp_texts(doc2).size == 1, "На странице ровно один текстовый блок — созданный параметр")
        end

        # ------------------------------------------------------------------
        # 85. Высота блока учитывает заголовок; переполнение колонки не дает
        #     наложения верхней и нижней групп; дефолты блоков и blank
        # ------------------------------------------------------------------
        def test_85_template_params_height_label_and_overflow_clamp
          puts "\n--- 85. Высота с заголовком / клампинг переполнения колонки / дефолты ---"

          # 1. Высота бокса считается по итоговому тексту «Заголовок: значение»
          pd = tp_make_project
          long_label = "Очень длинный заголовок параметра для проверки"
          tp_add_param(pd, :cover, "project.articul", label: long_label)
          doc = tp_render(pd)
          ent = tp_find_text(doc, "CF#")
          assert(ent, "Параметр с длинным заголовком выведен")
          expected_h = LB.send(:estimate_text_height, "#{long_label}: CF#260922_100000",
                               10.0, CONTENT_W * 0.45, "Sofia Sans Condensed", false) + 1.5
          actual_h = ent.bounds.height * 72.0
          assert((actual_h - expected_h).abs < 0.6,
                 "Высота бокса = оценка итогового текста с заголовком (#{actual_h.round(1)} ≈ #{expected_h.round(1)} pt)")

          # 2. Переполнение колонки: нижняя группа прижимается вниз,
          #    наложения текстов верхней и нижней групп нет
          pd2 = tp_make_project
          pd2.project_info[:description] = "Корпусная мебель из ЛДСП 16 мм с фасадами МДФ, наполнение Blum. " * 6
          pd2.workflow[:stadia] = Array.new(8) { |i| { name: "Этап №#{i + 1}", status: i.even? } }
          list2 = tp_params(pd2, :cover)
          4.times do |i|
            list2 << { id: "t#{i}", source: "project.description", label: "Описание", align: "left", valign: "top",
                       show_label: true, font_family: "", font_size: 10.0, color: "#0F172A", visible: true }
          end
          2.times do |i|
            list2 << { id: "b#{i}", source: "workflow.stadia", label: "", align: "left", valign: "bottom",
                       show_label: false, font_family: "", font_size: 10.0, color: "#0F172A", visible: true }
          end
          doc2 = tp_render(pd2)
          texts2 = tp_texts(doc2)
          top_last = texts2.select { |t| t.plain_text.to_s.start_with?("Описание:") }
                           .map { |t| (t.bounds.y + t.bounds.height) * 72.0 }.max
          bot_first = texts2.select { |t| t.plain_text.to_s.strip == "Этап №1" }
                            .map { |t| t.bounds.y * 72.0 }.min
          assert(top_last && bot_first, "Верхний и нижний стеки выведены (режим переполнения)")
          clearance = bot_first - top_last
          # зазор между нижней кромкой верхнего стека и первой строкой нижнего;
          # у верхнего бокса в bounds уже сидит запас +1.5 pt, поэтому ~5.6, а не 7.1
          assert(clearance >= 4.0 && clearance <= 9.0,
                 "Нижний стек прижат вниз и начинается ниже верхнего (зазор #{clearance.round(1)} pt)")

          # 3. Дефолт show_label: у обычного параметра — true, у блока — false
          norm_p = pd2.send(:normalize_template_params, [{ source: "a.a" }])
          assert(norm_p.first[:show_label] == true, "Параметр без show_label → true")
          assert(!norm_p.first.key?(:line_gap) && !norm_p.first.key?(:line_enabled),
                 "У параметра нет line_gap/line_enabled — настройка общая, на уровне шаблона")
          cover85 = pd2.pdf_settings[:custom_layouts][:cover]
          assert(cover85[:line_gap] == 2.5 && cover85[:line_enabled] == false,
                 "Дефолт шаблона: 2,5 мм, линия выключена")
          norm_g = pd2.send(:normalize_template_params, [{ group: true, label: "Блок", params: [{ source: "a.a" }] }])
          assert(norm_g.first[:show_label] == false, "Блок без show_label → false (как в диалоге)")

          # 4. Шаблон blank есть в Ruby-дефолтах (как в диалоге и layout.yaml)
          assert(tp_make_project.pdf_settings[:custom_layouts].key?(:blank),
                 "Шаблон blank присутствует в default_custom_layouts")
        end

        # ------------------------------------------------------------------
        # 86. «Размер между строками» и «Линия» — общие настройки шаблона
        # ------------------------------------------------------------------
        def test_86_template_params_line_gap_and_separator
          puts "\n--- 86. Размер между строками / линия-разделитель (настройки шаблона) ---"

          # 1. Дефолты на уровне шаблона; у параметров полей больше нет
          pd0 = tp_make_project
          cover0 = pd0.pdf_settings[:custom_layouts][:cover]
          assert(cover0[:line_gap] == 2.5 && cover0[:line_enabled] == false,
                 "Дефолт шаблона: размер между строками 2,5 мм, линия выключена")
          norm0 = pd0.send(:normalize_template_params, [{ source: "a.a" }])
          assert(!norm0.first.key?(:line_gap) && !norm0.first.key?(:line_enabled),
                 "line_gap/line_enabled — не поля параметра, а общие настройки шаблона")

          # 2. line_gap шаблона задает зазор между всеми строками зоны:
          #    расстояние между верхами двух текстов = высота первого + зазор
          pd = tp_make_project
          tp_add_param(pd, :cover, "project.room_name", label: "Помещение")
          tp_add_param(pd, :cover, "project.articul")
          tops = lambda do |doc|
            texts = tp_texts(doc)
            room = texts.find { |t| t.plain_text.to_s.include?("Помещение") }
            art = texts.find { |t| t.plain_text.to_s.include?("CF#") }
            [room.bounds.y * 72.0, art.bounds.y * 72.0]
          end
          y_default = tops.call(tp_render(pd))
          d_default = y_default[1] - y_default[0]
          pd.pdf_settings[:custom_layouts][:cover][:line_gap] = 10.0
          y_wide = tops.call(tp_render(pd))
          d_wide = y_wide[1] - y_wide[0]
          delta_mm = (d_wide - d_default) * 25.4 / 72.0
          assert((delta_mm - 7.5).abs < 0.2,
                 "line_gap=10 мм раздвигает строки на 7,5 мм относительно дефолта 2,5 (#{delta_mm.round(2)} мм)")

          # 3. «Линия» — ровно по одному разделителю между парами соседних
          #    строк зоны (параметры и блок), после последней строки линии нет
          assert(tp_entities(tp_render(pd)).grep(::Layout::Path).empty?,
                 "Без «Линии» разделителей на странице нет")
          pd.pdf_settings[:custom_layouts][:cover][:line_enabled] = true
          pd.project_info[:phone] = "+7 999 000-00-00"
          tp_params(pd, :cover) << {
            id: "g_test", group: true, label: "", show_label: false,
            align: "left", valign: "top", font_family: "", font_size: 10.0,
            color: "#0F172A", visible: true,
            params: [{ id: "c1", source: "customer.phone", label: "", show_label: false }]
          }
          doc3 = tp_render(pd)
          paths = tp_entities(doc3).grep(::Layout::Path)
          assert(paths.size == 2, "Три строки зоны (два параметра + блок) — два разделителя, между парами")
          assert(paths.all? { |l| l.points.size == 2 && l.points.first.y == l.points.last.y && l.points.last.x > l.points.first.x },
                 "Разделители — горизонтальные отрезки из двух точек")
          tops3 = tp_texts(doc3).map { |t| t.bounds.y * 72.0 }.sort
          ys = paths.map { |l| l.points.first.y * 72.0 }.sort
          assert(tops3.size == 3 && tops3[0] < ys[0] && ys[0] < tops3[1] && tops3[1] < ys[1] && ys[1] < tops3[2],
                 "Разделители лежат в зазорах между соседними строками зоны")

          # 4. Разделитель небольшой — шириной с текст строки, а не на всю колонку
          lens = paths.map { |l| (l.points.last.x - l.points.first.x) * 72.0 }
          page_w_pt = doc3.page_info.width * 72.0
          assert(lens.all? { |l| l.positive? && l < page_w_pt * 0.25 },
                 "Разделитель небольшой — шириной с текст строки (#{lens.map { |l| l.round(1) }.inspect} pt при странице #{page_w_pt.round} pt)")
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
        puts "  Проверка параметров шаблона (свободное размещение)"
        puts "=========================================================="

        test_79_template_params_placement
        test_80_template_params_sources
        test_81_template_params_per_template_and_yaml
        test_82_template_params_data_contract_and_js_guards
        test_83_template_params_render_reads_new_config_only
        test_84_template_params_group_block
        test_85_template_params_height_label_and_overflow_clamp
        test_86_template_params_line_gap_and_separator

        puts "=========================================================="
        puts "  ИТОГИ ТЕСТИРОВАНИЯ: Успешно: #{@passed}, Ошибок: #{@failed}"
        puts "=========================================================="
        exit(@failed.zero? ? 0 : 1)
      end
    end

    StandaloneParamsRunner.new.run_all
  end
end
