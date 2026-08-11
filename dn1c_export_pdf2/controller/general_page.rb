# frozen_string_literal: true

require_relative "page_base"

module DN1Code
  module ExportPdf2
    module Controller
      class GeneralPage < PageBase
        def render_header
          scene_name = @scene_item ? @scene_item.name : "Вид модели"
          draw_standard_header(scene_name)
        end

        def render_body
          content_top = bounds.top - 46
          desc_text = @scene_item ? @scene_item.description.to_s.strip : ""

          if desc_text.empty?
            # Если описания нет, используем всю высоту под чертеж/рендер
            img_h = bounds.height - 76
            draw_scene_image(bounds.left, content_top, bounds.width, img_h)
          else
            # Если есть описание сцены, делим область на изображение и карточку описания
            desc_card_h = 45
            img_h = bounds.height - 76 - desc_card_h - 10

            draw_scene_image(bounds.left, content_top, bounds.width, img_h)

            card_top = content_top - img_h - 10
            @pdf_doc.fill_color "F8FAFC"
            @pdf_doc.fill_rounded_rectangle [bounds.left, card_top], bounds.width, desc_card_h, 3
            @pdf_doc.stroke_color "E2E8F0"
            @pdf_doc.line_width 0.8
            @pdf_doc.stroke_rounded_rectangle [bounds.left, card_top], bounds.width, desc_card_h, 3

            @pdf_doc.fill_color @primary_col
            Service::FontService.apply_style(@pdf_doc, :small)
            @pdf_doc.text_box "ПРИМЕЧАНИЕ К ВИДУ:", at: [bounds.left + 10, card_top - 8], width: 150

            @pdf_doc.fill_color "334155"
            Service::FontService.apply_style(@pdf_doc, :body)
            @pdf_doc.text_box desc_text, at: [bounds.left + 130, card_top - 8], width: bounds.width - 145, height: desc_card_h - 14, overflow: :shrink_to_fit
          end
        end

        def render_footer
          draw_standard_footer
        end
      end
    end
  end
end
