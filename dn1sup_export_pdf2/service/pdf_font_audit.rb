# frozen_string_literal: true

require "zlib"

require_relative "font_service"

module DN1Code
  module ExportPdf2
    module Service
      # Аудит встроенных шрифтов готового PDF. Детектирует ситуацию, когда
      # LayOut не нашёл запрошенный шрифт (шрифт из config/fonts) и заменил
      # его системным фолбэком (Verdana, Microsoft Sans Serif и т.п.).
      module PdfFontAudit
        # Нормализованные имена известных фолбэк-шрифтов
        KNOWN_FALLBACKS = %w[verdana microsoftsansserif].freeze

        class << self
          # Список PostScript-имен шрифтов, встроенных в PDF (включая сжатые потоки).
          # @param pdf_path [String]
          # @return [Array<String>]
          def embedded_fonts(pdf_path)
            content = File.binread(pdf_path)
            names = content.scan(/\/BaseFont\s*\/([^\s\/<>\[\]()]+)/).flatten
            content.scan(/stream\r?\n(.*?)\r?\nendstream/m).each do |m|
              begin
                inflated = Zlib::Inflate.inflate(m[0])
                names.concat(inflated.scan(/\/BaseFont\s*\/([^\s\/<>\[\]()]+)/).flatten)
              rescue StandardError
                # поток не deflate (например, DCTDecode) — пропускаем
              end
            end
            names.uniq
          rescue StandardError => e
            warn "[DN1Sup Export PDF] PdfFontAudit: не удалось прочитать #{pdf_path}: #{e.message}"
            []
          end

          # Проверяет, что ожидаемый шрифт встроен в PDF. При отсутствии —
          # предупреждает в консоль (fallback LayOut) и возвращает false.
          # @param pdf_path [String]
          # @param expected_family [String, nil] ожидаемое имя шрифта (как в LayOut)
          # @return [Boolean] true, если ожидаемый шрифт найден (или проверить не удалось)
          def audit_exported_pdf!(pdf_path, expected_family = nil)
            fonts = embedded_fonts(pdf_path)
            return true if fonts.empty?

            normalized = fonts.map { |f| normalize(f) }
            prefixes = expected_family.nil? ? [] : expected_prefixes(expected_family)
            expected_ok = expected_family.nil? ||
                          normalized.any? { |n| prefixes.any? { |p| n.start_with?(p) } }
            fallbacks = normalized.select { |n| KNOWN_FALLBACKS.include?(n) }
            return true if expected_ok && fallbacks.empty?

            parts = []
            if expected_family && !expected_ok
              parts << "ожидаемый шрифт '#{expected_family}' НЕ встроен"
            end
            unless fallbacks.empty?
              fb_names = fonts.select { |f| KNOWN_FALLBACKS.include?(normalize(f)) }
              parts << "обнаружены фолбэк-шрифты: #{fb_names.uniq.join(', ')}"
            end
            warn "[DN1Sup Export PDF] Аудит шрифтов (#{File.basename(pdf_path)}): #{parts.join('; ')}. " \
                 "Встроены: #{fonts.join(', ')}. Если шрифт установлен — перезапустите SketchUp/LayOut."
            false
          rescue StandardError => e
            warn "[DN1Sup Export PDF] PdfFontAudit: #{e.message}"
            true
          end

          # "AMEJOL+Oswald-Light" => "oswaldlight"
          # @param name [String]
          # @return [String]
          def normalize(name)
            base = name.to_s.split("+").last || name.to_s
            base.downcase.gsub(/[^a-z0-9]/, "")
          end

          # Префиксы, по которым ожидаемый шрифт признаётся встроенным.
          # PostScript-имена несут стилевой суффикс ("SofiaSansCondensed-Regular"),
          # а для переименованных семейств ("Sofia Sans ExtraCond") имя из
          # настроек вообще не префикс встроенного — поэтому берутся и ключ
          # AVAILABLE_FONTS, и точное имя начертания из LAYOUT_FACE_NAMES.
          # @param family_name [String]
          # @return [Array<String>]
          def expected_prefixes(family_name)
            prefixes = [normalize(family_name)]
            family_key = FontService.match_available_family(family_name)
            if family_key
              prefixes << normalize(family_key)
              face = FontService::LAYOUT_FACE_NAMES[family_key]
              prefixes << normalize(face) if face
            end
            prefixes.compact.uniq
          rescue StandardError
            [normalize(family_name)]
          end
        end
      end
    end
  end
end
