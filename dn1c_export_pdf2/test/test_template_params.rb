# frozen_string_literal: true

# -------------------------------------------------------------------------------
# Проверка пользовательских параметров шаблона (вкладка «Шаблоны» →
# «Параметры страницы» → «+ Создать параметр»).
#
# Готовых списков параметров больше нет: параметр создается из источника данных
# («Данные проекта», «Папки спецификации», сцена, страница) и размещается
# свободно на странице (X/Y в %, выравнивание, кегль, цвет, заголовок, Вкл).
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

        def tp_find_text(doc, fragment)
          tp_texts(doc).find { |t| t.plain_text.to_s.include?(fragment) }
        end

        def tp_rects(doc)
          doc.entities.map { |rec| rec[:entity] }.grep(::Layout::Rectangle)
        end

        def tp_paths(doc)
          doc.entities.map { |rec| rec[:entity] }.grep(::Layout::Path)
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
          tp_add_param(pd_al, :cover, "project.articul", label: "A", x: 50.0, align: "center")
          tp_add_param(pd_al, :cover, "project.room_name", label: "B", x: 95.0, align: "right")
          doc_al = tp_render(pd_al)
          assert(tp_find_text(doc_al, "CF#").style.text_alignment == ::Layout::Style::ALIGN_CENTER,
                 "Выравнивание «Центр» → ALIGN_CENTER в стиле")
          assert(tp_find_text(doc_al, "Прихожая").style.text_alignment == ::Layout::Style::ALIGN_RIGHT,
                 "Выравнивание «Справа» → ALIGN_RIGHT в стиле")

          # 10. Шрифт параметра (font_family); пусто — шрифт страницы
          pd_ff = tp_make_project
          tp_add_param(pd_ff, :cover, "project.room_name", label: "Помещение", font_family: "Oswald")
          tp_add_param(pd_ff, :cover, "project.articul", label: "A", y: 30.0, font_family: "")
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
          tp_add_param(pd_st, :cover, "workflow.stadia", label: "Стадии", y: 30.0)
          doc_st = tp_render(pd_st)
          assert(tp_find_text(doc_st, "Эскизный проект") && tp_find_text(doc_st, "Рабочая документация"),
                 "Названия стадий выводятся строками")
          assert(tp_rects(doc_st).size == 3, "На каждую стадию рисуется квадрат-чекбокс (3 шт)")
          assert(tp_paths(doc_st).size == 1, "Галочка рисуется только для отмеченной стадии (1 шт)")

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
          assert(cover2[:params] == [], "Чистый лист: строки старой шапки/слотов не переносятся в параметры")
          assert(!cover2.key?(:header) && !cover2.key?(:slot_1), "Старые блоки в конфиг не попадают")

          # 4. load_from_layout_yaml: новая структура читается, params нормализуются
          new_path = File.join(dir, "layout_new.yaml")
          File.write(new_path, <<~YAML, encoding: "utf-8")
            ---
            layout:
              cover:
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
          assert(cover3[:image_4_3][:scale_pct] == 120 && cover3[:image_4_3][:aspect_ratio] == "16:9",
                 "Настройки видовоего окна сохраняются (ограничение масштаба — на рендере)")
          p2 = params3[1]
          assert(p2[:visible] == false, "visible: \"false\" → false")
          assert(p2[:font_size] == 10.0, "Отсутствующие поля получают дефолты")
          assert(p2[:valign] == "top" && p2[:font_family] == "", "valign и шрифт по умолчанию: top / «» (шрифт страницы)")

          # 6. Блок (group: true): нормализуется вместе с вложенными параметрами
          g = params3.find { |p| p[:group] == true }
          assert(g, "Блок (group: true) сохраняется при нормализации")
          assert(g[:params].size == 1, "Дитя блока без источника отбрасывается (1 шт)")
          child = g[:params].first
          assert(child[:source] == "project.room_name" && !child.key?(:x),
                 "Дитя блока нормализуется: источник сохранен, X/Y удалены")

          # 5. save_to_layout_yaml: параметры сохраняются и читаются обратно
          pd4 = tp_make_project
          tp_add_param(pd4, :cover, "customer.name", label: "Заказчик", x: 42.0, y: 96.0, align: "right")
          out_path = File.join(dir, "layout_out.yaml")
          assert(pd4.send(:save_to_layout_yaml, out_path), "layout.yaml сохраняется")
          pd5 = tp_make_project
          pd5.send(:load_from_layout_yaml, out_path)
          saved = pd5.pdf_settings[:custom_layouts][:cover][:params]
          assert(saved.size == 1 && saved.first[:source] == "customer.name" && saved.first[:align] == "right",
                 "Сохраненный параметр читается обратно без потерь")

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
          tp_add_param(pd, :cover, "project.room_name", label: "Помещение", y: 10.0)
          doc2 = tp_render(pd)
          assert(tp_find_text(doc2, "Прихожая"), "Новый параметр выводится независимо от легаси-ключей")
          assert(tp_texts(doc2).size == 1, "На странице ровно один текстовый блок — созданный параметр")
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

        puts "=========================================================="
        puts "  ИТОГИ ТЕСТИРОВАНИЯ: Успешно: #{@passed}, Ошибок: #{@failed}"
        puts "=========================================================="
        exit(@failed.zero? ? 0 : 1)
      end
    end

    StandaloneParamsRunner.new.run_all
  end
end
