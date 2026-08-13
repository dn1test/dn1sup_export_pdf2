# frozen_string_literal: true

require_relative "page_base"

module DN1Code
  module ExportPdf2
    module Controller
      class DescriptionPage < PageBase
        def render_header
          hdr_box = get_block_box(:description, :desc_header, 0.0, 0.0, 100.0, 7.0)
          return unless hdr_box[:visible]

          scene_name = @scene_item ? @scene_item.name : "Описание и спецификация проекта"
          draw_standard_header(scene_name)
        end

        def render_body
          # 1. Материалы и фурнитура
          mat_box = get_block_box(:description, :desc_materials, 0.0, 9.0, 52.0, 20.0)
          if mat_box[:visible]
            mat_text = @info[:materials].to_s.strip.empty? ? "Спецификация материалов и фурнитуры согласно техническому заданию." : @info[:materials].to_s
            draw_spec_card(mat_box[:x], mat_box[:y], mat_box[:width], mat_box[:height], "МАТЕРИАЛЫ И ФУРНИТУРА", mat_text)
          end

          # 2. Техника и оборудование
          app_box = get_block_box(:description, :desc_appliances, 0.0, 31.0, 52.0, 20.0)
          if app_box[:visible]
            app_text = @info[:appliances].to_s.strip.empty? ? "Встраиваемая и бытовая техника согласно спецификации проекта." : @info[:appliances].to_s
            draw_spec_card(app_box[:x], app_box[:y], app_box[:width], app_box[:height], "ТЕХНИКА И ОБОРУДОВАНИЕ", app_text)
          end

          # 3. Подсветка и электрика
          light_box = get_block_box(:description, :desc_lighting, 0.0, 53.0, 52.0, 20.0)
          if light_box[:visible]
            light_text = @info[:lighting].to_s.strip.empty? ? "Схема подключения и параметры освещения согласно проекту." : @info[:lighting].to_s
            draw_spec_card(light_box[:x], light_box[:y], light_box[:width], light_box[:height], "ПОДСВЕТКА И ЭЛЕКТРИКА", light_text)
          end

          # 4. Пояснительная записка
          note_box = get_block_box(:description, :desc_notes, 0.0, 75.0, 52.0, 20.0)
          if note_box[:visible]
            note_text = @info[:notes].to_s.strip.empty? ? "Монтаж и эксплуатация в соответствии со стандартами качества." : @info[:notes].to_s
            draw_spec_card(note_box[:x], note_box[:y], note_box[:width], note_box[:height], "ПОЯСНИТЕЛЬНАЯ ЗАПИСКА", note_text)
          end

          # 5. Видовой экран / Изображение
          img_box = get_block_box(:description, :desc_image, 55.0, 9.0, 45.0, 86.0)
          if img_box[:visible]
            draw_scene_image(img_box[:x], img_box[:y], img_box[:width], img_box[:height])
          end
        end

        def render_footer
          ft_box = get_block_box(:description, :footer, 0.0, 96.0, 100.0, 4.0)
          return unless ft_box[:visible]

          draw_standard_footer
        end

        def draw_spec_card(x, y, width, height, title, text)
          # Фоновая плашка
          @pdf_doc.fill_color "F8FAFC"
          @pdf_doc.fill_rounded_rectangle [x, y], width, height, 4
          @pdf_doc.stroke_color "E2E8F0"
          @pdf_doc.line_width 1
          @pdf_doc.stroke_rounded_rectangle [x, y], width, height, 4

          # Акцентная вертикальная полоса слева
          @pdf_doc.fill_color @primary_col
          @pdf_doc.fill_rounded_rectangle [x, y], 5, height, 2

          # Заголовок блока
          @pdf_doc.fill_color @primary_col
          Service::FontService.apply_style(@pdf_doc, :heading)
          @pdf_doc.text_box title, at: [x + 14, y - 8], width: width - 24, height: 16, overflow: :shrink_to_fit

          # Разделительная линия
          @pdf_doc.stroke_color "CBD5E1"
          @pdf_doc.line_width 0.8
          @pdf_doc.stroke_horizontal_line x + 14, x + width - 14, at: y - 24

          # Текст описания
          @pdf_doc.fill_color "334155"
          Service::FontService.apply_style(@pdf_doc, :body)
          text_top = y - 30
          text_max_h = height - 36
          @pdf_doc.text_box text, at: [x + 14, text_top], width: width - 28, height: text_max_h, overflow: :shrink_to_fit
        end
      end
    end
  end
end
