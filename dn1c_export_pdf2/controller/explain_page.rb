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
            enabled_scenes = @project_data.scenes.select { |s| s.enabled && s.page_type.to_s != "skip" }
            total_count = (@total_pages && @total_pages.to_i > 0) ? @total_pages.to_i : enabled_scenes.size

            @pdf_doc.fill_color @primary_col
            Service::FontService.apply_style(@pdf_doc, :heading)
            @pdf_doc.text_box "СОДЕРЖАНИЕ ПРОЕКТА", at: [toc_box[:x], toc_box[:y]], width: [toc_box[:width] - 140, 80].max

            @pdf_doc.fill_color @sec_col
            Service::FontService.apply_style(@pdf_doc, :small)
            @pdf_doc.text_box "Всего страниц: #{total_count}", at: [toc_box[:x] + toc_box[:width] - 130, toc_box[:y] - 2], width: 130, align: :right

            @pdf_doc.stroke_color "CBD5E1"
            @pdf_doc.line_width 0.8
            @pdf_doc.stroke_horizontal_line toc_box[:x], toc_box[:x] + toc_box[:width], at: toc_box[:y] - 18

            # Вывод списка сцен проекта
            item_y = toc_box[:y] - 28

            enabled_scenes.each_with_index do |sc, idx|
              break if item_y < toc_box[:y] - toc_box[:height] + 25

              # Номер листа
              page_num_str = sprintf("%02d", idx + 1)
              @pdf_doc.fill_color @primary_col
              Service::FontService.apply_style(@pdf_doc, :body)
              @pdf_doc.text_box page_num_str, at: [toc_box[:x], item_y], width: 25

              # Имя сцены
              @pdf_doc.fill_color "0F172A"
              Service::FontService.apply_style(@pdf_doc, :body)
              @pdf_doc.text_box sc.name, at: [toc_box[:x] + 30, item_y], width: [toc_box[:width] - 140, 60].max, height: 16, overflow: :shrink_to_fit

              # Тип страницы
              type_label = case sc.page_type
                           when :cover then "Титульный лист"
                           when :explain then "Пояснения"
                           when :visual then "Визуализация"
                           else "Общий вид"
                           end

              @pdf_doc.fill_color @sec_col
              Service::FontService.apply_style(@pdf_doc, :small)
              @pdf_doc.text_box type_label, at: [toc_box[:x] + toc_box[:width] - 100, item_y], width: 95, align: :right

              # Пунктир между сценой и типом
              @pdf_doc.stroke_color "E2E8F0"
              @pdf_doc.line_width 0.5
              @pdf_doc.stroke_horizontal_line toc_box[:x], toc_box[:x] + toc_box[:width], at: item_y - 8

              item_y -= 22
            end
          end

          # ПРАВАЯ КОЛОНКА: Описание материалов и превью
          specs_box = get_block_box(:explain, :explain_specs, 52.0, 9.0, 48.0, 35.0)
          if specs_box[:visible]
            @pdf_doc.fill_color @primary_col
            Service::FontService.apply_style(@pdf_doc, :heading)
            @pdf_doc.text_box "СПЕЦИФИКАЦИИ И МАТЕРИАЛЫ", at: [specs_box[:x], specs_box[:y]], width: specs_box[:width]

            @pdf_doc.stroke_color "CBD5E1"
            @pdf_doc.line_width 0.8
            @pdf_doc.stroke_horizontal_line specs_box[:x], specs_box[:x] + specs_box[:width], at: specs_box[:y] - 18

            @pdf_doc.fill_color "334155"
            Service::FontService.apply_style(@pdf_doc, :body)
            notes_text = @info[:notes].to_s.empty? ? "Специальные требования и спецификации не указаны." : @info[:notes].to_s
            @pdf_doc.text_box notes_text, at: [specs_box[:x], specs_box[:y] - 28], width: specs_box[:width], height: [specs_box[:height] - 32, 20].max, overflow: :shrink_to_fit
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
