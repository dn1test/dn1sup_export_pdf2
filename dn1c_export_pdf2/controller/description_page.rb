# frozen_string_literal: true

require_relative "page_base"

module DN1Code
  module ExportPdf2
    module Controller
      class DescriptionPage < PageBase
        def render_header
          scene_name = @scene_item ? @scene_item.name : "Описание и спецификация проекта"
          draw_standard_header(scene_name)
        end

        def render_body
          content_top = bounds.top - 50
          content_height = bounds.height - 85

          # Проверка наличия изображения сцены
          has_image = @image_path && File.exist?(@image_path)

          if @settings[:page_layout].to_s == "portrait"
            render_portrait_layout(content_top, content_height, has_image)
          else
            render_landscape_layout(content_top, content_height, has_image)
          end
        end

        def render_footer
          draw_standard_footer
        end

        private

        def render_landscape_layout(content_top, content_height, has_image)
          if has_image
            col_width = (bounds.width - 20) * 0.52
            img_width = bounds.width - col_width - 20
            left_x    = bounds.left
            right_x   = bounds.left + col_width + 20

            render_stacked_cards(left_x, content_top, col_width, content_height)
            draw_scene_image(right_x, content_top, img_width, content_height)
          else
            render_grid_cards(content_top, bounds.width, content_height)
          end
        end

        def render_portrait_layout(content_top, content_height, has_image)
          if has_image
            cards_height = (content_height * 0.58).round
            img_height   = content_height - cards_height - 12

            render_stacked_cards(bounds.left, content_top, bounds.width, cards_height)
            img_top = content_top - cards_height - 12
            draw_scene_image(bounds.left, img_top, bounds.width, img_height)
          else
            render_stacked_cards(bounds.left, content_top, bounds.width, content_height)
          end
        end

        def spec_blocks
          [
            {
              title: "МАТЕРИАЛЫ И ФУРНИТУРА",
              text:  @info[:materials].to_s.strip.empty? ? "Спецификация материалов и фурнитуры согласно техническому заданию." : @info[:materials].to_s
            },
            {
              title: "ТЕХНИКА И ОБОРУДОВАНИЕ",
              text:  @info[:appliances].to_s.strip.empty? ? "Встраиваемая и бытовая техника согласно спецификации проекта." : @info[:appliances].to_s
            },
            {
              title: "ПОДСВЕТКА И ЭЛЕКТРИКА",
              text:  @info[:lighting].to_s.strip.empty? ? "Схема подключения и параметры освещения согласно проекту." : @info[:lighting].to_s
            },
            {
              title: "ПОЯСНИТЕЛЬНАЯ ЗАПИСКА",
              text:  @info[:notes].to_s.strip.empty? ? "Монтаж и эксплуатация в соответствии со стандартами качества." : @info[:notes].to_s
            }
          ]
        end

        def render_stacked_cards(box_x, box_top, box_width, total_height)
          blocks = spec_blocks
          card_gap = 7
          card_height = (total_height - (card_gap * (blocks.size - 1))) / blocks.size.to_f

          current_y = box_top
          blocks.each do |blk|
            draw_spec_card(box_x, current_y, box_width, card_height, blk[:title], blk[:text])
            current_y -= (card_height + card_gap)
          end
        end

        def render_grid_cards(box_top, total_width, total_height)
          blocks = spec_blocks
          col_gap = 14
          row_gap = 10
          card_w  = (total_width - col_gap) / 2.0
          card_h  = (total_height - row_gap) / 2.0

          # Row 1
          draw_spec_card(bounds.left, box_top, card_w, card_h, blocks[0][:title], blocks[0][:text])
          draw_spec_card(bounds.left + card_w + col_gap, box_top, card_w, card_h, blocks[1][:title], blocks[1][:text])

          # Row 2
          row2_y = box_top - card_h - row_gap
          draw_spec_card(bounds.left, row2_y, card_w, card_h, blocks[2][:title], blocks[2][:text])
          draw_spec_card(bounds.left + card_w + col_gap, row2_y, card_w, card_h, blocks[3][:title], blocks[3][:text])
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
