# frozen_string_literal: true

# -------------------------------------------------------------------------------
# Проверка консистентности фронтенда (Vue 3 + Pinia) и Ruby-бэкенда
# DN1Sup Export PDF 2:
#
# 1. Ключи pdf_settings, собираемые bridge/payload.js (collectFormData),
#    должны входить в белый список Ruby (PDF_SETTINGS_ALLOWED) — иначе
#    sanitize_pdf_settings молча выбросит значение.
# 2. Ключи pdf_settings dev-мока (bridge/mock.js, buildGetDataPayload)
#    должны совпадать с реальными ключами бэкенда (default_pdf_settings),
#    чтобы npm run dev не искажал поведение.
# 3. Опции select-ов SettingsTab соответствуют Ruby-белым спискам значений.
# 4. Все window.app.<fn>, которые дергает Ruby (execute_script в
#    export_dialog.rb), определены в bridge/sketchup.js.
# 5. Все callRuby("<action>") из фронтенда зарегистрированы в Ruby
#    (add_action_callback в export_dialog.rb).
#
# Запуск отдельно:
#   ruby -I dn1sup_export_pdf2 dn1sup_export_pdf2/test/test_frontend_consistency.rb
# -------------------------------------------------------------------------------

require_relative "mock_sketchup"
require_relative "../main"

module DN1Code
  module ExportPdf2
    class FrontendConsistencyRunner
      ROOT       = File.expand_path("../..", __dir__)
      SRC_DIR    = File.join(ROOT, "frontend", "src")
      PAYLOAD_JS = File.join(SRC_DIR, "bridge", "payload.js")
      MOCK_JS    = File.join(SRC_DIR, "bridge", "mock.js")
      BRIDGE_JS  = File.join(SRC_DIR, "bridge", "sketchup.js")
      DIALOG_RB  = File.join(ROOT, "dn1sup_export_pdf2", "dialog", "export_dialog.rb")
      SETTINGS_VUE = File.join(SRC_DIR, "components", "tabs", "SettingsTab.vue")
      PD         = ::DN1Code::ExportPdf2::Model::ProjectData

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

      def read(path)
        File.read(path, encoding: "utf-8")
      end

      def run_all
        puts "=========================================================="
        puts "  Консистентность фронтенда и Ruby-бэкенда"
        puts "=========================================================="

        payload_js = read(PAYLOAD_JS)
        mock_js    = read(MOCK_JS)
        bridge_js  = read(BRIDGE_JS)
        dialog_rb  = read(DIALOG_RB)

        # --- 1. Ключи collectFormData входят в белый список Ruby ---
        puts "\n--- 1. Ключи payload.js (collectFormData) vs PDF_SETTINGS_ALLOWED ---"
        allowed = PD::PDF_SETTINGS_ALLOWED + [:custom_layouts]
        ps_start = payload_js.index("const outPdfSettings = {")
        assert(ps_start, "payload.js: найден блок outPdfSettings")
        block = ps_start ? brace_block(payload_js, payload_js.index("{", ps_start)) : ""
        js_keys = top_level_keys(block)
        missing = js_keys - allowed
        assert(!js_keys.empty?, "payload.js: блок pdf_settings найден (#{js_keys.size} ключей)")
        assert(missing.empty?,
               "все ключи collectFormData принимает Ruby-белый список; лишние: #{missing.inspect}")
        assert(!block.match?(/page_size:\s*"A3"/),
               "page_size не захардкожен в payload.js (читается из settings-стора)")

        # --- 2. Ключи dev-мока getData ---
        puts "\n--- 2. Dev-мок getData vs реальные ключи бэкенда ---"
        mock_start = mock_js.index("pdf_settings: {")
        mock_block = mock_start ? brace_block(mock_js, mock_start) : ""
        mock_keys = top_level_keys(mock_block)
        defaults = PD.new.send(:default_pdf_settings).keys
        wrong_keys = mock_keys - defaults
        assert(!mock_keys.empty?, "dev-мок: блок pdf_settings найден (#{mock_keys.size} ключей)")
        assert(wrong_keys.empty?,
               "dev-мок getData использует только реальные ключи бэкенда; неверные: #{wrong_keys.inspect}")
        assert(mock_keys.include?(:render_quality), "dev-мок отдаёт render_quality (не 'quality')")
        assert(mock_keys.include?(:save_skp_backup), "dev-мок отдаёт save_skp_backup (не 'save_backup')")

        # --- 3. Опции UI-списков соответствуют Ruby-белым спискам ---
        puts "\n--- 3. Опции select vs Ruby-белые списки ---"
        assert(File.exist?(SETTINGS_VUE), "SettingsTab.vue найден")
        if File.exist?(SETTINGS_VUE)
          src = read(SETTINGS_VUE)
          %w[landscape portrait].each do |v|
            assert(src.include?("value=\"#{v}\"") || src.include?("'#{v}'"),
                   "SettingsTab: page_layout предлагает #{v}")
          end
          assert(src =~ /value="A3"/, "SettingsTab: page_size предлагает A3")
          %w[low medium high].each do |v|
            assert(src.include?("value=\"#{v}\""), "SettingsTab: render_quality предлагает #{v}")
          end
          %w[png jpg].each do |v|
            assert(src.include?("value=\"#{v}\""), "SettingsTab: image_format предлагает #{v}")
          end
          %w[image hybrid].each do |v|
            assert(src.include?("value=\"#{v}\""), "SettingsTab: layout_render_mode предлагает #{v}")
          end
        end

        # --- 4. Ruby → JS: все window.app.<fn> определены в мосте ---
        puts "\n--- 4. execute_script(window.app.*) vs bridge/sketchup.js ---"
        ruby_fns = dialog_rb.scan(/window\.app\.(\w+)/).flatten.uniq
        assert(!ruby_fns.empty?, "export_dialog.rb: найдены вызовы window.app.* (#{ruby_fns.size} шт.)")
        js_fns = bridge_js.scan(/^\s{4}(\w+)\(/).flatten.uniq
        undefined = ruby_fns - js_fns
        assert(undefined.empty?,
               "все window.app.* из Ruby определены в мосте; отсутствуют: #{undefined.inspect}")

        # --- 5. JS → Ruby: все callRuby-действия зарегистрированы ---
        puts "\n--- 5. callRuby(...) vs add_action_callback ---"
        frontend_actions = Dir.glob(File.join(SRC_DIR, "**", "*.{js,vue}")).flat_map do |f|
          read(f).scan(/callRuby\(\s*["'](\w+)["']/)
        end.flatten.uniq.sort
        ruby_actions = dialog_rb.scan(/add_action_callback\(["'](\w+)["']/).flatten.uniq
        assert(!frontend_actions.empty?, "фронтенд: найдены вызовы callRuby (#{frontend_actions.size} шт.)")
        unregistered = frontend_actions - ruby_actions
        assert(unregistered.empty?,
               "все callRuby-действия зарегистрированы в Ruby; незарегистрированные: #{unregistered.inspect}")

        # --- 6. Ruby → JS: обратное направление — зарегистрированные колбэки,
        #        которые фронтенд никогда не вызывает (мёртвый мост-код) ---
        puts "\n--- 6. add_action_callback без вызовов из фронтенда ---"
        unused_actions = ruby_actions - frontend_actions
        assert(unused_actions.empty?,
               "нет мёртвых колбэков моста; неиспользуемые: #{unused_actions.inspect}")

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
