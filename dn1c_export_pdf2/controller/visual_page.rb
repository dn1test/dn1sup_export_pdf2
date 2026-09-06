# frozen_string_literal: true

require_relative "page_base"

module DN1Code
  module ExportPdf2
    module Controller
      class VisualPage < PageBase
        def render_header
          hdr_box = get_block_box(:visual, :visual_header, 0.0, 0.0, 100.0, 6.0)
          return unless hdr_box[:visible]

          # Компактный стильный заголовок для страницы визуализации
          scene_name = @scene_item ? @scene_item.name : "Визуализация"
          
          # Название сцены
          @pdf_doc.fill_color @primary_col
          Service::FontService.apply_style(@pdf_doc, :heading)
          @pdf_doc.text_box scene_name.upcase, at: [hdr_box[:x], hdr_box[:y]], width: [hdr_box[:width] * 0.5, 100].max, height: [hdr_box[:height], 16].max, overflow: :shrink_to_fit

          # Название проекта и артикул справа
          @pdf_doc.fill_color @sec_col
          Service::FontService.apply_style(@pdf_doc, :small)
          right_txt = "#{@info[:name_project]}  |  #{@info[:articul]}"
          right_w = [hdr_box[:width] * 0.45, 150].min
          @pdf_doc.text_box right_txt, at: [hdr_box[:x] + hdr_box[:width] - right_w, hdr_box[:y] - 1], width: right_w, align: :right, overflow: :shrink_to_fit
        end

        def render_body
          # Максимизированная область изображения
          img_box = get_block_box(:visual, :visual_image, 0.0, 7.0, 100.0, 88.0)
          if img_box[:visible]
            draw_scene_image(img_box[:x], img_box[:y], img_box[:width], img_box[:height])
          end
        end

        def render_footer
          ft_box = get_block_box(:visual, :footer, 0.0, 96.0, 100.0, 4.0)
          return unless ft_box[:visible]

          draw_standard_footer
        end
      end
    end
  end
end
