# frozen_string_literal: true

module DN1Code
  module ExportPdf2
    module Service
      # Сервис управления типографикой и шрифтовыми стилями PDF документа.
      # Регистрирует кастомный TTF-шрифт DIN Condensed с кириллицей и задает шкалу размеров.
      module FontService
        # Основное имя зарегистрированного шрифтового семейства
        FONT_NAME = "DIN Condensed"

        # Плотный межбуквенный интервал для максимального сжатия ширины шрифта (минимальная ширина)
        CHARACTER_SPACING = -0.25

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

          apply_character_spacing(pdf_doc)
        end

        # Применяет плотный межбуквенный интервал (минимальную ширину шрифта) к операциям вывода текста
        # @param pdf_doc [Prawn::Document]
        def self.apply_character_spacing(pdf_doc)
          return unless pdf_doc.respond_to?(:text_box)
          return if pdf_doc.respond_to?(:_dn1c_condensed_wrapped)

          pdf_doc.define_singleton_method(:_dn1c_condensed_wrapped) { true }

          pdf_doc.singleton_class.class_eval do
            alias_method :_orig_dn1c_text_box, :text_box
            def text_box(string, options = {})
              opts = options.dup
              opts[:character_spacing] = FontService::CHARACTER_SPACING unless opts.key?(:character_spacing)
              _orig_dn1c_text_box(string, opts)
            end

            alias_method :_orig_dn1c_height_of, :height_of
            def height_of(string, options = {})
              opts = options.dup
              opts[:character_spacing] = FontService::CHARACTER_SPACING unless opts.key?(:character_spacing)
              _orig_dn1c_height_of(string, opts)
            end

            if method_defined?(:formatted_text_box)
              alias_method :_orig_dn1c_formatted_text_box, :formatted_text_box
              def formatted_text_box(formatted_text, options = {})
                opts = options.dup
                opts[:character_spacing] = FontService::CHARACTER_SPACING unless opts.key?(:character_spacing)
                _orig_dn1c_formatted_text_box(formatted_text, opts)
              end
            end
          end
        end

        # Применяет предопределенный типографический стиль (шрифт и кегль) к документу PDF
        # @param pdf_doc [Prawn::Document] целевой документ PDF
        # @param style [Symbol] название стиля (:title, :subtitle, :heading, :body, :small, :stamp)
        # @return [void]
        def self.apply_style(pdf_doc, style = :body)
          font_name = (pdf_doc.font_families && pdf_doc.font_families.key?(FONT_NAME)) ? FONT_NAME : "Helvetica"
          case style
          when :title
            pdf_doc.font(font_name, size: 24)
          when :subtitle
            pdf_doc.font(font_name, size: 16)
          when :heading
            pdf_doc.font(font_name, size: 12)
          when :body
            pdf_doc.font(font_name, size: 10)
          when :small
            pdf_doc.font(font_name, size: 8)
          when :stamp
            pdf_doc.font(font_name, size: 26)
          else
            pdf_doc.font(font_name, size: 10)
          end
        end
      end
    end
  end
end
