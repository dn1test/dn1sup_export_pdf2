# frozen_string_literal: true

# -------------------------------------------------------------------------------
# Проверка мастер-шаблона (звезда в списке шаблонов).
#
# Мастер-шаблон — «основа» страницы: при экспорте его параметры рендерятся на
# всех страницах, кроме обложек (встроенный cover и пользовательские шаблоны
# на базе cover), ПЕРЕД параметрами собственных шаблонов страниц (в тех же
# зонных стеках — элементы дополняются рядом, а не наезжают). Общие настройки
# стека (line_gap/line_enabled), шрифт страницы и видовой экран (image_4_3)
# берутся от мастера. Назначения page_type страниц не меняются.
#
# Каждый тест проверяет ФАКТИЧЕСКИЙ результат: конфиг после слияния, тексты и
# позиции в мок-документе LayOut, нормализацию настроек (whitelist).
#
# Запуск отдельно:
#   ruby -I dn1c_export_pdf2 dn1c_export_pdf2/test/test_master_template.rb
# В составе общего прогона подключается из comprehensive_test.rb
# -------------------------------------------------------------------------------

require_relative "mock_sketchup"
require_relative "../main"
require "json"

module DN1Code
  module ExportPdf2
    module TestSupport
      module MasterTemplateTests
        LB = ::DN1Code::ExportPdf2::Service::LayoutBuilder

        # ------------------------------------------------------------------
        # Хелперы
        # ------------------------------------------------------------------

        def mt_make_project
          pd = ::DN1Code::ExportPdf2::Model::ProjectData.new
          # Тест не должен зависеть от локального config/layout.yaml пользователя
          pd.pdf_settings[:custom_layouts] = pd.send(:default_custom_layouts)
          pd.project_info.merge!(
            furniture_name: "Шкаф-купе АЛЬФА",
            room_name:      "Прихожая",
            articul:        "CF#260922_100000"
          )
          pd
        end

        # Не-обложечный пользовательский шаблон, назначаемый мастером
        def mt_add_master_tpl(pd)
          pd.pdf_settings[:custom_layouts][:master_tpl] = {
            name: "Мастер", _name: "Мастер", _base_type: "general",
            image_4_3: pd.pdf_settings[:custom_layouts][:general][:image_4_3].dup,
            params: [], line_gap: 2.5, line_enabled: false
          }
        end

        # Включить мастер-шаблон (как это делает звезда в списке шаблонов)
        def mt_enable_master(pd, key)
          pd.pdf_settings[:master_template_enabled] = true
          pd.pdf_settings[:master_template_key]     = key.to_s
        end

        def mt_add_param(pd, tpl, source, attrs = {})
          cfg = pd.pdf_settings[:custom_layouts][tpl] ||= {}
          cfg[:params] ||= []
          cfg[:params] << {
            id:         "p_mt_#{cfg[:params].size}",
            source:     source,
            label:      "",
            show_label: true,
            align:      "left",
            valign:     "top",
            font_size:  10.0,
            color:      "#0F172A",
            visible:    true
          }.merge(attrs)
        end

        # Пользовательский шаблон на базе cover (как createCustomTemplate)
        def mt_add_cover_based_template(pd)
          pd.pdf_settings[:custom_layouts][:custom_cover_tpl] = {
            name: "Моя обложка", _name: "Моя обложка", _base_type: "cover",
            image_4_3: pd.pdf_settings[:custom_layouts][:cover][:image_4_3].dup,
            params: [], line_gap: 2.5, line_enabled: false
          }
        end

        # Рендер одной страницы в мок-документ
        def mt_render(pd, scene_type: :general, scene_name: "02. Тестовая сцена")
          doc = ::Layout::Document.new
          ctx = LB.send(:build_context, pd, nil, "Sofia Sans Condensed")
          scene = ::DN1Code::ExportPdf2::Model::SceneItem.new(name: scene_name, page_type: scene_type)
          LB.send(:render_modular_page, doc, doc.pages.first, doc.layers.first, scene,
                  2, 4, doc.page_info.width, doc.page_info.height, doc.page_info.left_margin,
                  ctx, [])
          doc
        end

        def mt_entities(doc)
          if doc.respond_to?(:entities) && doc.method(:entities).arity.zero?
            doc.entities.map { |rec| rec[:entity] }
          else
            doc.pages.flat_map { |page| page.entities.to_a }
          end
        end

        def mt_texts(doc)
          mt_entities(doc).grep(::Layout::FormattedText)
        end

        def mt_find_text(doc, fragment)
          mt_texts(doc).find { |t| t.plain_text.to_s.include?(fragment) }
        end

        def mt_paths(doc)
          mt_entities(doc).grep(::Layout::Path)
        end

        # ------------------------------------------------------------------
        # 90. Слияние конфигов: мастер-основа + параметры страницы, guard-и
        # ------------------------------------------------------------------
        def test_90_master_template_merge_config
          puts "\n--- 90. Мастер-шаблон: слияние конфигов и guard-и ---"

          # 1. Мастер выключен — конфиг страницы возвращается как есть
          pd = mt_make_project
          mt_add_master_tpl(pd)
          mt_add_param(pd, :general, "project.articul", label: "Артикул")
          ctx = LB.send(:build_context, pd, nil, "Sofia Sans Condensed")
          own_cfg = LB.send(:get_page_cfg, ctx, :general)
          merged = LB.send(:merge_master_page_cfg, ctx, :general, own_cfg)
          assert(merged.equal?(own_cfg), "Мастер выключен → конфиг страницы без изменений (тот же объект)")

          # 2. Мастер включен: params = мастера + свои; line_gap/line_enabled/
          #    image_4_3 — от мастера (основа); настройки в ctx не мутируются
          mt_enable_master(pd, :master_tpl)
          mt_add_param(pd, :master_tpl, "project.furniture_name", label: "Изделие")
          pd.pdf_settings[:custom_layouts][:master_tpl][:line_gap] = 7.0
          pd.pdf_settings[:custom_layouts][:master_tpl][:line_enabled] = true
          ctx2 = LB.send(:build_context, pd, nil, "Sofia Sans Condensed")
          own2 = LB.send(:get_page_cfg, ctx2, :general)
          merged2 = LB.send(:merge_master_page_cfg, ctx2, :general, own2)
          sources = merged2[:params].map { |p| p[:source] }
          assert(sources.first == "project.furniture_name" && sources.last == "project.articul",
                 "Параметры мастера идут первыми, свои — после (#{sources.inspect})")
          assert(merged2[:params].size == 2, "В merged-списке ровно два параметра")
          assert(merged2[:line_gap] == 7.0 && merged2[:line_enabled] == true,
                 "line_gap/line_enabled берутся от мастера (основа)")
          assert(own2[:line_gap] == 2.5 && own2[:line_enabled] == false,
                 "Собственный конфиг страницы не мутируется")
          assert(pd.pdf_settings[:custom_layouts][:master_tpl][:params].size == 1 &&
                 pd.pdf_settings[:custom_layouts][:general][:params].size == 1,
                 "Списки params в custom_layouts не изменяются слиянием")

          # 3. Обложка (встроенный cover) мастером не затрагивается
          own_cover = LB.send(:get_page_cfg, ctx2, :cover)
          merged_cover = LB.send(:merge_master_page_cfg, ctx2, :cover, own_cover)
          assert(merged_cover.equal?(own_cover), "Встроенная обложка (cover) исключена из мастера")

          # 4. Пользовательский шаблон на базе cover (_base_type) — тоже обложка
          mt_add_cover_based_template(pd)
          own_cc = LB.send(:get_page_cfg, ctx2, :custom_cover_tpl)
          merged_cc = LB.send(:merge_master_page_cfg, ctx2, :custom_cover_tpl, own_cc)
          assert(merged_cc.equal?(own_cc), "Шаблон с _base_type=cover исключен из мастера")

          # 5. Страница уже на мастере — слияния нет (без дублирования параметров)
          own_master = LB.send(:get_page_cfg, ctx2, :master_tpl)
          merged_self = LB.send(:merge_master_page_cfg, ctx2, :master_tpl, own_master)
          assert(merged_self.equal?(own_master), "Страница на самом мастере не удваивает параметры")

          # 6. Несуществующий ключ мастера — фолбэк на собственный шаблон
          mt_enable_master(pd, :deleted_tpl)
          ctx3 = LB.send(:build_context, pd, nil, "Sofia Sans Condensed")
          own3 = LB.send(:get_page_cfg, ctx3, :general)
          assert(LB.send(:merge_master_page_cfg, ctx3, :general, own3).equal?(own3),
                 "Мастер с отсутствующим ключом → фолбэк на собственный шаблон")
          assert(LB.send(:active_master_cfg, ctx3).nil?, "active_master_cfg: отсутствующий ключ → nil")

          # 7. cover_page? на строковых и символьных ключах
          assert(LB.send(:cover_page?, ctx2, "cover") && LB.send(:cover_page?, ctx2, :cover),
                 "cover_page?: встроенный cover в строковом и символьном виде")
          assert(LB.send(:cover_page?, ctx2, :custom_cover_tpl), "cover_page?: _base_type=cover")
          assert(!LB.send(:cover_page?, ctx2, :general), "cover_page?: general — не обложка")
        end

        # ------------------------------------------------------------------
        # 91. Рендер: параметры мастера + страницы в одном зонном стеке,
        #     обложка не затронута, линия-разделитель от мастера
        # ------------------------------------------------------------------
        def test_91_master_template_render
          puts "\n--- 91. Мастер-шаблон: рендер страницы (стек, обложка, линия) ---"

          # 1. Мастер выключен — на странице general только свои параметры
          pd = mt_make_project
          mt_add_master_tpl(pd)
          mt_add_param(pd, :general, "project.articul", label: "Артикул")
          doc_off = mt_render(pd, scene_type: :general)
          assert(mt_find_text(doc_off, "CF#260922_100000"), "Без мастера: свой параметр выведен")
          assert(mt_texts(doc_off).size == 1, "Без мастера: на странице один текстовый блок")

          # 2. Мастер включен: параметры мастера + свои в одной зоне — друг под
          #    другом, мастер первым
          mt_enable_master(pd, :master_tpl)
          mt_add_param(pd, :master_tpl, "project.furniture_name", label: "Изделие")
          doc_on = mt_render(pd, scene_type: :general)
          assert(mt_find_text(doc_on, "Шкаф-купе АЛЬФА"), "Параметр мастера выведен на странице general")
          assert(mt_find_text(doc_on, "CF#260922_100000"), "Свой параметр страницы сохранен")
          assert(mt_texts(doc_on).size == 2, "Мастер + страница: два текстовых блока")
          y_master = mt_find_text(doc_on, "Шкаф-купе АЛЬФА").bounds.y * 72.0
          y_own = mt_find_text(doc_on, "CF#260922_100000").bounds.y * 72.0
          assert(y_own > y_master, "В зонном стеке мастер идет первым, свой параметр — под ним " \
                 "(#{y_master.round(1)} → #{y_own.round(1)} pt)")

          # 3. Линия-разделитель мастера переносится на страницу общего вида
          pd.pdf_settings[:custom_layouts][:master_tpl][:line_enabled] = true
          doc_line = mt_render(pd, scene_type: :general)
          paths = mt_paths(doc_line)
          assert(paths.size == 1, "«Линия» мастера: один разделитель между двумя строками зоны (#{paths.size})")

          # 4. Обложка не затронута: только свои параметры, без мастера
          mt_add_param(pd, :cover, "project.room_name", label: "Помещение")
          doc_cover = mt_render(pd, scene_type: :cover)
          assert(mt_find_text(doc_cover, "Прихожая"), "Обложка: свой параметр выведен")
          assert(!mt_find_text(doc_cover, "Шкаф-купе АЛЬФА"),
                 "Обложка: параметр мастера НЕ выведен")
          assert(mt_texts(doc_cover).size == 1, "Обложка: на странице один текстовый блок")

          # 5. Пользовательская обложка (на базе cover) тоже не затронута
          mt_add_cover_based_template(pd)
          mt_add_param(pd, :custom_cover_tpl, "project.room_name", label: "Помещение")
          doc_cc = mt_render(pd, scene_type: :custom_cover_tpl, scene_name: "00. Титул")
          assert(mt_find_text(doc_cc, "Прихожая") && !mt_find_text(doc_cc, "Шкаф-купе АЛЬФА"),
                 "Пользовательская обложка (_base_type=cover): мастер не применяется")

          # 6. Страница на самом мастере не удваивает параметры
          doc_self = mt_render(pd, scene_type: :master_tpl)
          furniture_ents = mt_texts(doc_self).select { |t| t.plain_text.include?("Шкаф-купе АЛЬФА") }
          assert(furniture_ents.size == 1, "Страница на мастере: параметр не задвоен (#{furniture_ents.size})")

          # 7. Шаблон blank (без параметров) + мастер → только параметры мастера
          pd_blank = mt_make_project
          mt_add_master_tpl(pd_blank)
          mt_enable_master(pd_blank, :master_tpl)
          mt_add_param(pd_blank, :master_tpl, "project.articul", label: "Артикул")
          doc_blank = mt_render(pd_blank, scene_type: :blank)
          assert(mt_find_text(doc_blank, "CF#260922_100000") && mt_texts(doc_blank).size == 1,
                 "blank + мастер: на странице параметры мастера")
        end

        # ------------------------------------------------------------------
        # 92. Настройки: whitelist/bool-нормализация + guard-тесты фронтенда
        # ------------------------------------------------------------------
        def test_92_master_template_settings_and_frontend_guards
          puts "\n--- 92. Мастер-шаблон: настройки (sanitize) и guard-тесты GUI ---"

          # 1. sanitize_pdf_settings: ключи мастера проходят whitelist,
          #    "true"/"false" приводятся к boolean, ключ нормализуется
          clean = ::DN1Code::ExportPdf2::Model::ProjectData.sanitize_pdf_settings(
            master_template_enabled: "true",
            master_template_key: "  custom_abc  "
          )
          assert(clean[:master_template_enabled] == true, "master_template_enabled: \"true\" → true")
          assert(clean[:master_template_key] == "custom_abc", "master_template_key нормализуется (strip)")

          clean_off = ::DN1Code::ExportPdf2::Model::ProjectData.sanitize_pdf_settings(
            master_template_enabled: "false",
            master_template_key: ""
          )
          assert(clean_off[:master_template_enabled] == false, "master_template_enabled: \"false\" → false")
          assert(!clean_off.key?(:master_template_key), "Пустой ключ мастера отбрасывается")

          # 2. Дефолты: мастер выключен, ключ пуст
          pd = mt_make_project
          assert(pd.pdf_settings[:master_template_enabled] == false &&
                 pd.pdf_settings[:master_template_key] == "",
                 "Дефолт pdf_settings: мастер выключен, ключ пуст")

          # 3. Guard-тесты фронтенда: звезда, тосты, автосейв, удаление, набор
          js = Dir[File.join(__dir__, "../../frontend/src/**/*.{js,vue}")].sort
                 .map { |f| (File.read(f, encoding: "utf-8") rescue "") }.join("\n")

          assert(js.include?("toggleMaster(tplKey)"), "templates-стор: toggleMaster переключает мастера")
          assert(js.include?("templates.toggleMaster(tpl.key)"), "TemplatesSidebar.vue: звезда вызывает toggleMaster")
          assert(js.include?("master_template_enabled: templates.masterEnabled") &&
                 js.include?("master_template_key: templates.masterKey"),
                 "payload.js отправляет ключи мастера (иначе автосейв их теряет)")
          assert(js.include?("master: isMaster && tpl.key === this.masterKey"),
                 "templates-стор: sidebarList помечает мастер-шаблон")
          assert(js.include?("clearStaleMaster()"), "templates-стор: висячая звезда сбрасывается (удаление/набор)")
          assert(js.include?("masterEnabled: false") && js.include?("masterKey: ''"),
                 "templates-стор: мастер — реактивное состояние для Vue")
          assert(js.include?("masterAffects"), "ScenesTab.vue: бейдж на страницах, затронутых мастером")
          assert(js.include?("tsb.masterTitle") && js.include?("toast.masterOn") &&
                 js.include?("toast.masterOff") && js.include?("scenes.masterBadgeTitle"),
                 "i18n: строки мастера присутствуют в словарях")

          ru = File.read(File.join(__dir__, "../../frontend/src/i18n/ru.js"), encoding: "utf-8")
          en = File.read(File.join(__dir__, "../../frontend/src/i18n/en.js"), encoding: "utf-8")
          %w[tsb.masterTitle tsb.masterActiveTitle tsb.masterBadge toast.masterOn toast.masterOff
             scenes.masterBadgeTitle].each do |key|
            assert(ru.include?("'#{key}'") && en.include?("'#{key}'"),
                   "i18n: ключ #{key} есть в ru.js и en.js")
          end
        end
      end
    end
  end
end

# -------------------------------------------------------------------------------
# Автономный запуск: ruby -I dn1c_export_pdf2 dn1c_export_pdf2/test/test_master_template.rb
# -------------------------------------------------------------------------------
if __FILE__ == $PROGRAM_NAME
  if defined?(Sketchup) && Sketchup.respond_to?(:version)
    puts "Тесты мастер-шаблона предназначены для запуска через терминал вне SketchUp GUI."
  else
    class StandaloneMasterRunner
      include DN1Code::ExportPdf2::TestSupport::MasterTemplateTests

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
        puts "  Проверка мастер-шаблона (основа всех страниц, кроме обложек)"
        puts "=========================================================="

        test_90_master_template_merge_config
        test_91_master_template_render
        test_92_master_template_settings_and_frontend_guards

        puts "=========================================================="
        puts "  ИТОГИ ТЕСТИРОВАНИЯ: Успешно: #{@passed}, Ошибок: #{@failed}"
        puts "=========================================================="
        exit(@failed.zero? ? 0 : 1)
      end
    end

    StandaloneMasterRunner.new.run_all
  end
end
