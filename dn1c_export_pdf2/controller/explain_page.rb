# frozen_string_literal: true

require_relative "page_base"

module DN1Code
  module ExportPdf2
    module Controller
      class ExplainPage < PageBase
        def render_header
          hdr_box = get_block_box(:explain, :explain_header, 0.0, 0.0, 100.0, 7.0)
          return unless hdr_box[:visible]

          draw_standard_header("СОДЕРЖАНИЕ И ПОЯСНИТЕЛЬНАЯ ЗАПИСКА")
        end

        def render_body
          # ЛЕВАЯ КОЛОНКА: Содержание проекта
          toc_box = get_block_box(:explain, :explain_toc, 0.0, 9.0, 48.0, 86.0)
          if toc_box[:visible]
            @pdf_doc.fill_color "F8FAFC"
            @pdf_doc.fill_rounded_rectangle [toc_box[:x], toc_box[:y]], toc_box[:width], toc_box[:height], 4
            @pdf_doc.stroke_color "E2E8F0"
            @pdf_doc.line_width 1
            @pdf_doc.stroke_rounded_rectangle [toc_box[:x], toc_box[:y]], toc_box[:width], toc_box[:height], 4

            @pdf_doc.fill_color @primary_col
            Service::FontService.apply_style(@pdf_doc, :heading)
            @pdf_doc.text_box "СОДЕРЖАНИЕ ПРОЕКТА", at: [toc_box[:x] + 15, toc_box[:y] - 12], width: toc_box[:width] - 30

            @pdf_doc.stroke_color "CBD5E1"
            @pdf_doc.stroke_horizontal_line toc_box[:x] + 15, toc_box[:x] + toc_box[:width] - 15, at: toc_box[:y] - 30

            # Вывод списка сцен проекта
            item_y = toc_box[:y] - 42
            enabled_scenes = @project_data.scenes.select(&:enabled)

            enabled_scenes.each_with_index do |sc, idx|
              break if item_y < toc_box[:y] - toc_box[:height] + 25

              # Номер листа
              page_num_str = sprintf("%02d", idx + 1)
              @pdf_doc.fill_color @primary_col
              Service::FontService.apply_style(@pdf_doc, :body)
              @pdf_doc.text_box page_num_str, at: [toc_box[:x] + 15, item_y], width: 25

              # Имя сцены
              @pdf_doc.fill_color "0F172A"
              Service::FontService.apply_style(@pdf_doc, :body)
              @pdf_doc.text_box sc.name, at: [toc_box[:x] + 45, item_y], width: [toc_box[:width] - 160, 60].max, height: 16, overflow: :shrink_to_fit

              # Тип страницы
              type_label = case sc.page_type
                           when :cover then "Титульный лист"
                           when :explain then "Пояснения"
                           when :visual then "Визуализация"
                           else "Общий вид"
                           end

              @pdf_doc.fill_color @sec_col
              Service::FontService.apply_style(@pdf_doc, :small)
              @pdf_doc.text_box type_label, at: [toc_box[:x] + toc_box[:width] - 110, item_y], width: 95, align: :right

              # Пунктир между сценой и типом
              @pdf_doc.stroke_color "E2E8F0"
              @pdf_doc.line_width 0.5
              @pdf_doc.stroke_horizontal_line toc_box[:x] + 15, toc_box[:x] + toc_box[:width] - 15, at: item_y - 8

              item_y -= 22
            end
          end

          # ПРАВАЯ КОЛОНКА: Описание материалов и превью
          specs_box = get_block_box(:explain, :explain_specs, 52.0, 9.0, 48.0, 35.0)
          if specs_box[:visible]
            @pdf_doc.fill_color "F8FAFC"
            @pdf_doc.fill_rounded_rectangle [specs_box[:x], specs_box[:y]], specs_box[:width], specs_box[:height], 4
            @pdf_doc.stroke_color "E2E8F0"
            @pdf_doc.stroke_rounded_rectangle [specs_box[:x], specs_box[:y]], specs_box[:width], specs_box[:height], 4

            @pdf_doc.fill_color @primary_col
            Service::FontService.apply_style(@pdf_doc, :heading)
            @pdf_doc.text_box "СПЕЦИФИКАЦИИ И МАТЕРИАЛЫ", at: [specs_box[:x] + 15, specs_box[:y] - 12], width: specs_box[:width] - 30

            @pdf_doc.stroke_color "CBD5E1"
            @pdf_doc.stroke_horizontal_line specs_box[:x] + 15, specs_box[:x] + specs_box[:width] - 15, at: specs_box[:y] - 30

            @pdf_doc.fill_color "334155"
            Service::FontService.apply_style(@pdf_doc, :body)
            notes_text = @info[:notes].to_s.empty? ? "Специальные требования и спецификации не указаны." : @info[:notes].to_s
            @pdf_doc.text_box notes_text, at: [specs_box[:x] + 15, specs_box[:y] - 42], width: specs_box[:width] - 30, height: [specs_box[:height] - 50, 20].max, overflow: :shrink_to_fit
          end

          # Превью рендер
          img_box = get_block_box(:explain, :explain_image, 52.0, 47.0, 48.0, 48.0)
          if img_box[:visible]
            draw_scene_image(img_box[:x], img_box[:y], img_box[:width], img_box[:height])
          end
        end

        def render_footer
          ft_box = get_block_box(:explain, :footer, 0.0, 96.0, 100.0, 4.0)
          return unless ft_box[:visible]

          draw_standard_footer
        end
      end
    end
  end
end
