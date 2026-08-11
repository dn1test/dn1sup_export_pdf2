# frozen_string_literal: true

module DN1Code
  module ExportPdf2
    module Controller
      class PageBase
        attr_reader :pdf_doc, :project_data, :scene_item, :page_index, :total_pages

        def initialize(pdf_doc, project_data, scene_item, page_index: 1, total_pages: 1, image_path: nil)
          @pdf_doc      = pdf_doc
          @project_data = project_data
          @scene_item   = scene_item
          @page_index   = page_index
          @total_pages  = total_pages
          @image_path   = image_path

          @info         = project_data.project_info
          @settings     = project_data.pdf_settings
          @primary_col  = @settings[:primary_color] || "005EB0"
          @sec_col      = @settings[:secondary_color] || "64748B"
          @stamp_col    = @settings[:stamp_color] || "D32F2F"
        end

        def bounds
          @pdf_doc.bounds
        end

        # Шаблонный метод рендеринга страницы
        def render
          before_render
          render_background
          render_header
          render_body
          render_footer
          render_stamp
          after_render
        end

        protected

        def before_render; end
        def render_background; end
        def render_header; end
        def render_body; end
        def render_footer; end
        def after_render; end

        # Отрисовка стандартного штампа/водяного знака
        def render_stamp
          stamp_type = @settings[:stamp_type].to_s
          return if stamp_type == "none" || stamp_type.empty?

          text1 = case stamp_type
                  when "draft"
                    @settings[:stamp_custom] || "НЕ УТВЕРЖДЕН"
                  when "approved"
                    "В ПРОИЗВОДСТВО"
                  else
                    @settings[:stamp_custom] || "КОНЦЕПТ"
                  end

          text2 = "Проект не является финальным чертежом"

          @pdf_doc.transparent(0.35) do
            @pdf_doc.fill_color @stamp_col
            Service::FontService.apply_style(@pdf_doc, :stamp)
            pos_x = bounds.right - 260
            pos_y = bounds.bottom + 110

            @pdf_doc.text_box text1.upcase, at: [pos_x, pos_y], size: 28, rotate: 25, style: :bold
            @pdf_doc.text_box text2, at: [pos_x - 10, pos_y - 32], size: 10, rotate: 25
          end
        end

        # Стандартный верхний колонтитул для технических страниц
        def draw_standard_header(scene_title = nil)
          title = scene_title || (@scene_item ? @scene_item.name : "")
          project_title = @info[:name_project].to_s
          articul = @info[:articul] ? "АРТ: #{@info[:articul]}" : ""

          @pdf_doc.fill_color @sec_col
          Service::FontService.apply_style(@pdf_doc, :small)
          @pdf_doc.text_box "#{project_title}  |  #{@info[:address]}", at: [bounds.left, bounds.top], width: bounds.width * 0.7, align: :left

          @pdf_doc.text_box articul, at: [bounds.right - 200, bounds.top], width: 200, align: :right

          # Название сцены
          @pdf_doc.fill_color @primary_col
          Service::FontService.apply_style(@pdf_doc, :subtitle)
          @pdf_doc.text_box title, at: [bounds.left, bounds.top - 14], width: bounds.width, align: :left

          # Тонкая разделительная линия
          @pdf_doc.stroke_color "E2E8F0"
          @pdf_doc.line_width 0.8
          @pdf_doc.stroke_horizontal_line bounds.left, bounds.right, at: bounds.top - 38
        end

        # Стандартный нижний колонтитул
        def draw_standard_footer
          @pdf_doc.stroke_color "E2E8F0"
          @pdf_doc.line_width 0.8
          @pdf_doc.stroke_horizontal_line bounds.left, bounds.right, at: bounds.bottom + 22

          @pdf_doc.fill_color @sec_col
          Service::FontService.apply_style(@pdf_doc, :small)

          rev_text = "Ревизия v#{@info[:version]}#r#{@info[:revision]}  •  Дата: #{Time.now.strftime('%d.%m.%Y')}"
          @pdf_doc.text_box rev_text, at: [bounds.left, bounds.bottom + 16], width: bounds.width * 0.6, align: :left

          page_text = "Лист #{@page_index} из #{@total_pages}"
          @pdf_doc.text_box page_text, at: [bounds.right - 200, bounds.bottom + 16], width: 200, align: :right
        end

        # Отрисовка изображения сцены с безопасным позиционированием
        def draw_scene_image(box_x, box_y, box_width, box_height)
          return unless @image_path && File.exist?(@image_path)

          # Рамка для картинки
          @pdf_doc.stroke_color "E2E8F0"
          @pdf_doc.line_width 0.5
          @pdf_doc.rectangle [box_x, box_y], box_width, box_height
          @pdf_doc.stroke

          @pdf_doc.image @image_path, fit: [box_width - 4, box_height - 4], at: [box_x + 2, box_y - 2]
        end
      end
    end
  end
end
