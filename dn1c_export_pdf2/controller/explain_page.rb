# frozen_string_literal: true

require_relative "page_base"

module DN1Code
  module ExportPdf2
    module Controller
      class ExplainPage < PageBase
        def render_header
          draw_standard_header("СОДЕРЖАНИЕ И ПОЯСНИТЕЛЬНАЯ ЗАПИСКА")
        end

        def render_body
          content_top = bounds.top - 50
          content_height = bounds.height - 85

          col_width = (bounds.width - 25) / 2
          left_x    = bounds.left
          right_x   = bounds.left + col_width + 25

          # ЛЕВАЯ КОЛОНКА: Содержание проекта
          @pdf_doc.fill_color "F8FAFC"
          @pdf_doc.fill_rounded_rectangle [left_x, content_top], col_width, content_height, 4
          @pdf_doc.stroke_color "E2E8F0"
          @pdf_doc.line_width 1
          @pdf_doc.stroke_rounded_rectangle [left_x, content_top], col_width, content_height, 4

          @pdf_doc.fill_color @primary_col
          Service::FontService.apply_style(@pdf_doc, :heading)
          @pdf_doc.text_box "СОДЕРЖАНИЕ ПРОЕКТА", at: [left_x + 15, content_top - 12], width: col_width - 30

          @pdf_doc.stroke_color "CBD5E1"
          @pdf_doc.stroke_horizontal_line left_x + 15, left_x + col_width - 15, at: content_top - 30

          # Вывод списка сцен проекта
          item_y = content_top - 42
          enabled_scenes = @project_data.scenes.select(&:enabled)

          enabled_scenes.each_with_index do |sc, idx|
            break if item_y < content_top - content_height + 25

            # Номер листа
            page_num_str = sprintf("%02d", idx + 1)
            @pdf_doc.fill_color @primary_col
            Service::FontService.apply_style(@pdf_doc, :body)
            @pdf_doc.text_box page_num_str, at: [left_x + 15, item_y], width: 25

            # Имя сцены
            @pdf_doc.fill_color "0F172A"
            Service::FontService.apply_style(@pdf_doc, :body)
            @pdf_doc.text_box sc.name, at: [left_x + 45, item_y], width: col_width - 160, height: 16, overflow: :shrink_to_fit

            # Тип страницы
            type_label = case sc.page_type
                         when :cover then "Титульный лист"
                         when :explain then "Пояснения"
                         when :visual then "Визуализация"
                         else "Общий вид"
                         end

            @pdf_doc.fill_color @sec_col
            Service::FontService.apply_style(@pdf_doc, :small)
            @pdf_doc.text_box type_label, at: [left_x + col_width - 110, item_y], width: 95, align: :right

            # Пунктир между сценой и типом
            @pdf_doc.stroke_color "E2E8F0"
            @pdf_doc.line_width 0.5
            @pdf_doc.stroke_horizontal_line left_x + 15, left_x + col_width - 15, at: item_y - 8

            item_y -= 22
          end

          # ПРАВАЯ КОЛОНКА: Описание материалов и превью
          notes_card_height = 140
          @pdf_doc.fill_color "F8FAFC"
          @pdf_doc.fill_rounded_rectangle [right_x, content_top], col_width, notes_card_height, 4
          @pdf_doc.stroke_color "E2E8F0"
          @pdf_doc.stroke_rounded_rectangle [right_x, content_top], col_width, notes_card_height, 4

          @pdf_doc.fill_color @primary_col
          Service::FontService.apply_style(@pdf_doc, :heading)
          @pdf_doc.text_box "СПЕЦИФИКАЦИИ И МАТЕРИАЛЫ", at: [right_x + 15, content_top - 12], width: col_width - 30

          @pdf_doc.stroke_color "CBD5E1"
          @pdf_doc.stroke_horizontal_line right_x + 15, right_x + col_width - 15, at: content_top - 30

          @pdf_doc.fill_color "334155"
          Service::FontService.apply_style(@pdf_doc, :body)
          notes_text = @info[:notes].to_s.empty? ? "Специальные требования и спецификации не указаны." : @info[:notes].to_s
          @pdf_doc.text_box notes_text, at: [right_x + 15, content_top - 42], width: col_width - 30, height: notes_card_height - 50, overflow: :shrink_to_fit

          # Превью рендер под карточкой спецификаций
          img_top = content_top - notes_card_height - 15
          img_h   = content_height - notes_card_height - 15
          draw_scene_image(right_x, img_top, col_width, img_h)
        end

        def render_footer
          draw_standard_footer
        end
      end
    end
  end
end
