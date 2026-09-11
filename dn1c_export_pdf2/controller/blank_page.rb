# frozen_string_literal: true

require_relative "page_base"

module DN1Code
  module ExportPdf2
    module Controller
      # Контроллер для чистой страницы без оформления/шаблона (Blank).
      # Отрисовывает только чистое изображение сцены во всю страницу (или область модульных слотов).
      # Полностью исключает верхние колонтитулы, нижние штампы и текстовые блоки.
      class BlankPage < PageBase
        def render_header
          # Без заголовка
        end

        def render_body
          # Полноразмерное чистое изображение сцены
          img_box = get_block_box(:blank, :image_4_3, 0.0, 0.0, 100.0, 100.0)
          if img_box[:visible]
            draw_scene_image(img_box[:x], img_box[:y], img_box[:width], img_box[:height])
          end
        end

        def render_footer
          # Без подвала
        end

        def render_stamp
          # На чистой странице водяные знаки и штампы не отображаются
        end
      end
    end
  end
end
