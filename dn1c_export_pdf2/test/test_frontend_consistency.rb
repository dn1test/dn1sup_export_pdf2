# frozen_string_literal: true

# -------------------------------------------------------------------------------
# Проверка консистентности фронтенда и Ruby-бэкенда DN1C Export PDF 2:
#
# 1. Мёртвые id: ссылки els.xxx = document.getElementById("...") в app.js,
#    которым нет соответствующего элемента ни в одном Vue-компоненте
#    (и в собранном dialog/html/index.html).
# 2. Ключи pdf_settings, отправляемые collectFormData / dev-моком getData,
#    должны входить в белый список Ruby (PDF_SETTINGS_ALLOWED) — иначе
#    sanitize_pdf_settings молча выбросит значение.
# 3. Ключи dev-мока getData должны совпадать с реальными ключами бэкенда
#    (default_pdf_settings), чтобы npm run dev не искажал поведение.
#
# Запуск отдельно:
#   ruby -I dn1c_export_pdf2 dn1c_export_pdf2/test/test_frontend_consistency.rb
# -------------------------------------------------------------------------------

require_relative "mock_sketchup"
require_relative "../main"

module DN1Code
  module ExportPdf2
    class FrontendConsistencyRunner
      ROOT     = File.expand_path("../..", __dir__)
      APP_JS   = File.join(ROOT, "frontend", "src", "legacy", "app.js")
      VUE_DIR  = File.join(ROOT, "frontend", "src")
      BUILT    = File.join(ROOT, "dn1c_export_pdf2", "dialog", "html", "index.html")
      PD       = ::DN1Code::ExportPdf2::Model::ProjectData

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

      def app_js
        @app_js ||= File.read(APP_JS, encoding: "utf-8")
      end

      def all_frontend_ids
        return @all_ids if @all_ids

        ids = Set.new
        Dir.glob(File.join(VUE_DIR, "**", "*.vue")).each do |f|
          File.read(f, encoding: "utf-8").scan(/\bid="([^"]+)"/) { |m| ids << Regexp.last_match(1) }
        end
        File.read(BUILT, encoding: "utf-8").scan(/\bid="([^"]+)"/) { |m| ids << Regexp.last_match(1) } if File.exist?(BUILT)
        # index.html диалога (вне Vue) тоже источник id
        app_js.scan(/getElementById\("([^"]+)"\)/) { |_| } # сами ссылки не считаем элементами
        @all_ids = ids
      end

      def run_all
        require "set"
        puts "=========================================================="
        puts "  Консистентность фронтенда и Ruby-бэкенда"
        puts "=========================================================="

        # --- 1. Мёртвые id ---
        puts "\n--- 1. Ссылки els.* на несуществующие элементы ---"
        referenced = {}
        app_js.scan(/getElementById\("([^"]+)"\)/) { referenced[Regexp.last_match(1)] = true }
        dead = referenced.keys.reject { |id| all_frontend_ids.include?(id) }
        # id из legacy-разметки index.html диалога (не Vue) — проверяем и их
        dialog_html = File.join(ROOT, "frontend", "index.html")
        if File.exist?(dialog_html)
          File.read(dialog_html, encoding: "utf-8").scan(/\bid="([^"]+)"/) { |m| dead.delete(Regexp.last_match(1)) }
        end
        # Мягкие ссылки: элементы удалены из UI, каждое обращение защищено
        # проверкой на null с фолбэком на state — осознанный шаблон. Новые
        # мёртвые id должны попадать сюда явно, иначе проверка падает.
        soft_ok = %w[
          selectImageAspect customAspectGroup inputAspectCustomW inputAspectCustomH
          selectAnnotationFontSize selectStamp customStampGroup inputCustomStamp
          inputPrimaryColor primaryColorHex inputStampColor stampColorHex
          selectPageSize selectCompression selectQuality selectFontFamily selectLayoutFontFamily
          inputTags inputStatus scenesSplitResizer
        ]
        hard_dead = dead - soft_ok
        assert(hard_dead.empty?, "нет мёртвых id вне известного мягкого списка: #{hard_dead.inspect}")
        unlisted_soft = (dead & soft_ok)
        puts "  [INFO] мягкие ссылки с фолбэком (ok, #{unlisted_soft.size} шт.): #{unlisted_soft.sort.inspect}"

        # --- 2. Ключи collectFormData входят в белый список Ruby ---
        puts "\n--- 2. Ключи collectFormData vs PDF_SETTINGS_ALLOWED ---"
        allowed = PD::PDF_SETTINGS_ALLOWED + [:custom_layouts]
        # Вырезаем блок state.pdf_settings = { ... } именно внутри collectFormData
        cf_start = app_js.index("function collectFormData")
        block = ""
        if cf_start
          ps_start = app_js.index("state.pdf_settings = {", cf_start)
          block = brace_block(app_js, ps_start + "state.pdf_settings = ".length) if ps_start
        end
        js_keys = block.scan(/^(\s+)(\w+):/).select { |ind, _| ind.length == 6 }.map { |_, k| k.to_sym }.uniq
        missing = js_keys - allowed
        assert(!js_keys.empty?, "collectFormData: блок pdf_settings найден (#{js_keys.size} ключей)")
        assert(missing.empty?,
               "все ключи collectFormData принимает Ruby-белый список; лишние: #{missing.inspect}")

        # --- 3. Ключи dev-мока getData ---
        puts "\n--- 3. Dev-мок getData vs реальные ключи бэкенда ---"
        mock_start = app_js.index('if (action === "getData")')
        mock_block = ""
        if mock_start
          ps_start = app_js.index("pdf_settings: {", mock_start)
          mock_block = brace_block(app_js, ps_start + "pdf_settings: ".length) if ps_start
        end
        mock_keys = top_level_keys(mock_block)
        defaults = PD.new.send(:default_pdf_settings).keys
        wrong_keys = mock_keys - defaults
        assert(!mock_keys.empty?, "dev-мок: блок pdf_settings найден (#{mock_keys.size} ключей)")
        assert(wrong_keys.empty?,
               "dev-мок getData использует только реальные ключи бэкенда; неверные: #{wrong_keys.inspect}")
        assert(mock_keys.include?(:render_quality), "dev-мок отдаёт render_quality (не 'quality')")
        assert(mock_keys.include?(:save_skp_backup), "dev-мок отдаёт save_skp_backup (не 'save_backup')")

        # --- 4. Опции UI-списков соответствуют Ruby-белым спискам ---
        puts "\n--- 4. Опции select vs Ruby-белые списки ---"
        settings_vue = File.join(VUE_DIR, "components", "SettingsTab.vue")
        if File.exist?(settings_vue)
          src = File.read(settings_vue, encoding: "utf-8")
          %w[landscape portrait].each do |v|
            assert(src.include?("\"#{v}\"") || src.include?("'#{v}'") || src.include?("value=\"#{v}\""),
                   "SettingsTab: page_layout предлагает #{v}")
          end
          assert(src =~ /value="A3"/, "SettingsTab: page_size предлагает A3")
          %w[low medium high].each do |v|
            assert(src.include?(v), "SettingsTab: render_quality предлагает #{v}")
          end
          %w[png jpg].each do |v|
            assert(src.include?("value=\"#{v}\"") || src.include?("'#{v}'"),
                   "SettingsTab: image_format предлагает #{v}")
          end
          %w[image hybrid].each do |v|
            assert(src.include?("\"#{v}\"") || src.include?("'#{v}'"),
                   "SettingsTab: layout_render_mode предлагает #{v}")
          end
        else
          assert(false, "SettingsTab.vue найден")
        end

        # --- 5. page_size больше не захардкожен в collectFormData ---
        puts "\n--- 5. collectFormData: page_size из выпадающего списка ---"
        assert(!block.match?(/^\s{6}page_size: "A3",$/),
               "page_size не захардкожен в collectFormData (читается из selectPageSize)")

        # --- 6. Обёртки ui.scenes строятся с текущими объектами state.scenes ---
        puts "\n--- 6. renderScenesTable: обёртки сцен без устаревших ссылок ---"
        rs_start = app_js.index("function renderScenesTable")
        assign = app_js.index("ui.scenes = scenes.map", rs_start) if rs_start
        rs_block = assign ? brace_block(app_js, app_js.index("{", assign)) : ""
        assert(!rs_block.empty?, "renderScenesTable: найдено присваивание ui.scenes = scenes.map(...)")
        assert(!rs_block.include?("prev"), "обёртки сцен не переиспользуют prev (устаревшие item после onScenesRefreshed ломали галочки «Вкл»)")
        assert(rs_block.include?("uid:") && rs_block.include?("item"),
               "обёртки сцен содержат стабильный uid (ключ v-for) и текущий item")

        puts "=========================================================="
        puts "  ИТОГИ ТЕСТИРОВАНИЯ: Успешно: #{@passed}, Ошибок: #{@failed}"
        puts "=========================================================="
        exit(@failed.zero? ? 0 : 1)
      end

      private

      # Ключи верхнего уровня объектного литерала (по отступу первого ключа)
      def top_level_keys(block)
        first = block.scan(/^(\s+)(\w+):/).first
        return [] unless first

        indent = first[0]
        block.scan(/^(#{Regexp.escape(indent)})(\w+):/).map { |_, k| k.to_sym }.uniq
      end

      # Текст сбалансированного по скобкам объектного литерала,
      # начинающегося в позиции brace_pos (символ '{')
      def brace_block(src, brace_pos)
        depth = 0
        in_str = nil
        i = brace_pos
        while i < src.length
          ch = src[i]
          if in_str
            in_str = nil if ch == in_str && src[i - 1] != "\\"
          elsif ch == '"' || ch == "'"
            in_str = ch
          elsif ch == "{"
            depth += 1
          elsif ch == "}"
            depth -= 1
            return src[brace_pos..i] if depth.zero?
          end
          i += 1
        end
        ""
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  DN1Code::ExportPdf2::FrontendConsistencyRunner.new.run_all
end
