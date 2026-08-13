# frozen_string_literal: true

require_relative "page_base"

module DN1Code
  module ExportPdf2
    module Controller
      class CoverPage < PageBase
        def render_header
          # Верхняя акцентная полоса бренда
          bar_box = get_block_box(:cover, :cover_accent_bar, 0.0, 0.0, 100.0, 1.5)
          if bar_box[:visible]
            @pdf_doc.fill_color @primary_col
            @pdf_doc.fill_rectangle [bar_box[:x], bar_box[:y]], bar_box[:width], [bar_box[:height], 4].max
          end

          # Номер проекта / артикул справа
          art_box = get_block_box(:cover, :cover_articul, 65.0, 2.5, 35.0, 4.0)
          if art_box[:visible]
            art_text = @info[:articul].to_s.empty? ? "" : "АРТИКУЛ: #{@info[:articul]}"
            @pdf_doc.fill_color @sec_col
            Service::FontService.apply_style(@pdf_doc, :small)
            @pdf_doc.text_box art_text, at: [art_box[:x], art_box[:y]], width: art_box[:width], height: art_box[:height], align: art_box[:align] || :right
          end

          # Главный заголовок проекта (складывается из места и мебели)
          title_box = get_block_box(:cover, :cover_title, 0.0, 3.5, 65.0, 8.0)
          if title_box[:visible]
            project_title = @info[:name_project].to_s.strip
            if project_title.empty?
              project_title = [@info[:room_name], @info[:furniture_name]].map { |s| s.to_s.strip }.reject(&:empty?).join(" — ")
            end
            project_title = "ПРОЕКТ" if project_title.empty?

            @pdf_doc.fill_color @primary_col
            Service::FontService.apply_style(@pdf_doc, :title)
            @pdf_doc.text_box project_title, at: [title_box[:x], title_box[:y]], width: title_box[:width], height: title_box[:height], align: title_box[:align] || :left, overflow: :shrink_to_fit
          end

          # Подзаголовок: Заказчик и адрес объекта
          sub_box = get_block_box(:cover, :cover_subtitle, 0.0, 11.5, 100.0, 5.0)
          if sub_box[:visible]
            @pdf_doc.fill_color @sec_col
            Service::FontService.apply_style(@pdf_doc, :body)
            sub_parts = []
            sub_parts << "Заказчик: #{@info[:name_customer].to_s.strip}" unless @info[:name_customer].to_s.strip.empty?
            sub_parts << "Адрес объекта: #{@info[:address].to_s.strip}" unless @info[:address].to_s.strip.empty?
            sub_text = sub_parts.join("   •   ")
            @pdf_doc.text_box sub_text, at: [sub_box[:x], sub_box[:y]], width: sub_box[:width], height: sub_box[:height], align: sub_box[:align] || :left, overflow: :shrink_to_fit
          end

          # Разделитель
          div_box = get_block_box(:cover, :cover_divider, 0.0, 16.5, 100.0, 0.5)
          if div_box[:visible]
            @pdf_doc.stroke_color "CBD5E1"
            @pdf_doc.line_width 1
            @pdf_doc.stroke_horizontal_line div_box[:x], div_box[:x] + div_box[:width], at: div_box[:y]
          end
        end

        def render_body
          # Левый блок: Основной рендер / Hero Image
          img_box = get_block_box(:cover, :cover_hero_image, 0.0, 19.0, 56.0, 76.0)
          if img_box[:visible]
            draw_scene_image(img_box[:x], img_box[:y], img_box[:width], img_box[:height])
          end

          # Правый блок: Карточка реквизитов проекта
          card_box = get_block_box(:cover, :cover_project_card, 59.0, 19.0, 41.0, 46.0)
          if card_box[:visible]
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

            # Фоновая плашка карточки
            @pdf_doc.fill_color "F8FAFC"
            @pdf_doc.fill_rounded_rectangle [card_box[:x], card_box[:y]], card_box[:width], card_box[:height], 4
            @pdf_doc.stroke_color "E2E8F0"
            @pdf_doc.line_width 1
            @pdf_doc.stroke_rounded_rectangle [card_box[:x], card_box[:y]], card_box[:width], card_box[:height], 4

            # Заголовок карточки
            @pdf_doc.fill_color @primary_col
            Service::FontService.apply_style(@pdf_doc, :heading)
            @pdf_doc.text_box "ДАННЫЕ ПРОЕКТА", at: [card_box[:x] + 12, card_box[:y] - 10], width: card_box[:width] - 24

            # Поля карточки
            field_y = card_box[:y] - 28
            field_spacing = [16, (card_box[:height] - 36) / [fields.size, 1].max].min
            fields.each do |label, val|
              break if field_y < card_box[:y] - card_box[:height] + 14

              @pdf_doc.fill_color @sec_col
              Service::FontService.apply_style(@pdf_doc, :small)
              lbl_w = [110, card_box[:width] * 0.4].min
              @pdf_doc.text_box label, at: [card_box[:x] + 12, field_y], width: lbl_w

              @pdf_doc.fill_color "0F172A"
              Service::FontService.apply_style(@pdf_doc, :body)
              val_w = card_box[:width] - lbl_w - 24
              @pdf_doc.text_box val, at: [card_box[:x] + lbl_w + 14, field_y + 1], width: val_w, height: 16, overflow: :shrink_to_fit

              field_y -= field_spacing
            end
          end

          # Правый блок: История изменений (Ревизии)
          hist_box = get_block_box(:cover, :cover_history_card, 59.0, 67.0, 41.0, 28.0)
          if hist_box[:visible] && hist_box[:height] > 35
            @pdf_doc.fill_color "F8FAFC"
            @pdf_doc.fill_rounded_rectangle [hist_box[:x], hist_box[:y]], hist_box[:width], hist_box[:height], 4
            @pdf_doc.stroke_color "E2E8F0"
            @pdf_doc.stroke_rounded_rectangle [hist_box[:x], hist_box[:y]], hist_box[:width], hist_box[:height], 4

            @pdf_doc.fill_color @primary_col
            Service::FontService.apply_style(@pdf_doc, :heading)
            @pdf_doc.text_box "ИСТОРИЯ ИЗМЕНЕНИЙ", at: [hist_box[:x] + 12, hist_box[:y] - 10], width: hist_box[:width] - 24

            # Список ревизий (до 5 последних)
            hy = hist_box[:y] - 28
            history_items = @project_data.history.last(5).reverse
            history_items.each do |item|
              break if hy < hist_box[:y] - hist_box[:height] + 16

              date_str = item[:date] || item["date"] || ""
              desc_str = item[:description] || item["description"] || ""

              @pdf_doc.fill_color @primary_col
              Service::FontService.apply_style(@pdf_doc, :small)
              @pdf_doc.text_box date_str, at: [hist_box[:x] + 12, hy], width: 85

              @pdf_doc.fill_color "334155"
              Service::FontService.apply_style(@pdf_doc, :body)
              @pdf_doc.text_box desc_str, at: [hist_box[:x] + 100, hy], width: hist_box[:width] - 112, height: 18, overflow: :shrink_to_fit

              hy -= 18
            end
          end
        end

        def render_footer
          footer_box = get_block_box(:cover, :footer, 0.0, 96.0, 100.0, 4.0)
          return unless footer_box[:visible]

          draw_standard_footer
        end
      end
    end
  end
end
