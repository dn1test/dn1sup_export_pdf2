# frozen_string_literal: true

module DN1Code
  module ExportPdf2
    module Service
      module FontService
        FONT_NAME = "DIN Condensed"

        def self.setup_fonts(pdf_doc)
          fonts_dir = File.expand_path("../config/fonts", __dir__)
          din_font_path = File.join(fonts_dir, "DIN Condensed.ttf")

          if File.exist?(din_font_path)
            pdf_doc.font_families.update(
              FONT_NAME => {
                normal: din_font_path,
                bold: din_font_path,
                italic: din_font_path,
                bold_italic: din_font_path
              }
            )
            pdf_doc.font(FONT_NAME)
          else
            # Fallback to standard PDF font if custom font file is missing
            pdf_doc.font("Helvetica")
          end
        end

        def self.apply_style(pdf_doc, style = :body)
          case style
          when :title
            pdf_doc.font(FONT_NAME, size: 28)
          when :subtitle
            pdf_doc.font(FONT_NAME, size: 18)
          when :heading
            pdf_doc.font(FONT_NAME, size: 14)
          when :body
            pdf_doc.font(FONT_NAME, size: 11)
          when :small
            pdf_doc.font(FONT_NAME, size: 9)
          when :stamp
            pdf_doc.font(FONT_NAME, size: 26)
          else
            pdf_doc.font(FONT_NAME, size: 11)
          end
        end
      end
    end
  end
end
