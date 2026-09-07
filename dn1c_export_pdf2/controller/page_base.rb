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
          @workflow     = (project_data.respond_to?(:workflow) ? project_data.workflow : nil) || {}
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
          if has_modular_slots?
            render_modular_page
          else
            render_header
            render_body
            render_footer
          end
          render_stamp
          after_render
        end

        # Определение типа текущей страницы
        def current_page_type
          case self.class.name.split("::").last
          when "CoverPage" then :cover
          when "DescriptionPage" then :description
          when "ExplainPage" then :explain
          when "GeneralPage" then :general
          when "VisualPage" then :visual
          else
            (@scene_item ? @scene_item.page_type.to_sym : :cover) rescue :cover
          end
        end

        # Проверка, сконфигурирован ли макет через систему фиксированных слотов
        def has_modular_slots?(pt = current_page_type)
          custom = @settings[:custom_layouts] || {}
          page_cfg = custom[pt.to_sym] || custom[pt.to_s] || {}
          page_cfg.key?(:image_4_3) || page_cfg.key?("image_4_3") ||
            page_cfg.key?(:slot_1) || page_cfg.key?("slot_1") ||
            page_cfg.key?(:header) || page_cfg.key?("header")
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
        # Отрисовка изображения сцены с безопасным позиционированием (без рамок)
        def draw_scene_image(box_x, box_y, box_width, box_height)
          return unless @image_path && File.exist?(@image_path)

          @pdf_doc.image @image_path, fit: [box_width, box_height], at: [box_x, box_y]
        end

        # Получение настроек блока из пользовательской конфигурации
        def get_block_config(page_type, block_id)
          custom = @settings[:custom_layouts] || {}
          pt_sym = page_type.to_sym rescue page_type
          pt_str = page_type.to_s
          blk_sym = block_id.to_sym rescue block_id
          blk_str = block_id.to_s

          page_cfg = custom[pt_sym] || custom[pt_str] || {}
          page_cfg[blk_sym] || page_cfg[blk_str] || {}
        end

        # Проверка видимости блока
        def block_visible?(page_type, block_id)
          cfg = get_block_config(page_type, block_id)
          return true if cfg.empty?
          return false if cfg[:visible] == false || cfg["visible"] == false

          true
        end

        # Расчет абсолютных координат блока в точках Prawn [x, y, width, height]
        def get_block_box(page_type, block_id, def_x, def_y, def_w, def_h)
          cfg = get_block_config(page_type, block_id)

          x_pct = (cfg[:x] || cfg["x"] || def_x).to_f
          y_pct = (cfg[:y] || cfg["y"] || def_y).to_f
          w_pct = (cfg[:w] || cfg["w"] || def_w).to_f
          h_pct = (cfg[:h] || cfg["h"] || def_h).to_f

          # Высота заголовка задана жестко 30%, от верхнего края листа (y = 0.0), не регулируется
          if block_id.to_s == "header"
            y_pct = 0.0
            h_pct = 30.0
          end

          # Подвал страницы всегда привязан к нижнему краю листа (y + h = 100.0%)
          if block_id.to_s == "footer"
            h_pct = 4.0 if h_pct <= 0.0
            y_pct = 100.0 - h_pct
          end

          visible = cfg.key?(:visible) ? cfg[:visible] : (cfg.key?("visible") ? cfg["visible"] : true)
          align = (cfg[:align] || cfg["align"] || "left").to_s.to_sym
          valign = (cfg[:valign] || cfg["valign"] || (block_id == :footer ? "bottom" : "top")).to_s.to_sym

          x = bounds.left + (bounds.width * (x_pct / 100.0))
          y = bounds.top - (bounds.height * (y_pct / 100.0))
          width = bounds.width * (w_pct / 100.0)
          height = bounds.height * (h_pct / 100.0)

          {
            x:       x,
            y:       y,
            width:   width,
            height:  height,
            visible: visible,
            align:   align,
            valign:  valign
          }
        end

        # Полный рендеринг страницы по фиксированной 7-зонной сетке слотов
        def render_modular_page(pt = current_page_type)
          # 1. Изображение чертежа/модели в пропорциях (3:2, 4:3, 16:9) и масштабом (60%-100%) ниже всего текста
          if block_visible?(pt, :image_4_3)
            img_cfg = get_block_config(pt, :image_4_3) || {}
            ratio_str = (img_cfg[:aspect_ratio] || img_cfg["aspect_ratio"] || "4:3").to_s.strip
            target_ratio = case ratio_str
                           when "3:2"  then 3.0 / 2.0
                           when "16:9" then 16.0 / 9.0
                           else 4.0 / 3.0 # "4:3"
                           end

            raw_scale = (img_cfg[:scale_pct] || img_cfg["scale_pct"] || 100).to_f
            raw_scale = 100.0 if raw_scale <= 0.0 || raw_scale > 100.0
            scale_factor = raw_scale / 100.0

            page_w = bounds.width
            page_h = bounds.height

            # Доступная область под картинку с учетом процента размещения
            avail_w = page_w * scale_factor
            avail_h = page_h * scale_factor

            cur_ratio = avail_w / avail_h
            if cur_ratio > target_ratio
              img_h = avail_h
              img_w = avail_h * target_ratio
            else
              img_w = avail_w
              img_h = avail_w / target_ratio
            end

            # Центрирование картинки на странице
            img_x = bounds.left + ((page_w - img_w) / 2.0)
            img_y = bounds.top - ((page_h - img_h) / 2.0)

            draw_scene_image(img_x, img_y, img_w, img_h)
          end

          # 2. Верхний заголовок (Header)
          if block_visible?(pt, :header)
            hdr_box = get_block_box(pt, :header, 0.0, 0.0, 100.0, 30.0)
            render_modular_header(pt, hdr_box)
          end

          # 3. 4 информационных слота поверх картинки (Средний блок)
          slot_coords = {
            slot_1: [0.0, 0.0, 25.0, 58.0],
            slot_2: [0.0, 58.0, 25.0, 36.0],
            slot_3: [75.0, 0.0, 25.0, 58.0],
            slot_4: [75.0, 58.0, 25.0, 36.0]
          }

          s1_vis = block_visible?(pt, :slot_1)
          s1_cfg = s1_vis ? get_block_config(pt, :slot_1) : nil
          s1_lines = s1_cfg ? (s1_cfg[:lines] || s1_cfg["lines"]) : nil
          handled_slots = []

          s1_content = s1_cfg ? (s1_cfg[:content] || s1_cfg["content"]).to_s : ""
          is_info_lines = s1_content == "info_lines" || (s1_content != "custom_text" && s1_content != "project_card" && s1_content != "customer_card" && s1_content != "workflow_status" && s1_content != "history_table")

          if s1_vis && s1_cfg && s1_lines.is_a?(Array) && !s1_lines.empty? && is_info_lines
            handled_slots = [:slot_1, :slot_2, :slot_3, :slot_4]
            line_aligns = s1_cfg[:line_aligns] || s1_cfg["line_aligns"] || {}
            line_valigns = s1_cfg[:line_valigns] || s1_cfg["line_valigns"] || {}

            s1_w = (s1_cfg[:w] || s1_cfg["w"] || 25.0).to_f
            s3_cfg = get_block_config(pt, :slot_3)
            s3_w = (s3_cfg && (s3_cfg[:w] || s3_cfg["w"])) ? (s3_cfg[:w] || s3_cfg["w"]).to_f : 25.0
            s3_x = 100.0 - s3_w

            zones = {
              left_top:     { lines: [], align: "left",  valign: :top,    target_slot: :slot_1 },
              left_center:  { lines: [], align: "left",  valign: :center, target_slot: :slot_1_center },
              left_bottom:  { lines: [], align: "left",  valign: :bottom, target_slot: :slot_2 },
              right_top:    { lines: [], align: "right", valign: :top,    target_slot: :slot_3 },
              right_center: { lines: [], align: "right", valign: :center, target_slot: :slot_3_center },
              right_bottom: { lines: [], align: "right", valign: :bottom, target_slot: :slot_4 }
            }

            s1_lines.each do |k|
              k_str = k.to_s
              k_sym = k.to_sym rescue nil
              side = (line_aligns[k_str] || (k_sym && line_aligns[k_sym]) || s1_cfg[:align] || "left").to_s == "right" ? :right : :left
              raw_v = (line_valigns[k_str] || (k_sym && line_valigns[k_sym]) || s1_cfg[:valign] || "top").to_s.downcase
              vpos = case raw_v
                     when "bottom" then :bottom
                     when "center", "middle" then :center
                     else :top
                     end

              zone_key = "#{side}_#{vpos}".to_sym
              zones[zone_key][:lines] << k if zones[zone_key]
            end

            opacity = (s1_cfg[:opacity] || s1_cfg["opacity"] || 0.90).to_f

            # Расчет непересекающихся координат для зон каждого столбца (left/right)
            col_boxes = {}
            [:left, :right].each do |side|
              col_x = (side == :right) ? s3_x : 0.0
              col_w = (side == :right) ? s3_w : s1_w

              has_top = !zones[:"#{side}_top"][:lines].empty?
              has_mid = !zones[:"#{side}_center"][:lines].empty?
              has_bot = !zones[:"#{side}_bottom"][:lines].empty?

              if has_top && has_mid && has_bot
                col_boxes[:"#{side}_top"]    = [col_x, 0.0,  col_w, 30.0]
                col_boxes[:"#{side}_center"] = [col_x, 30.0, col_w, 34.0]
                col_boxes[:"#{side}_bottom"] = [col_x, 64.0, col_w, 30.0]
              elsif has_top && has_mid && !has_bot
                col_boxes[:"#{side}_top"]    = [col_x, 0.0,  col_w, 36.0]
                col_boxes[:"#{side}_center"] = [col_x, 36.0, col_w, 58.0]
              elsif !has_top && has_mid && has_bot
                col_boxes[:"#{side}_center"] = [col_x, 0.0,  col_w, 58.0]
                col_boxes[:"#{side}_bottom"] = [col_x, 58.0, col_w, 36.0]
              elsif !has_top && has_mid && !has_bot
                col_boxes[:"#{side}_center"] = [col_x, 0.0,  col_w, 94.0]
              elsif has_top && !has_mid && has_bot
                col_boxes[:"#{side}_top"]    = [col_x, 0.0,  col_w, 58.0]
                col_boxes[:"#{side}_bottom"] = [col_x, 58.0, col_w, 36.0]
              elsif has_top && !has_mid && !has_bot
                col_boxes[:"#{side}_top"]    = [col_x, 0.0,  col_w, 94.0]
              elsif !has_top && !has_mid && has_bot
                col_boxes[:"#{side}_bottom"] = [col_x, 0.0,  col_w, 94.0]
              end
            end

            zones.each do |zone_key, z_data|
              q_lines = z_data[:lines]
              next if q_lines.empty?

              target_slot = z_data[:target_slot]
              coords = col_boxes[zone_key] || [0.0, 0.0, 25.0, 58.0]
              bx = bounds.left + (bounds.width * (coords[0] / 100.0))
              by = bounds.top - (bounds.height * (coords[1] / 100.0))
              bw = bounds.width * (coords[2] / 100.0)
              bh = bounds.height * (coords[3] / 100.0)

              slot_box = {
                x: bx,
                y: by,
                width: bw,
                height: bh,
                visible: true,
                align: z_data[:align],
                valign: z_data[:valign]
              }


              q_cfg = s1_cfg.dup
              q_cfg[:content] = "info_lines"
              q_cfg[:lines] = q_lines
              q_cfg[:align] = z_data[:align]
              q_cfg[:valign] = z_data[:valign]

              render_modular_slot_card(slot_box, "info_lines", q_cfg, opacity, target_slot)
            end
          end

          # Отрисовка остальных слотов, если они видимы и не были обработаны
          slot_coords.each do |slot_id, defs|
            next if handled_slots.include?(slot_id)
            next unless block_visible?(pt, slot_id)

            cfg = get_block_config(pt, slot_id)
            lines = cfg[:lines] || cfg["lines"]
            content = (cfg[:content] || cfg["content"]).to_s
            content = "info_lines" if (content.empty? || content == "none") && lines.is_a?(Array) && !lines.empty?
            next if content.empty? || content == "none"

            slot_box = get_block_box(pt, slot_id, defs[0], defs[1], defs[2], defs[3])
            opacity = (cfg[:opacity] || cfg["opacity"] || 0.90).to_f
            render_modular_slot_card(slot_box, content, cfg, opacity, slot_id)
          end

          # 4. Нижний колонтитул (Footer)
          if block_visible?(pt, :footer)
            ftr_box = get_block_box(pt, :footer, 0.0, 94.0, 100.0, 6.0)
            render_modular_footer(pt, ftr_box)
          end
        end

        def render_modular_header(pt, hdr_box)
          cfg = get_block_config(pt, :header)
          content = (cfg[:content] || cfg["content"] || "header_title").to_s
          align = (cfg[:align] || cfg["align"] || "center").to_s.to_sym
          valign = (cfg[:valign] || cfg["valign"] || "top").to_s.to_sym
          font_size = (cfg[:font_size] || cfg["font_size"] || 11.0).to_f
          lines = cfg[:lines] || cfg["lines"]
          if lines.nil?
            lines = ["furniture_name", "place_address", "customer_or_company", "scene_name", "scene_description"]
          end
          return if lines.is_a?(Array) && lines.empty?

          if content == "custom_text"
            txt = (cfg[:custom_text] || cfg["custom_text"] || "").to_s
            @pdf_doc.fill_color "0F172A"
            Service::FontService.apply_style(@pdf_doc, :bold)
            @pdf_doc.text_box txt, at: [hdr_box[:x], hdr_box[:y]], width: hdr_box[:width], height: hdr_box[:height], align: :center, valign: valign, size: font_size, overflow: :shrink_to_fit
            return
          end

          # Определение строк заголовка согласно эскизу:
          # 1. Название мебели
          # 2. Место установки | Адрес установки
          # 3. Имя заказчика или Название компании
          furn = (@info[:furniture_name] || @info[:name_product] || @info[:name_project]).to_s.strip
          furn = "ПРОЕКТ МЕБЕЛИ" if furn.empty?

          room = (@info[:room_name] || @info[:name_place]).to_s.strip
          addr = (@info[:address] || @info[:adress]).to_s.strip
          place_addr = [room, addr].reject(&:empty?).join(" | ")
          place_addr = "Место установки | Адрес не указан" if place_addr.empty?

          cust = (@info[:name_customer] || @info[:customer]).to_s.strip
          comp = (@info[:company] || @info[:name_company]).to_s.strip
          cust_comp = [cust, comp].reject(&:empty?).join(" | ")
          cust_comp = "Заказчик не указан" if cust_comp.empty?

          line_rows = cfg[:line_rows] || cfg["line_rows"] || {}
          line_font_sizes = cfg[:line_font_sizes] || cfg["line_font_sizes"] || {}
          line_colors = cfg[:line_colors] || cfg["line_colors"] || {}

          resolve_header_item = lambda do |k|
            case k.to_s
            when "furniture_name"
              furn
            when "place_address"
              place_addr
            when "customer_or_company"
              cust_comp
            when "scene_name", "name", "name_scene"
              s_name = ""
              if @scene_item
                if @scene_item.respond_to?(:scene_ref) && @scene_item.scene_ref && @scene_item.scene_ref.respond_to?(:name) && !@scene_item.scene_ref.name.to_s.strip.empty?
                  s_name = @scene_item.scene_ref.name.to_s.strip
                elsif !@scene_item.name.to_s.strip.empty?
                  s_name = @scene_item.name.to_s.strip
                end
              end
              s_name = (@info[:scene_name] || @info[:name_scene] || "") if s_name.strip.empty?
              s_name.to_s.strip
            when "scene_description", "description", "scene_desc", "desc"
              s_desc = ""
              if @scene_item
                if @scene_item.respond_to?(:scene_ref) && @scene_item.scene_ref && @scene_item.scene_ref.respond_to?(:description) && !@scene_item.scene_ref.description.to_s.strip.empty?
                  s_desc = @scene_item.scene_ref.description.to_s.strip
                elsif !@scene_item.description.to_s.strip.empty?
                  s_desc = @scene_item.description.to_s.strip
                end
              end
              s_desc = (@info[:scene_description] || @info[:scene_desc] || "") if s_desc.strip.empty?
              s_desc.to_s.strip
            else
              resolve_info_line(k)
            end
          end

          grouped_rows = { 1 => [], 2 => [], 3 => [], 4 => [], 5 => [] }
          if lines && lines.is_a?(Array) && !lines.empty?
            lines.each_with_index do |k, idx|
              k_str = k.to_s
              default_r = case k_str
                          when "furniture_name" then 1
                          when "place_address" then 2
                          when "customer_or_company" then 3
                          when "scene_name", "name", "name_scene" then 4
                          when "scene_description", "description", "scene_desc", "desc" then 5
                          else [idx + 1, 5].min
                          end
              row_num = (line_rows[k_str] || line_rows[k.to_sym] || default_r).to_i
              row_num = 1 if row_num < 1
              row_num = 5 if row_num > 5

              val = resolve_header_item.call(k_str)
              if val && !val.to_s.strip.empty?
                item_sz = (line_font_sizes[k_str] || line_font_sizes[k.to_sym] || font_size).to_f
                item_sz = font_size if item_sz <= 0.0

                raw_col = (line_colors[k_str] || line_colors[k.to_sym] || "0F172A").to_s.strip
                clean_col = raw_col.sub(/^#/, "")
                clean_col = "0F172A" if clean_col.empty?

                grouped_rows[row_num] << {
                  key: k_str,
                  text: val.to_s.strip,
                  size: item_sz,
                  color: clean_col
                }
              end
            end
          end

          active_rows = [1, 2, 3, 4, 5].select { |r| grouped_rows[r] && !grouped_rows[r].empty? }

          # Если все пункты отключены или нет данных для вывода — ничего не ставить на странице
          return if active_rows.empty?

          align = :center

          # Расчет высоты строк и отступов (увеличенные промежутки между строками)
          item_gap = active_rows.size > 1 ? (active_rows.size > 3 ? 5.5 : 7.5) : 0.0
          row_heights = {}
          active_rows.each do |r|
            max_item_sz = grouped_rows[r].map { |it| it[:size] }.max || font_size
            row_heights[r] = [max_item_sz * 1.3, max_item_sz + 4.0].max
          end
          raw_total_h = row_heights.values.sum + ((active_rows.size - 1) * item_gap)

          scale = 1.0
          available_h = hdr_box[:height] - 4.0
          if raw_total_h > available_h && raw_total_h > 0
            scale = [available_h / raw_total_h, 0.6].max
          end

          scaled_item_gap = item_gap * scale
          scaled_row_heights = {}
          active_rows.each do |r|
            scaled_row_heights[r] = row_heights[r] * scale
          end
          total_h = scaled_row_heights.values.sum + ((active_rows.size - 1) * scaled_item_gap)

          cur_y = case valign
                  when :top
                    hdr_box[:y] - 2
                  when :bottom
                    hdr_box[:y] - hdr_box[:height] + total_h + 2
                  else # :center
                    offset = [(hdr_box[:height] - total_h) / 2.0, 2.0].max
                    hdr_box[:y] - offset
                  end

          Service::FontService.apply_style(@pdf_doc, :bold)

          active_rows.each_with_index do |r, idx|
            items = grouped_rows[r]
            r_h = scaled_row_heights[r]

            fragments = []
            items.each_with_index do |it, i|
              if i > 0
                sep_sz = [it[:size], items[i-1][:size]].min * scale
                fragments << {
                  text: " | ",
                  size: sep_sz,
                  color: "CBD5E1"
                }
              end
              fragments << {
                text: it[:text],
                size: it[:size] * scale,
                color: it[:color]
              }
            end

            @pdf_doc.formatted_text_box(
              fragments,
              at: [hdr_box[:x] + 4, cur_y],
              width: hdr_box[:width] - 8,
              height: r_h,
              align: :center,
              valign: :center,
              overflow: :shrink_to_fit
            )
            cur_y -= r_h

            if idx < active_rows.size - 1
              sep_y = cur_y - (scaled_item_gap / 2.0)
              @pdf_doc.stroke_color "CBD5E1"
              @pdf_doc.line_width 0.5
              line_w = [hdr_box[:width] * 0.45, 130.0].min
              lx = hdr_box[:x] + (hdr_box[:width] - line_w) / 2.0
              @pdf_doc.stroke_horizontal_line lx, lx + line_w, at: sep_y
              cur_y -= scaled_item_gap
            end
          end
        end

        def render_modular_footer(pt, ftr_box)
          cfg = get_block_config(pt, :footer)
          raw_valign = (cfg[:valign] || cfg["valign"] || "bottom").to_s
          valign = (raw_valign == "top") ? :top : :bottom
          font_size = (cfg[:font_size] || cfg["font_size"] || 8.5).to_f

          @pdf_doc.fill_color "475569"
          Service::FontService.apply_style(@pdf_doc, :small)

          raw_lines = cfg[:lines] || cfg["lines"]
          lines = if raw_lines.is_a?(Array) && !raw_lines.empty?
                    raw_lines.map(&:to_s)
                  else
                    ["footer_last_edit", "footer_ver_rev", "footer_articul", "footer_date", "footer_page_total"]
                  end

          # Поддержка старого составного ключа footer_rev_ver_date
          expanded_lines = []
          lines.each do |k|
            if k == "footer_rev_ver_date"
              expanded_lines << "footer_ver_rev"
              expanded_lines << "footer_articul"
              expanded_lines << "footer_date"
            else
              expanded_lines << k
            end
          end

          raw_aligns = cfg[:line_aligns] || cfg["line_aligns"] || {}
          line_aligns = {}
          if raw_aligns.is_a?(Hash)
            raw_aligns.each { |k, v| line_aligns[k.to_s] = v.to_s }
          end

          default_aligns = {
            "footer_last_edit"  => "left",
            "footer_ver_rev"    => "center",
            "footer_articul"    => "center",
            "footer_date"       => "center",
            "footer_page_total" => "right"
          }

          left_items = []
          center_items = []
          right_items = []

          expanded_lines.each do |k|
            text = resolve_info_line(k)
            next if text.nil? || text.to_s.strip.empty?

            item_align = (line_aligns[k] || default_aligns[k] || "center").to_s.downcase
            case item_align
            when "left"
              left_items << text.to_s.strip
            when "right"
              right_items << text.to_s.strip
            else
              center_items << text.to_s.strip
            end
          end

          left_text = left_items.join("   |   ")
          center_text = center_items.join("   |   ")
          right_text = right_items.join("   |   ")

          y_pos = ftr_box[:y]
          h_pos = ftr_box[:height]
          w_total = ftr_box[:width]

          # Адаптивный расчет ширины колонок в зависимости от наличия контента
          has_left = !left_text.empty?
          has_center = !center_text.empty?
          has_right = !right_text.empty?

          if has_left && has_center && has_right
            w_left = (w_total * 0.35).round(2)
            w_center = (w_total * 0.42).round(2)
            w_right = (w_total - w_left - w_center).round(2)
            x_left = ftr_box[:x] + 4
            x_center = ftr_box[:x] + w_left + 2
            x_right = ftr_box[:x] + w_left + w_center + 4

            @pdf_doc.text_box left_text, at: [x_left, y_pos], width: w_left - 6, height: h_pos, align: :left, valign: valign, size: font_size, overflow: :shrink_to_fit
            @pdf_doc.text_box center_text, at: [x_center, y_pos], width: w_center - 4, height: h_pos, align: :center, valign: valign, size: font_size, overflow: :shrink_to_fit
            @pdf_doc.text_box right_text, at: [x_right, y_pos], width: w_right - 12, height: h_pos, align: :right, valign: valign, size: font_size, overflow: :shrink_to_fit
          elsif has_left && has_right && !has_center
            w_left = (w_total * 0.65).round(2)
            w_right = (w_total - w_left).round(2)
            @pdf_doc.text_box left_text, at: [ftr_box[:x] + 4, y_pos], width: w_left - 6, height: h_pos, align: :left, valign: valign, size: font_size, overflow: :shrink_to_fit
            @pdf_doc.text_box right_text, at: [ftr_box[:x] + w_left + 4, y_pos], width: w_right - 12, height: h_pos, align: :right, valign: valign, size: font_size, overflow: :shrink_to_fit
          elsif has_center && !has_left && !has_right
            @pdf_doc.text_box center_text, at: [ftr_box[:x] + 4, y_pos], width: w_total - 8, height: h_pos, align: :center, valign: valign, size: font_size, overflow: :shrink_to_fit
          elsif has_left && !has_center && !has_right
            @pdf_doc.text_box left_text, at: [ftr_box[:x] + 4, y_pos], width: w_total - 8, height: h_pos, align: :left, valign: valign, size: font_size, overflow: :shrink_to_fit
          elsif has_right && !has_left && !has_center
            @pdf_doc.text_box right_text, at: [ftr_box[:x] + 4, y_pos], width: w_total - 12, height: h_pos, align: :right, valign: valign, size: font_size, overflow: :shrink_to_fit
          elsif has_left && has_center && !has_right
            w_left = (w_total * 0.45).round(2)
            w_center = (w_total - w_left).round(2)
            @pdf_doc.text_box left_text, at: [ftr_box[:x] + 4, y_pos], width: w_left - 6, height: h_pos, align: :left, valign: valign, size: font_size, overflow: :shrink_to_fit
            @pdf_doc.text_box center_text, at: [ftr_box[:x] + w_left + 2, y_pos], width: w_center - 6, height: h_pos, align: :center, valign: valign, size: font_size, overflow: :shrink_to_fit
          elsif has_center && has_right && !has_left
            w_center = (w_total * 0.65).round(2)
            w_right = (w_total - w_center).round(2)
            @pdf_doc.text_box center_text, at: [ftr_box[:x] + 4, y_pos], width: w_center - 6, height: h_pos, align: :center, valign: valign, size: font_size, overflow: :shrink_to_fit
            @pdf_doc.text_box right_text, at: [ftr_box[:x] + w_center + 4, y_pos], width: w_right - 12, height: h_pos, align: :right, valign: valign, size: font_size, overflow: :shrink_to_fit
          end
        end

        def render_modular_slot_card(slot_box, content_type, cfg, opacity, slot_id = nil)
          # Рамка и затемнение белым под текстом убраны по требованию пользователя
          pad = 4
          in_x = slot_box[:x] + pad
          in_y = slot_box[:y] - pad
          in_w = [slot_box[:width] - (pad * 2), 10.0].max
          in_h = [slot_box[:height] - (pad * 2), 10.0].max

          is_right_slot = [:slot_3, :slot_4, "slot_3", "slot_4"].include?(slot_id)
          default_align = is_right_slot ? :right : :left
          raw_align = cfg[:align] || cfg["align"]
          align = if raw_align && !raw_align.to_s.empty?
                    raw_align.to_s.to_sym
                  else
                    default_align
                  end
          align = :right if is_right_slot && align == :left
          align = :left if !is_right_slot && align == :right

          is_bottom_slot = [:slot_2, :slot_4, "slot_2", "slot_4"].include?(slot_id)
          raw_valign = cfg[:valign] || cfg["valign"]
          valign = if raw_valign && !raw_valign.to_s.empty?
                     v_sym = raw_valign.to_s.to_sym
                     [:top, :center, :middle, :bottom].include?(v_sym) ? (v_sym == :middle ? :center : v_sym) : (is_bottom_slot ? :bottom : :top)
                   else
                     is_bottom_slot ? :bottom : :top
                   end

          font_size = (cfg[:font_size] || cfg["font_size"] || 8.0).to_f
          title_size = [font_size + 1.5, 22.0].min
          lines = cfg[:lines] || cfg["lines"]
          in_bottom_y = slot_box[:y] - slot_box[:height] + pad

          if content_type == "custom_text"
            txt = (cfg[:custom_text] || cfg["custom_text"] || "").to_s
            @pdf_doc.fill_color "1E293B"
            Service::FontService.apply_style(@pdf_doc, :body)
            if valign == :bottom
              txt_h = @pdf_doc.height_of(txt, width: in_w, size: font_size)
              txt_box_h = [txt_h + 2.0, in_h].min
              target_top_y = [in_bottom_y + txt_box_h, in_y].min
              @pdf_doc.text_box txt, at: [in_x, target_top_y], width: in_w, height: txt_box_h, align: align, valign: :bottom, size: font_size, overflow: :shrink_to_fit
            elsif valign == :center
              txt_h = @pdf_doc.height_of(txt, width: in_w, size: font_size)
              txt_box_h = [txt_h + 2.0, in_h].min
              offset = [(in_h - txt_box_h) / 2.0, 0.0].max
              target_top_y = in_y - offset
              @pdf_doc.text_box txt, at: [in_x, target_top_y], width: in_w, height: txt_box_h, align: align, valign: :top, size: font_size, overflow: :shrink_to_fit
            else
              @pdf_doc.text_box txt, at: [in_x, in_y], width: in_w, height: in_h, align: align, valign: valign, size: font_size, overflow: :shrink_to_fit
            end
            return
          end

          items = []
          line_aligns = cfg[:line_aligns] || cfg["line_aligns"] || {}
          line_sizes = cfg[:line_font_sizes] || cfg["line_font_sizes"] || {}
          line_colors = cfg[:line_colors] || cfg["line_colors"] || {}

          if lines && lines.is_a?(Array)
            lines.each do |line_key|
              line_text = resolve_info_line(line_key)
              next if line_text.nil? || line_text.to_s.empty?
              k_str = line_key.to_s
              k_sym = line_key.to_sym rescue nil

              it_sz = (line_sizes[k_str] || (k_sym && line_sizes[k_sym]) || font_size).to_f
              it_sz = font_size if it_sz <= 0.0

              raw_col = (line_colors[k_str] || (k_sym && line_colors[k_sym]) || "334155").to_s.strip
              it_col = raw_col.sub(/^#/, "")
              it_col = "334155" if it_col.empty?

              it_align = (line_aligns[k_str] || (k_sym && line_aligns[k_sym]) || align).to_s.to_sym
              it_align = align unless [:left, :right, :center].include?(it_align)

              items << {
                key: k_str,
                text: line_text,
                size: it_sz,
                color: it_col,
                align: it_align
              }
            end
          else
            raw_lines = case content_type
                        when "project_card"
                          get_default_project_card_lines
                        when "customer_card"
                          get_default_customer_card_lines
                        when "workflow_status"
                          get_default_workflow_status_lines
                        when "history_table"
                          get_default_history_lines
                        when "materials_spec"
                          [@info[:materials].to_s.strip.empty? ? "Фасады, корпус, фурнитура..." : @info[:materials].to_s.strip]
                        when "appliances_spec"
                          [@info[:appliances].to_s.strip.empty? ? "Встраиваемая техника и приборы..." : @info[:appliances].to_s.strip]
                        when "lighting_spec"
                          [@info[:lighting].to_s.strip.empty? ? "LED подсветка и блоки питания..." : @info[:lighting].to_s.strip]
                        when "scene_notes"
                          desc = (@scene_item ? @scene_item.description : nil)
                          [(desc && !desc.empty?) ? desc : (@info[:notes].to_s.strip.empty? ? "Габаритные размеры и привязки..." : @info[:notes].to_s.strip)]
                        else
                          []
                        end
            (raw_lines || []).each do |s|
              items << { text: s, size: font_size, color: "334155", align: align } if s && !s.empty?
            end
          end

          return if items.empty?

          Service::FontService.apply_style(@pdf_doc, :small)

          item_gap = if (cfg.key?(:item_gap_mm) && !cfg[:item_gap_mm].nil?) || (cfg.key?("item_gap_mm") && !cfg["item_gap_mm"].nil?)
                       mm_val = (cfg[:item_gap_mm] || cfg["item_gap_mm"]).to_f
                       (mm_val * 72.0 / 25.4).round(1)
                     elsif (cfg.key?(:item_gap) && !cfg[:item_gap].nil?) || (cfg.key?("item_gap") && !cfg["item_gap"].nil?)
                       (cfg[:item_gap] || cfg["item_gap"]).to_f
                     else
                       6.0
                     end
          item_heights = items.map do |it|
            [@pdf_doc.height_of(it[:text], width: in_w, size: it[:size]) + 1.0, it[:size] + 2.0].max
          end
          total_items_h = item_heights.sum + ([items.size - 1, 0].max * item_gap)

          cur_y = if valign == :bottom
                    [in_bottom_y + total_items_h, in_y].min
                  elsif valign == :center
                    offset = [(in_h - total_items_h) / 2.0, 0.0].max
                    in_y - offset
                  else
                    in_y
                  end

          items.each_with_index do |it, idx|
            h = item_heights[idx]
            @pdf_doc.fill_color it[:color]
            item_align = it[:align] || align
            @pdf_doc.text_box it[:text], at: [in_x, cur_y], width: in_w, height: h, align: item_align, valign: :top, size: it[:size], overflow: :shrink_to_fit
            cur_y -= h

            if idx < items.size - 1
              sep_y = cur_y - (item_gap / 2.0)
              @pdf_doc.stroke_color "CBD5E1"
              @pdf_doc.line_width 0.5
              line_w = [in_w * 0.75, 120.0].min
              lx = if item_align == :right
                     in_x + in_w - line_w
                   elsif item_align == :center
                     in_x + (in_w - line_w) / 2.0
                   else
                     in_x
                   end
              @pdf_doc.stroke_horizontal_line lx, lx + line_w, at: sep_y
              cur_y -= item_gap
            end
          end
        end

        # Разрешает строковый ключ информации в текст для отображения на листе
        def resolve_info_line(key)
          k_str = key.to_s
          case k_str
          when "toc_pages", "toc"
            scenes = if @project_data.respond_to?(:scenes) && @project_data.scenes
                       @project_data.scenes.select { |s| s.enabled && s.page_type.to_s != "skip" }
                     else
                       []
                     end
            total_count = (@total_pages && @total_pages.to_i > 0) ? @total_pages.to_i : scenes.size
            if !scenes.empty?
              lines_list = scenes.each_with_index.map { |s, idx| "#{idx + 1}. #{s.name}" }
              "Содержание (всего страниц: #{total_count}):\n" + lines_list.join("\n")
            else
              "Содержание: Список страниц проекта"
            end
          when "place_address"
            room = (@info[:room_name] || @info[:name_place]).to_s.strip
            addr = (@info[:address] || @info[:adress]).to_s.strip
            val = [room, addr].reject(&:empty?).join(" | ")
            val.empty? ? "Место | Адрес" : val
          when "customer_or_company"
            cust = (@info[:name_customer] || @info[:customer]).to_s.strip
            comp = (@info[:company] || @info[:name_company]).to_s.strip
            val = [cust, comp].reject(&:empty?).join(" | ")
            val.empty? ? "Имя заказчика / Компания" : val
          when "general_notes"
            val = (@info[:project_description] || @info[:description] || @info[:notes]).to_s.strip
            val.empty? ? "Общие пояснения: —" : "Общие пояснения: #{val}"
          when "workflow_history", "history_table"
            hist = @workflow[:history_edit] || @info[:history_edit]
            if hist.is_a?(Array) && !hist.empty?
              lines_arr = hist.map do |entry|
                if entry.is_a?(Array)
                  date, desc = entry[0].to_s.strip, entry[1].to_s.strip
                  desc.empty? ? date : "#{date} — #{desc}"
                elsif entry.is_a?(Hash)
                  d = (entry[:data] || entry[:date] || entry["data"] || entry["date"]).to_s.strip
                  desc = (entry[:edit] || entry[:text] || entry["edit"] || entry["text"] || entry[:description] || entry["description"]).to_s.strip
                  desc.empty? ? d : "#{d} — #{desc}"
                else
                  entry.to_s.strip
                end
              end.reject(&:empty?)
              lines_arr.empty? ? "История правок: нет записей" : ("История правок:\n" + lines_arr.join("\n"))
            else
              val = (@workflow[:last_edit] || @info[:last_edit]).to_s.strip
              val.empty? ? "История правок: —" : "История правок: #{val}"
            end
          when "workflow_stadia"
            stadia = @workflow[:stadia] || @info[:stadia]
            if stadia.is_a?(Array) && !stadia.empty?
              lines_arr = stadia.map do |st|
                if st.is_a?(Hash)
                  done = (st[:status] == true || st["status"] == true || st[:status].to_s == "true" || st["status"].to_s == "true")
                  title = (st[:name] || st["name"] || st[:title] || st["title"]).to_s.strip
                  mark = done ? "[✓]" : "[ ]"
                  "#{mark} #{title}"
                elsif st.is_a?(Array)
                  done = (st[1] == true || st[1] == "true")
                  title = st[2].to_s.strip
                  mark = done ? "[✓]" : "[ ]"
                  "#{mark} #{title}"
                else
                  st.to_s.strip
                end
              end.reject(&:empty?)
              lines_arr.empty? ? "Стадия проекта: В работе" : ("Стадия проекта:\n" + lines_arr.join("\n"))
            else
              st = (@workflow[:status] || @info[:status]).to_s.strip
              st.empty? ? "Стадия проекта: Предварительный проект" : "Стадия проекта: #{st}"
            end
          when "footer_last_edit"
            hist = @workflow[:history_edit] || @info[:history_edit]
            last = if hist.is_a?(Array) && !hist.empty?
                     entry = hist.last
                     if entry.is_a?(Array)
                       "#{entry[0]} #{entry[1]}"
                     elsif entry.is_a?(Hash)
                       d = entry[:data] || entry[:date] || entry["data"] || entry["date"]
                       t = entry[:edit] || entry[:text] || entry["edit"] || entry["text"]
                       "#{d} #{t}".strip
                     else
                       entry.to_s
                     end
                   else
                     (@workflow[:last_edit] || @info[:last_edit]).to_s
                   end
            last = last.strip
            last.empty? ? "Последние изменения: —" : (last.downcase.start_with?("последние") ? last : "Последние изменения: #{last}")
          when "footer_ver_rev"
            rev = @workflow[:revision] || @info[:revision] || "001"
            ver = @workflow[:version] || @info[:version] || "01"
            "Версия #{ver} # Ревизия #{rev}"
          when "footer_articul"
            art = (@info[:articul] || "").to_s.strip
            art = "CF##{@info[:id] || 'PRJ'}" if art.empty?
            art.downcase.start_with?("артикул") ? art : "Артикул: #{art}"
          when "footer_date"
            d = @workflow[:last_edit_date] || @info[:date]
            d = d.to_s.strip
            d = Time.now.strftime("%d.%m.%Y") if d.empty?
            d.downcase.start_with?("дата") ? d : "Дата: #{d}"
          when "footer_rev_ver_date"
            rev = @workflow[:revision] || @info[:revision] || "001"
            ver = @workflow[:version] || @info[:version] || "01"
            art = (@info[:articul] || "").to_s.strip
            art = "CF##{@info[:id] || 'PRJ'}" if art.empty?
            date = Time.now.strftime("%d.%m.%Y")
            "Ревизия #{rev} # Версия #{ver} | #{art} | #{date}"
          when "footer_page_total"
            "Страница #{@page_index} | #{@total_pages}"
          when "workflow_date", "date"
            d = @workflow[:last_edit_date] || @info[:date]
            d ? "Дата: #{d}" : "Дата: #{Time.now.strftime('%d.%m.%Y')}"
          when "room_name"
            val = (@info[:room_name] || @info[:name_place]).to_s.strip
            val.empty? ? "Помещение: —" : "Помещение: #{val}"
          when "furniture_name"
            val = (@info[:furniture_name] || @info[:name_product]).to_s.strip
            val.empty? ? "Изделие: —" : "Изделие: #{val}"
          when "trade_type"
            val = (@info[:trade] == 1 || @info[:trade] == "1") ? "Коммерческий (CF#)" : "Бытовой (HF#)"
            "Тип: #{val}"
          when "articul"
            val = @info[:articul].to_s.strip
            val.empty? ? "Артикул: —" : "Артикул: #{val}"
          when "address"
            val = (@info[:address] || @info[:adress]).to_s.strip
            val.empty? ? "Адрес: —" : "Адрес: #{val}"
          when "project_desc"
            val = (@info[:project_description] || @info[:description]).to_s.strip
            val.empty? ? "Описание: —" : "Описание: #{val}"
          when "customer_name"
            val = (@info[:name_customer] || @info[:customer]).to_s.strip
            val.empty? ? "Заказчик: —" : "Заказчик: #{val}"
          when "customer_id"
            val = (@info[:customer_id] || @info[:id]).to_s.strip
            val.empty? ? "ID клиента: —" : "ID клиента: #{val}"
          when "customer_company"
            val = (@info[:company] || @info[:name_company]).to_s.strip
            val.empty? ? "Компания: —" : "Компания: #{val}"
          when "customer_phone"
            val = @info[:phone].to_s.strip
            val.empty? ? "Тел: —" : "Тел: #{val}"
          when "customer_email"
            val = @info[:email].to_s.strip
            val.empty? ? "Email: —" : "Email: #{val}"
          when "scene_name", "name_scene"
            s_name = ""
            if @scene_item
              if @scene_item.respond_to?(:scene_ref) && @scene_item.scene_ref && @scene_item.scene_ref.respond_to?(:name) && !@scene_item.scene_ref.name.to_s.strip.empty?
                s_name = @scene_item.scene_ref.name.to_s.strip
              elsif !@scene_item.name.to_s.strip.empty?
                s_name = @scene_item.name.to_s.strip
              end
            end
            s_name = (@info[:scene_name] || @info[:name_scene] || "") if s_name.strip.empty?
            s_name = s_name.to_s.strip
            s_name.empty? ? "Сцена: —" : "Сцена: #{s_name}"
          when "scene_description", "scene_desc"
            s_desc = ""
            if @scene_item
              if @scene_item.respond_to?(:scene_ref) && @scene_item.scene_ref && @scene_item.scene_ref.respond_to?(:description) && !@scene_item.scene_ref.description.to_s.strip.empty?
                s_desc = @scene_item.scene_ref.description.to_s.strip
              elsif !@scene_item.description.to_s.strip.empty?
                s_desc = @scene_item.description.to_s.strip
              end
            end
            s_desc = (@info[:scene_description] || @info[:scene_desc] || "") if s_desc.strip.empty?
            s_desc = s_desc.to_s.strip
            s_desc.empty? ? "Описание сцены: —" : "Описание сцены: #{s_desc}"
          when "workflow_status"
            val = (@workflow[:status] || @info[:status]).to_s.strip
            val.empty? ? "Статус: —" : "Статус: #{val}"
          when "workflow_version"
            ver = @workflow[:version] || @info[:version] || 1
            "Версия: v#{ver}"
          when "workflow_revision"
            rev = @workflow[:revision] || @info[:revision] || "001"
            "Ревизия: #r#{rev}"
          when "workflow_dates"
            s = @info[:start_date].to_s.strip
            e = @info[:end_date].to_s.strip
            (s.empty? && e.empty?) ? "Сроки: —" : "Сроки: #{s.empty? ? '—' : s} → #{e.empty? ? '—' : e}"
          when "workflow_duration"
            val = @info[:total_duration].to_s.strip
            val.empty? ? "Длительность: —" : "Длительность: #{val} дн."
          when "workflow_price"
            val = @info[:price].to_s.strip
            val.empty? ? "Стоимость: —" : "Стоимость: #{val} руб."
          when "workflow_author"
            val = (@workflow[:author] || @info[:author]).to_s.strip
            val.empty? ? "Автор: —" : "Автор: #{val}"
          when "workflow_edit"
            val = (@workflow[:last_edit] || @info[:last_edit]).to_s.strip
            val.empty? ? "Правка: —" : "Правка: #{val}"
          when "spec_materials"
            val = @info[:materials].to_s.strip
            val.empty? ? "Материалы: Фасады МДФ, ЛДСП, Blum..." : "Материалы: #{val}"
          when "spec_appliances"
            app = @info[:appliances].to_s.strip
            lig = @info[:lighting].to_s.strip
            combined = [app, lig].uniq.reject(&:empty?).join("; ")
            combined.empty? ? "Техника и подсветка: Встраиваемая техника, LED 3000K..." : "Техника и подсветка: #{combined}"
          when "spec_lighting"
            val = @info[:lighting].to_s.strip
            val.empty? ? "Подсветка: LED 3000K 24V..." : "Подсветка: #{val}"
          when "scene_notes"
            desc = (@scene_item ? @scene_item.description : nil)
            val = (desc && !desc.empty?) ? desc : @info[:notes].to_s.strip
            val.empty? ? "Примечание: Габаритные размеры..." : "Примечание: #{val}"
          when "system_date"
            "Дата: #{Time.now.strftime('%d.%m.%Y')}"
          when "system_page"
            "Лист #{@page_index} из #{@total_pages}"
          else
            nil
          end
        end

        def get_default_project_card_lines
          items = []
          room = (@info[:room_name] || @info[:name_place]).to_s.strip
          furn = (@info[:furniture_name] || @info[:name_product]).to_s.strip
          cust = (@info[:name_customer] || @info[:customer]).to_s.strip
          stat = @info[:status].to_s.strip

          items << "Помещение: #{room}" unless room.empty?
          items << "Изделие: #{furn}" unless furn.empty?
          items << "Заказчик: #{cust}" unless cust.empty?
          items << "Статус: #{stat}" unless stat.empty?
          items << "Стоимость: #{@info[:price]} руб." unless @info[:price].to_s.strip.empty?
          items
        end

        def get_default_customer_card_lines
          items = []
          cust = (@info[:name_customer] || @info[:customer]).to_s.strip
          phone = @info[:phone].to_s.strip
          email = @info[:email].to_s.strip
          addr = (@info[:address] || @info[:adress]).to_s.strip
          comp = @info[:company].to_s.strip

          items << "Имя: #{cust}" unless cust.empty?
          items << "Компания: #{comp}" unless comp.empty?
          items << "Тел: #{phone}" unless phone.empty?
          items << "Email: #{email}" unless email.empty?
          items << "Адрес: #{addr}" unless addr.empty?
          items
        end

        def get_default_workflow_status_lines
          items = []
          items << "Версия: v#{@info[:version]} #r#{@info[:revision]}"
          items << "Статус: #{@info[:status] || 'В РАБОТЕ'}"
          items << "Сроки: #{@info[:start_date]} - #{@info[:end_date]}" if @info[:start_date] && @info[:end_date]
          items << "Длительность: #{@info[:total_duration]} дн." unless @info[:total_duration].to_s.strip.empty?
          items << "Дата проекта: #{Time.now.strftime('%d.%m.%Y')}"
          items
        end

        def get_default_history_lines
          wf = @project_data.workflow || {}
          hist = wf[:history_edit] || []
          items = []

          if hist.is_a?(Array) && !hist.empty?
            hist.last(3).each do |entry|
              if entry.is_a?(Array)
                items << "#{entry[0]}: #{entry[1]}"
              elsif entry.is_a?(Hash)
                items << "#{entry[:date] || entry['date']}: #{entry[:text] || entry['text'] || entry[:description]}"
              end
            end
          else
            items << "v#{@info[:version]}#r#{@info[:revision]}: Начальная редакция"
          end
          items.map { |i| "• #{i}" }
        end
      end
    end
  end
end
