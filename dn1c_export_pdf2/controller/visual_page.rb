# frozen_string_literal: true

require_relative "page_base"

module DN1Code
  module ExportPdf2
    module Controller
      class VisualPage < PageBase
        def render_header
          # Компактный стильный заголовок для страницы визуализации
          scene_name = @scene_item ? @scene_item.name : "Визуализация"
          
          # Фоновая плашка заголовка
          banner_h = 28
          @pdf_doc.fill_color "F8FAFC"
          @pdf_doc.fill_rounded_rectangle [bounds.left, bounds.top], bounds.width, banner_h, 3
          @pdf_doc.stroke_color "E2E8F0"
          @pdf_doc.line_width 0.8
          @pdf_doc.stroke_rounded_rectangle [bounds.left, bounds.top], bounds.width, banner_h, 3

          # Название сцены
          @pdf_doc.fill_color @primary_col
          Service::FontService.apply_style(@pdf_doc, :heading)
          @pdf_doc.text_box scene_name.upcase, at: [bounds.left + 12, bounds.top - 7], width: bounds.width * 0.5, height: 18

          # Название проекта и артикул справа
          @pdf_doc.fill_color @sec_col
          Service::FontService.apply_style(@pdf_doc, :small)
          right_txt = "#{@info[:name_project]}  |  #{@info[:articul]}"
          @pdf_doc.text_box right_txt, at: [bounds.right - 300, bounds.top - 8], width: 288, align: :right
        end

        def render_body
          # Максимизированная область изображения
          img_top = bounds.top - 36
          img_h   = bounds.height - 68
          draw_scene_image(bounds.left, img_top, bounds.width, img_h)
        end

        def render_footer
          draw_standard_footer
        end
      end
    end
  end
end
