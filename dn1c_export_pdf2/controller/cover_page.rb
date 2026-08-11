# frozen_string_literal: true

require_relative "page_base"

module DN1Code
  module ExportPdf2
    module Controller
      class CoverPage < PageBase
        def render_header
          # Верхняя акцентная полоса бренда
          @pdf_doc.fill_color @primary_col
          @pdf_doc.fill_rectangle [bounds.left, bounds.top], bounds.width, 6

          # Номер проекта / артикул справа
          art_text = @info[:articul].to_s.empty? ? "" : "АРТИКУЛ: #{@info[:articul]}"
          @pdf_doc.fill_color @sec_col
          Service::FontService.apply_style(@pdf_doc, :small)
          @pdf_doc.text_box art_text, at: [bounds.right - 250, bounds.top - 14], width: 250, align: :right

          # Главный заголовок проекта (складывается из места и мебели)
          project_title = @info[:name_project].to_s.strip
          if project_title.empty?
            project_title = [@info[:room_name], @info[:furniture_name]].map { |s| s.to_s.strip }.reject(&:empty?).join(" — ")
          end
          project_title = "ПРОЕКТ" if project_title.empty?

          @pdf_doc.fill_color @primary_col
          Service::FontService.apply_style(@pdf_doc, :title)
          @pdf_doc.text_box project_title, at: [bounds.left, bounds.top - 26], width: bounds.width, height: 40, overflow: :shrink_to_fit

          # Подзаголовок: Заказчик и адрес объекта
          @pdf_doc.fill_color @sec_col
          Service::FontService.apply_style(@pdf_doc, :body)
          sub_parts = []
          sub_parts << "Заказчик: #{@info[:name_customer].to_s.strip}" unless @info[:name_customer].to_s.strip.empty?
          sub_parts << "Адрес объекта: #{@info[:address].to_s.strip}" unless @info[:address].to_s.strip.empty?
          sub_text = sub_parts.join("   •   ")
          @pdf_doc.text_box sub_text, at: [bounds.left, bounds.top - 68], width: bounds.width, height: 25, overflow: :shrink_to_fit

          # Разделитель
          @pdf_doc.stroke_color "CBD5E1"
          @pdf_doc.line_width 1
          @pdf_doc.stroke_horizontal_line bounds.left, bounds.right, at: bounds.top - 95
        end

        def render_body
          content_top = bounds.top - 110
          left_width  = bounds.width * 0.56
          right_width = bounds.width * 0.40
          right_left  = bounds.left + left_width + (bounds.width * 0.04)

          # Левый блок: Основной рендер / Hero Image
          img_height = bounds.height - 180
          draw_scene_image(bounds.left, content_top, left_width, img_height)

          # Правый блок: Карточка реквизитов проекта
          card_y = content_top

          fields = []
          fields << ["Помещение / Зона:", @info[:room_name].to_s] unless @info[:room_name].to_s.strip.empty?
          fields << ["Изделие / Мебель:", @info[:furniture_name].to_s] unless @info[:furniture_name].to_s.strip.empty?
          fields << ["Адрес объекта:", @info[:address].to_s] unless @info[:address].to_s.strip.empty?
          fields << ["Заказчик:", @info[:name_customer].to_s] unless @info[:name_customer].to_s.strip.empty?
          contacts = [@info[:phone], @info[:email]].map { |s| s.to_s.strip }.reject(&:empty?).join(" | ")
          fields << ["Контакты:", contacts] unless contacts.empty?
          fields << ["Статус:", @info[:status].to_s]
          fields << ["Версия / Ревизия:", "v#{@info[:version]} #r#{@info[:revision]}"]
          fields << ["Дата проекта:", Time.now.strftime("%d.%m.%Y")]

          card_height = [140, 32 + (fields.size * 18)].max

          # Фоновая плашка карточки
          @pdf_doc.fill_color "F8FAFC"
          @pdf_doc.fill_rounded_rectangle [right_left, card_y], right_width, card_height, 4
          @pdf_doc.stroke_color "E2E8F0"
          @pdf_doc.line_width 1
          @pdf_doc.stroke_rounded_rectangle [right_left, card_y], right_width, card_height, 4

          # Заголовок карточки
          @pdf_doc.fill_color @primary_col
          Service::FontService.apply_style(@pdf_doc, :heading)
          @pdf_doc.text_box "ДАННЫЕ ПРОЕКТА", at: [right_left + 12, card_y - 10], width: right_width - 24

          # Поля карточки
          field_y = card_y - 30
          fields.each do |label, val|
            @pdf_doc.fill_color @sec_col
            Service::FontService.apply_style(@pdf_doc, :small)
            @pdf_doc.text_box label, at: [right_left + 12, field_y], width: 110

            @pdf_doc.fill_color "0F172A"
            Service::FontService.apply_style(@pdf_doc, :body)
            @pdf_doc.text_box val, at: [right_left + 125, field_y + 1], width: right_width - 137, height: 16, overflow: :shrink_to_fit

            field_y -= 18
          end

          # Правый блок: История изменений (Ревизии)
          hist_top = card_y - card_height - 12
          hist_height = img_height - card_height - 12
          return if hist_height < 45

          @pdf_doc.fill_color "F8FAFC"
          @pdf_doc.fill_rounded_rectangle [right_left, hist_top], right_width, hist_height, 4
          @pdf_doc.stroke_color "E2E8F0"
          @pdf_doc.stroke_rounded_rectangle [right_left, hist_top], right_width, hist_height, 4

          @pdf_doc.fill_color @primary_col
          Service::FontService.apply_style(@pdf_doc, :heading)
          @pdf_doc.text_box "ИСТОРИЯ ИЗМЕНЕНИЙ", at: [right_left + 12, hist_top - 10], width: right_width - 24

          # Список ревизий (до 5 последних)
          hy = hist_top - 28
          history_items = @project_data.history.last(5).reverse
          history_items.each do |item|
            break if hy < hist_top - hist_height + 18

            date_str = item[:date] || item["date"] || ""
            desc_str = item[:description] || item["description"] || ""

            @pdf_doc.fill_color @primary_col
            Service::FontService.apply_style(@pdf_doc, :small)
            @pdf_doc.text_box date_str, at: [right_left + 12, hy], width: 85

            @pdf_doc.fill_color "334155"
            Service::FontService.apply_style(@pdf_doc, :body)
            @pdf_doc.text_box desc_str, at: [right_left + 100, hy], width: right_width - 112, height: 18, overflow: :shrink_to_fit

            hy -= 20
          end
        end

        def render_footer
          draw_standard_footer
        end
      end
    end
  end
end
