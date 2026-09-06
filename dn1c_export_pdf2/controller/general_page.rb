# frozen_string_literal: true

require_relative "page_base"

module DN1Code
  module ExportPdf2
    module Controller
      class GeneralPage < PageBase
        def render_header
          hdr_box = get_block_box(:general, :general_header, 0.0, 0.0, 100.0, 7.0)
          return unless hdr_box[:visible]

          scene_name = @scene_item ? @scene_item.name : "Вид модели"
          draw_standard_header(scene_name)
        end

        def render_body
          # Изображение
          img_box = get_block_box(:general, :general_image, 0.0, 9.0, 100.0, 73.0)
          if img_box[:visible]
            draw_scene_image(img_box[:x], img_box[:y], img_box[:width], img_box[:height])
          end

          # Карточка примечания к виду
          note_box = get_block_box(:general, :general_note, 0.0, 84.0, 100.0, 11.0)
          desc_text = @scene_item ? @scene_item.description.to_s.strip : ""

          if note_box[:visible] && (!desc_text.empty? || note_box[:height] > 20)
            @pdf_doc.fill_color @primary_col
            Service::FontService.apply_style(@pdf_doc, :small)
            lbl_w = [150, note_box[:width] * 0.3].min
            @pdf_doc.text_box "ПРИМЕЧАНИЕ К ВИДУ:", at: [note_box[:x], note_box[:y]], width: lbl_w

            @pdf_doc.fill_color "334155"
            Service::FontService.apply_style(@pdf_doc, :body)
            shown_text = desc_text.empty? ? "—" : desc_text
            @pdf_doc.text_box shown_text, at: [note_box[:x] + lbl_w + 10, note_box[:y]], width: note_box[:width] - lbl_w - 10, height: note_box[:height], overflow: :shrink_to_fit
          end
        end

        def render_footer
          ft_box = get_block_box(:general, :footer, 0.0, 96.0, 100.0, 4.0)
          return unless ft_box[:visible]

          draw_standard_footer
        end
      end
    end
  end
end
