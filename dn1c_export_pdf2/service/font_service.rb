# frozen_string_literal: true

module DN1Code
  module ExportPdf2
    module Service
      # Сервис управления типографикой и шрифтовыми стилями PDF документа.
      # Регистрирует кастомный TTF-шрифт DIN Condensed с кириллицей и задает шкалу размеров.
      module FontService
        # Основное имя зарегистрированного шрифтового семейства
        FONT_NAME = "DIN Condensed"

        # Регистрирует семейство шрифтов DIN Condensed в документе Prawn.
        # Если файл шрифта не найден, переключается на стандартный Helvetica.
        # @param pdf_doc [Prawn::Document] целевой документ PDF
        # @return [void]
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
            # Резервный стандартный PDF шрифт при отсутствии файла DIN Condensed
            pdf_doc.font("Helvetica")
          end
        end

        # Применяет предопределенный типографический стиль (шрифт и кегль) к документу PDF
        # @param pdf_doc [Prawn::Document] целевой документ PDF
        # @param style [Symbol] название стиля (:title, :subtitle, :heading, :body, :small, :stamp)
        # @return [void]
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
