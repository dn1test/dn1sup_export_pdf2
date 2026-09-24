# frozen_string_literal: true

module DN1Code
  module ExportPdf2
    module Service
      # Сервис отображения рамки пропорций кадра (Safe Frame Overlay)
      # Позволяет пользователю в реальном времени видеть границы кадра рендера в окне SketchUp
      module OverlayService
        OVERLAY_ID   = "dn1code.export_pdf2.safe_frame_overlay"
        OVERLAY_NAME = "DN1C: Рамка экспорта PDF (Safe Frame)"

        @active_overlay = nil
        @current_settings = nil

        class << self
          attr_accessor :current_settings
        end

        # Класс оверлея SketchUp 2023+ (с безопасным наследованием для тестов и старых версий)
        class SafeFrameOverlay < (defined?(Sketchup::Overlay) ? Sketchup::Overlay : Object)
          attr_accessor :ratio_cache, :label_cache, :width_cache, :height_cache, :visible_cache
          attr_accessor :border_color_cache, :border_opacity_cache, :mask_color_cache, :mask_opacity_cache
          attr_accessor :line_width_cache

          def initialize
            if defined?(Sketchup::Overlay)
              super(OVERLAY_ID, OVERLAY_NAME, description: "Отображает границы и пропорции кадра для экспорта в PDF")
            end
            @ratio_cache          = 4.0 / 3.0
            @label_cache          = "4:3"
            @width_cache          = 2400
            @height_cache         = 1800
            @visible_cache        = true
            @border_color_cache   = "#0EA5E9"
            @border_opacity_cache = 100
            @mask_color_cache     = "#0F172A"
            @mask_opacity_cache   = 80
            @line_width_cache     = 1
          end

          # Отрисовка рамки в окне просмотра SketchUp
          # @param view [Sketchup::View] активное окно просмотра
          # @return [void]
          def draw(view)
            return unless view && view.respond_to?(:vpwidth) && view.respond_to?(:vpheight)

            vp_w = view.vpwidth.to_f
            vp_h = view.vpheight.to_f
            return if vp_w <= 10.0 || vp_h <= 10.0

            begin
              model = defined?(Sketchup) && Sketchup.respond_to?(:active_model) ? Sketchup.active_model : nil

              target_ratio = @ratio_cache
              target_label = @label_cache
              target_w     = @width_cache
              target_h     = @height_cache

              if target_ratio.nil? || target_ratio <= 0.001 || @visible_cache.nil?
                ratio_info   = OverlayService.calculate_target_info(model)
                target_ratio = ratio_info[:ratio]
                target_label = ratio_info[:label]
                target_w     = ratio_info[:render_w]
                target_h     = ratio_info[:render_h]
                @visible_cache        = ratio_info[:visible]
                @ratio_cache          = target_ratio
                @label_cache          = target_label
                @width_cache          = target_w
                @height_cache         = target_h
                @border_color_cache   = ratio_info[:border_color]
                @border_opacity_cache = ratio_info[:border_opacity]
                @mask_color_cache     = ratio_info[:mask_color]
                @mask_opacity_cache   = ratio_info[:mask_opacity]
                @line_width_cache     = ratio_info[:line_width] || 1
              end

              return if @visible_cache == false
              return if target_ratio.nil? || target_ratio <= 0.001

              vp_ratio = vp_w / vp_h

              # Расчет координат рамки
              if vp_ratio > target_ratio
                # Окно шире рамки: рамка по высоте окна, полосы по бокам (Pillarbox)
                frame_h = vp_h
                frame_w = frame_h * target_ratio
                frame_x = ((vp_w - frame_w) / 2.0).round
                frame_y = 0.0
              else
                # Окно уже или выше рамки: рамка по ширине окна, полосы сверху и снизу (Letterbox)
                frame_w = vp_w
                frame_h = frame_w / target_ratio
                frame_x = 0.0
                frame_y = ((vp_h - frame_h) / 2.0).round
              end

              return unless view.respond_to?(:draw2d)

              # 1. Отрисовка затемнения за пределами рамки (Letterbox / Pillarbox)
              mask_color = OverlayService.parse_color(@mask_color_cache || "#0F172A", @mask_opacity_cache || 55, 15, 23, 42, 140)
              view.drawing_color = mask_color

              if frame_x > 0.5
                # Левая полоса
                left_quad = [
                  Geom::Point3d.new(0.0, 0.0, 0.0),
                  Geom::Point3d.new(frame_x, 0.0, 0.0),
                  Geom::Point3d.new(frame_x, vp_h, 0.0),
                  Geom::Point3d.new(0.0, vp_h, 0.0)
                ]
                view.draw2d(GL_QUADS, left_quad)

                # Правая полоса
                right_x = frame_x + frame_w
                right_quad = [
                  Geom::Point3d.new(right_x, 0.0, 0.0),
                  Geom::Point3d.new(vp_w, 0.0, 0.0),
                  Geom::Point3d.new(vp_w, vp_h, 0.0),
                  Geom::Point3d.new(right_x, vp_h, 0.0)
                ]
                view.draw2d(GL_QUADS, right_quad)
              elsif frame_y > 0.5
                # Верхняя полоса
                top_quad = [
                  Geom::Point3d.new(0.0, 0.0, 0.0),
                  Geom::Point3d.new(vp_w, 0.0, 0.0),
                  Geom::Point3d.new(vp_w, frame_y, 0.0),
                  Geom::Point3d.new(0.0, frame_y, 0.0)
                ]
                view.draw2d(GL_QUADS, top_quad)

                # Нижняя полоса
                bottom_y = frame_y + frame_h
                bottom_quad = [
                  Geom::Point3d.new(0.0, bottom_y, 0.0),
                  Geom::Point3d.new(vp_w, bottom_y, 0.0),
                  Geom::Point3d.new(vp_w, vp_h, 0.0),
                  Geom::Point3d.new(0.0, vp_h, 0.0)
                ]
                view.draw2d(GL_QUADS, bottom_quad)
              end

              # 2. Сетка третей (Rule of Thirds, тонкие штриховые ориентиры)
              grid_color = defined?(Sketchup::Color) ? Sketchup::Color.new(255, 255, 255, 35) : "rgba(255,255,255,0.15)"
              view.drawing_color = grid_color
              view.line_width = 1 if view.respond_to?(:line_width=)

              x_t1 = frame_x + frame_w / 3.0
              x_t2 = frame_x + (frame_w * 2.0) / 3.0
              y_t1 = frame_y + frame_h / 3.0
              y_t2 = frame_y + (frame_h * 2.0) / 3.0

              grid_lines = [
                Geom::Point3d.new(x_t1, frame_y, 0.0), Geom::Point3d.new(x_t1, frame_y + frame_h, 0.0),
                Geom::Point3d.new(x_t2, frame_y, 0.0), Geom::Point3d.new(x_t2, frame_y + frame_h, 0.0),
                Geom::Point3d.new(frame_x, y_t1, 0.0), Geom::Point3d.new(frame_x + frame_w, y_t1, 0.0),
                Geom::Point3d.new(frame_x, y_t2, 0.0), Geom::Point3d.new(frame_x + frame_w, y_t2, 0.0)
              ]
              view.draw2d(GL_LINES, grid_lines)

              # 3. Основная контурная рамка кадра (пользовательский цвет и прозрачность, по умолчанию 1px)
              border_color = OverlayService.parse_color(@border_color_cache || "#0EA5E9", @border_opacity_cache || 100, 14, 165, 233, 255)
              view.drawing_color = border_color
              view.line_width = (@line_width_cache || 1) if view.respond_to?(:line_width=)

              frame_pts = [
                Geom::Point3d.new(frame_x, frame_y, 0.0),
                Geom::Point3d.new(frame_x + frame_w, frame_y, 0.0),
                Geom::Point3d.new(frame_x + frame_w, frame_y + frame_h, 0.0),
                Geom::Point3d.new(frame_x, frame_y + frame_h, 0.0)
              ]
              view.draw2d(GL_LINE_LOOP, frame_pts)

              # 4. Угловые засечки (акцентные L-маркеры рисуются только при усиленной толщине рамки)
              if @line_width_cache && @line_width_cache > 1
                corner_len = 24.0
                corner_color = OverlayService.parse_color(@border_color_cache || "#0EA5E9", 100, 56, 189, 248, 255)
                view.drawing_color = corner_color
                view.line_width = @line_width_cache if view.respond_to?(:line_width=)

                c_lines = [
                  # Верхний левый
                  Geom::Point3d.new(frame_x, frame_y, 0.0), Geom::Point3d.new(frame_x + corner_len, frame_y, 0.0),
                  Geom::Point3d.new(frame_x, frame_y, 0.0), Geom::Point3d.new(frame_x, frame_y + corner_len, 0.0),
                  # Верхний правый
                  Geom::Point3d.new(frame_x + frame_w, frame_y, 0.0), Geom::Point3d.new(frame_x + frame_w - corner_len, frame_y, 0.0),
                  Geom::Point3d.new(frame_x + frame_w, frame_y, 0.0), Geom::Point3d.new(frame_x + frame_w, frame_y + corner_len, 0.0),
                  # Нижний правый
                  Geom::Point3d.new(frame_x + frame_w, frame_y + frame_h, 0.0), Geom::Point3d.new(frame_x + frame_w - corner_len, frame_y + frame_h, 0.0),
                  Geom::Point3d.new(frame_x + frame_w, frame_y + frame_h, 0.0), Geom::Point3d.new(frame_x + frame_w, frame_y + frame_h - corner_len, 0.0),
                  # Нижний левый
                  Geom::Point3d.new(frame_x, frame_y + frame_h, 0.0), Geom::Point3d.new(frame_x + corner_len, frame_y + frame_h, 0.0),
                  Geom::Point3d.new(frame_x, frame_y + frame_h, 0.0), Geom::Point3d.new(frame_x, frame_y + frame_h - corner_len, 0.0)
                ]
                view.draw2d(GL_LINES, c_lines)
              end

              # 5. Информационная строка пропорций и разрешения (внизу по центру кадра, тонкий черный шрифт 9pt без темной рамки)
              if view.respond_to?(:draw_text)
                badge_text = "📐 #{target_label || 'Кадр'}  |  #{target_w || 2400} × #{target_h || 1800} px"
                center_x = (frame_x + (frame_w / 2.0)).round
                label_y = [frame_y + frame_h - 18.0, frame_y + 4.0].max
                label_pos = Geom::Point3d.new(center_x, label_y, 0.0)
                font_family = (RUBY_PLATFORM =~ /darwin/i) ? "Helvetica Neue" : "Segoe UI"
                align_center = defined?(TextAlignCenter) ? TextAlignCenter : 1
                options = {
                  :font => font_family,
                  :size => 9,
                  :bold => false,
                  :align => align_center,
                  :color => defined?(Sketchup::Color) ? Sketchup::Color.new(0, 0, 0, 255) : "black"
                }
                view.draw_text(label_pos, badge_text, options)
              end
            rescue StandardError
            end
          end
        end

        # Расчет информации о пропорциях кадра на основе текущих настроек проекта или модели
        # @param model [Sketchup::Model, nil]
        # @param override_settings [Hash, nil]
        # @return [Hash] {:ratio => Float, :label => String, :render_w => Integer, :render_h => Integer}
        def self.calculate_target_info(model = nil, override_settings = nil)
          pdata = nil
          if override_settings && (override_settings[:project_data] || override_settings["project_data"])
            pdata = override_settings[:project_data] || override_settings["project_data"]
          elsif model && defined?(Model::SessionStore)
            # Быстрое чтение из сессии памяти (без обращения к диску и атрибутам модели)
            pdata = Model::SessionStore.data(model)
          end

          base_settings = {}
          base_settings.merge!(pdata.pdf_settings) if pdata && pdata.pdf_settings
          base_settings.merge!(@current_settings) if @current_settings
          settings = override_settings ? base_settings.merge(override_settings) : base_settings
          settings ||= {}

          # Определение активной сцены и активного шаблона (template_key)
          matched_sc = nil
          if override_settings && (override_settings[:scene_item] || override_settings["scene_item"])
            matched_sc = override_settings[:scene_item] || override_settings["scene_item"]
          elsif override_settings && (override_settings[:scene_name] || override_settings["scene_name"])
            sc_name = (override_settings[:scene_name] || override_settings["scene_name"]).to_s
            matched_sc = pdata.scenes.find { |s| s.name == sc_name || s.original_name == sc_name } if pdata && pdata.scenes
          elsif override_settings && (override_settings[:scene_index] || override_settings["scene_index"])
            idx = (override_settings[:scene_index] || override_settings["scene_index"]).to_i
            matched_sc = pdata.scenes[idx] if pdata && pdata.scenes
          elsif model && model.respond_to?(:pages) && model.pages && model.pages.selected_page
            sel_page_name = model.pages.selected_page.name
            if pdata && pdata.scenes
              matched_sc = pdata.scenes.find { |s| s.name == sel_page_name || s.original_name == sel_page_name }
            end
          end

          tpl_key = settings[:template_key] || settings["template_key"]
          unless tpl_key
            tpl_key = matched_sc.page_type if matched_sc
          end
          tpl_key = (tpl_key || :cover).to_sym

          # Извлекаем параметры блока картинки (image_4_3) из шаблона с корректным слиянием уровней
          pdata_layouts    = (pdata.respond_to?(:custom_layouts) ? pdata.custom_layouts : nil) || (pdata ? pdata.pdf_settings[:custom_layouts] : nil) || {}
          session_layouts  = @current_settings ? (@current_settings[:custom_layouts] || @current_settings["custom_layouts"] || {}) : {}
          override_layouts = override_settings ? (override_settings[:custom_layouts] || override_settings["custom_layouts"] || {}) : {}

          pdata_tpl    = pdata_layouts[tpl_key] || pdata_layouts[tpl_key.to_s] || {}
          session_tpl  = session_layouts[tpl_key] || session_layouts[tpl_key.to_s] || {}
          override_tpl = override_layouts[tpl_key] || override_layouts[tpl_key.to_s] || {}

          pdata_img    = pdata_tpl[:image_4_3] || pdata_tpl["image_4_3"] || {}
          session_img  = session_tpl[:image_4_3] || session_tpl["image_4_3"] || {}
          override_img = override_tpl[:image_4_3] || override_tpl["image_4_3"] || {}

          tpl_cfg = pdata_tpl.merge(session_tpl).merge(override_tpl)
          img_cfg = pdata_img.merge(session_img).merge(override_img)

          # Проверка видимости блока видового экрана (из сцены или из шаблона)
          img_visible = if tpl_key.to_s == "blank" && (matched_sc.nil? || matched_sc.viewport_visible != true)
                          false
                        elsif matched_sc && matched_sc.respond_to?(:viewport_visible) && !matched_sc.viewport_visible.nil?
                          matched_sc.viewport_visible != false
                        elsif img_cfg.key?(:visible)
                          v = img_cfg[:visible]
                          v != false && v.to_s != "false" && v != 0 && v.to_s != "0"
                        elsif img_cfg.key?("visible")
                          v = img_cfg["visible"]
                          v != false && v.to_s != "false" && v != 0 && v.to_s != "0"
                        else
                          true
                        end
          if override_settings && (override_settings.key?(:visible) || override_settings.key?("visible"))
            v = override_settings[:visible].nil? ? override_settings["visible"] : override_settings[:visible]
            img_visible = (v != false && v.to_s != "false" && v != 0 && v.to_s != "0")
          end

          valid_modes = %w[page 16:9 4:3 3:2 1:1 custom].freeze

          gui_aspect = (settings[:image_aspect_ratio] || settings["image_aspect_ratio"]).to_s.strip
          gui_aspect = "4:3" if !gui_aspect.empty? && !valid_modes.include?(gui_aspect)

          scene_aspect = (matched_sc && matched_sc.respond_to?(:aspect_ratio)) ? matched_sc.aspect_ratio.to_s.strip : nil
          scene_aspect = nil unless valid_modes.include?(scene_aspect)

          img_aspect = (img_cfg[:aspect_ratio] || img_cfg["aspect_ratio"]).to_s.strip
          img_aspect = nil unless valid_modes.include?(img_aspect)

          explicit_ratio = (settings[:aspect_ratio] || settings["aspect_ratio"]).to_s.strip
          explicit_ratio = nil if explicit_ratio.empty?

          gui_explicit = !gui_aspect.empty? && gui_aspect != "page"
          aspect_mode = if gui_explicit
                          explicit_ratio || gui_aspect
                        else
                          explicit_ratio || scene_aspect || img_aspect || (!gui_aspect.empty? ? gui_aspect : "4:3")
                        end
          aspect_mode = aspect_mode.to_s.strip
          aspect_mode = "4:3" if aspect_mode.empty?

          page_size   = (settings[:page_size] || settings["page_size"] || (pdata ? pdata.pdf_settings[:page_size] : nil) || "A4").to_s.upcase
          page_layout = (settings[:page_layout] || settings["page_layout"] || (pdata ? pdata.pdf_settings[:page_layout] : nil) || "landscape").to_s.downcase
          img_w       = (settings[:image_width] || settings["image_width"] || (pdata ? pdata.pdf_settings[:image_width] : nil) || 2400).to_i
          img_w       = 2400 if img_w <= 0

          ratio = 1.3333
          label = "4:3"

          case aspect_mode
          when "16:9"
            ratio = 16.0 / 9.0
            label = "16:9"
          when "4:3"
            ratio = 4.0 / 3.0
            label = "4:3"
          when "3:2"
            ratio = 3.0 / 2.0
            label = "3:2"
          when "1:1"
            ratio = 1.0
            label = "1:1"
          when "custom"
            cw = (settings[:custom_ratio_w] || settings["custom_ratio_w"] || 16).to_f
            ch = (settings[:custom_ratio_h] || settings["custom_ratio_h"] || 9).to_f
            cw = 16.0 if cw <= 0.0
            ch = 9.0 if ch <= 0.0
            ratio = cw / ch
            label = "#{cw.round(1)}:#{ch.round(1)}"
          when "page"
            # Размеры страниц в миллиметрах (ширина x высота для landscape)
            dim = case page_size
                  when "A3"     then [420.0, 297.0]
                  when "A2"     then [594.0, 420.0]
                  when "LETTER" then [279.4, 215.9] # 11 x 8.5 дюймов
                  else               [297.0, 210.0] # A4
                  end

            if page_layout == "portrait"
              ratio = dim[1] / dim[0]
              label = "#{page_size} Книжный (#{ratio.round(2)}:1)"
            else
              ratio = dim[0] / dim[1]
              label = "#{page_size} Альбомный (#{ratio.round(2)}:1)"
            end
          else
            if aspect_mode =~ /^(\d+(?:\.\d+)?)\s*:\s*(\d+(?:\.\d+)?)$/
              w = $1.to_f
              h = $2.to_f
              ratio = w / [h, 0.001].max
              label = "#{w.round(1)}:#{h.round(1)}"
            elsif aspect_mode.to_f > 0.01
              ratio = aspect_mode.to_f
              label = "#{ratio.round(2)}:1"
            else
              ratio = 4.0 / 3.0
              label = "4:3"
            end
          end

          border_color_val   = settings[:overlay_border_color] || settings["overlay_border_color"] ||
                               img_cfg[:overlay_border_color] || img_cfg["overlay_border_color"] ||
                               (pdata ? pdata.pdf_settings[:overlay_border_color] : nil) || "#0EA5E9"

          border_opacity_val = settings[:overlay_border_opacity] || settings["overlay_border_opacity"] ||
                               img_cfg[:overlay_border_opacity] || img_cfg["overlay_border_opacity"] ||
                               (pdata ? pdata.pdf_settings[:overlay_border_opacity] : nil) || 100

          mask_color_val     = settings[:overlay_mask_color] || settings["overlay_mask_color"] ||
                               img_cfg[:overlay_mask_color] || img_cfg["overlay_mask_color"] ||
                               (pdata ? pdata.pdf_settings[:overlay_mask_color] : nil) || "#0F172A"

          mask_opacity_val   = settings[:overlay_mask_opacity] || settings["overlay_mask_opacity"] ||
                               img_cfg[:overlay_mask_opacity] || img_cfg["overlay_mask_opacity"] ||
                               (pdata ? pdata.pdf_settings[:overlay_mask_opacity] : nil) || 55

          border_color_val = "##{border_color_val}" unless border_color_val.to_s.start_with?("#")
          mask_color_val   = "##{mask_color_val}" unless mask_color_val.to_s.start_with?("#")

          border_opacity_val = border_opacity_val.to_i.clamp(0, 100)
          mask_opacity_val   = mask_opacity_val.to_i.clamp(0, 100)

          line_width_val     = (settings[:overlay_line_width] || settings["overlay_line_width"] ||
                               img_cfg[:overlay_line_width] || img_cfg["overlay_line_width"] ||
                               (pdata ? pdata.pdf_settings[:overlay_line_width] : nil) || 1).to_i
          line_width_val = 1 if line_width_val <= 0

          img_h = (img_w / ratio).round

          {
            ratio:          ratio,
            label:          label,
            aspect_ratio:   aspect_mode,
            render_w:       img_w,
            render_h:       img_h,
            border_color:   border_color_val,
            border_opacity: border_opacity_val,
            mask_color:     mask_color_val,
            mask_opacity:   mask_opacity_val,
            line_width:     line_width_val,
            visible:        img_visible,
            image_visible:  img_visible
          }
        end

        # Преобразует HEX-цвет и процент непрозрачности (0..100) в Sketchup::Color (RGBA)
        # @param hex_or_str [String, nil]
        # @param opacity_pct [Numeric, nil] 0..100 (или 0.0..1.0)
        # @param default_r [Integer]
        # @param default_g [Integer]
        # @param default_b [Integer]
        # @param default_a [Integer]
        # @return [Sketchup::Color, String]
        def self.parse_color(hex_or_str, opacity_pct = 100, default_r = 14, default_g = 165, default_b = 233, default_a = 255)
          alpha = if opacity_pct.nil?
                    default_a
                  elsif opacity_pct.is_a?(Numeric) && opacity_pct <= 1.0 && opacity_pct > 0.0
                    (opacity_pct * 255.0).round.clamp(0, 255)
                  else
                    ((opacity_pct.to_f / 100.0) * 255.0).round.clamp(0, 255)
                  end

          hex = hex_or_str.to_s.strip.sub(/^#/, "")
          r, g, b = if hex =~ /\A([0-9a-fA-F]{2})([0-9a-fA-F]{2})([0-9a-fA-F]{2})\z/
                      [$1.to_i(16), $2.to_i(16), $3.to_i(16)]
                    elsif hex =~ /\A([0-9a-fA-F])([0-9a-fA-F])([0-9a-fA-F])\z/
                      [($1 * 2).to_i(16), ($2 * 2).to_i(16), ($3 * 2).to_i(16)]
                    else
                      [default_r, default_g, default_b]
                    end

          if defined?(Sketchup::Color)
            Sketchup::Color.new(r, g, b, alpha)
          else
            "rgba(#{r},#{g},#{b},#{(alpha / 255.0).round(2)})"
          end
        end

        # Возвращает текущий синглтон-экземпляр оверлея
        # @return [SafeFrameOverlay]
        def self.overlay_instance
          @active_overlay ||= SafeFrameOverlay.new
        end

        # Поиск зарегистрированного оверлея в коллекции модели
        # @param model [Sketchup::Model, nil]
        # @return [Sketchup::Overlay, nil]
        def self.find_model_overlay(model = nil)
          m = model || (defined?(Sketchup) && Sketchup.respond_to?(:active_model) ? Sketchup.active_model : nil)
          return nil unless m && m.respond_to?(:overlays)

          found = nil
          m.overlays.each do |o|
            if o.respond_to?(:overlay_id) && o.overlay_id == OVERLAY_ID
              found = o
              break
            end
          end
          found
        end

        # Проверяет, активна ли рамка пропорций в указанной или текущей модели SketchUp
        # @param model [Sketchup::Model, nil]
        # @return [Boolean]
        def self.overlay_active?(model = nil)
          m = model || (defined?(Sketchup) && Sketchup.respond_to?(:active_model) ? Sketchup.active_model : nil)
          ov = find_model_overlay(m)
          return false unless ov && ov.respond_to?(:enabled?)

          begin
            return false unless ov.enabled?
            info = calculate_target_info(m)
            return false if info[:visible] == false
            true
          rescue StandardError
            false
          end
        end

        # Включает отображение рамки пропорций кадра
        # @param model [Sketchup::Model, nil]
        # @return [Boolean] true если успешно включено
        def self.enable(model = nil)
          m = model || (defined?(Sketchup) && Sketchup.respond_to?(:active_model) ? Sketchup.active_model : nil)
          return false unless m && m.respond_to?(:overlays)

          info = calculate_target_info(m)
          ov = find_model_overlay(m)
          unless ov
            ov = overlay_instance
            m.overlays.add(ov)
          end
          @active_overlay = ov

          ov.visible_cache        = info[:visible]
          ov.ratio_cache          = info[:ratio]
          ov.label_cache          = info[:label]
          ov.width_cache          = info[:render_w]
          ov.height_cache         = info[:render_h]
          ov.border_color_cache   = info[:border_color]
          ov.border_opacity_cache = info[:border_opacity]
          ov.mask_color_cache     = info[:mask_color]
          ov.mask_opacity_cache   = info[:mask_opacity]
          ov.line_width_cache     = info[:line_width] || 1

          if info[:visible] == false
            disable(m)
            return false
          end

          begin
            ov.enabled = true if ov.respond_to?(:enabled=)
          rescue StandardError
          end
          invalidate_view(m)
          true
        end

        # Отключает отображение рамки пропорций кадра
        # @param model [Sketchup::Model, nil]
        # @return [Boolean] true если успешно отключено
        def self.disable(model = nil)
          m = model || (defined?(Sketchup) && Sketchup.respond_to?(:active_model) ? Sketchup.active_model : nil)
          return false unless m && m.respond_to?(:overlays)

          ov = find_model_overlay(m) || overlay_instance
          ov.visible_cache = false if ov.respond_to?(:visible_cache=)
          begin
            ov.enabled = false if ov.respond_to?(:enabled=)
          rescue StandardError
          end
          invalidate_view(m)
          true
        end

        # Обновляет параметры рамки и видимость под активную сцену/шаблон
        # @param model [Sketchup::Model, nil]
        # @return [Hash] целевые параметры кадра
        def self.refresh(model = nil)
          m = model || (defined?(Sketchup) && Sketchup.respond_to?(:active_model) ? Sketchup.active_model : nil)
          info = calculate_target_info(m)
          ov = find_model_overlay(m) || overlay_instance
          if ov
            ov.visible_cache        = info[:visible]
            ov.ratio_cache          = info[:ratio]
            ov.label_cache          = info[:label]
            ov.width_cache          = info[:render_w]
            ov.height_cache         = info[:render_h]
            ov.border_color_cache   = info[:border_color]
            ov.border_opacity_cache = info[:border_opacity]
            ov.mask_color_cache     = info[:mask_color]
            ov.mask_opacity_cache   = info[:mask_opacity]
            ov.line_width_cache     = info[:line_width] || 1
          end

          if info[:visible] == false
            disable(m)
          else
            invalidate_view(m)
          end
          info
        end

        # Переключает отображение рамки пропорций кадра
        # @param model [Sketchup::Model, nil]
        # @return [Boolean] новое состояние (true - включено, false - выключено)
        def self.toggle(model = nil)
          if overlay_active?(model)
            disable(model)
            false
          else
            enable(model)
          end
        end

        # Обновляет параметры кадра и принудительно перерисовывает активный вид
        # @param new_settings [Hash]
        # @param model [Sketchup::Model, nil]
        # @return [void]
        def self.update_settings(new_settings, model = nil)
          return unless new_settings.is_a?(Hash)

          # Нормализация всех ключей в символы
          sym_settings = {}
          new_settings.each { |k, v| sym_settings[k.to_sym] = v }

          @current_settings = (@current_settings || {}).dup
          # Если передана новая пропорция кадра, удаляем старые ключи (строки и символы)
          if sym_settings.key?(:aspect_ratio) || sym_settings.key?(:image_aspect_ratio)
            @current_settings.delete("aspect_ratio")
            @current_settings.delete(:aspect_ratio)
            @current_settings.delete("image_aspect_ratio")
            @current_settings.delete(:image_aspect_ratio)
          end
          if sym_settings.key?(:template_key)
            @current_settings.delete("template_key")
            @current_settings.delete(:template_key)
          end
          @current_settings.merge!(sym_settings)

          m = model || (defined?(Sketchup) && Sketchup.respond_to?(:active_model) ? Sketchup.active_model : nil)
          info = calculate_target_info(m)
          ov = find_model_overlay(m)
          unless ov
            ov = overlay_instance
            m.overlays.add(ov) if m && m.respond_to?(:overlays)
          end
          if ov
            ov.visible_cache        = info[:visible]
            ov.ratio_cache          = info[:ratio]
            ov.label_cache          = info[:label]
            ov.width_cache          = info[:render_w]
            ov.height_cache         = info[:render_h]
            ov.border_color_cache   = info[:border_color]
            ov.border_opacity_cache = info[:border_opacity]
            ov.mask_color_cache     = info[:mask_color]
            ov.mask_opacity_cache   = info[:mask_opacity]
            ov.line_width_cache     = info[:line_width] || 1
            if info[:visible] == false
              ov.enabled = false if ov.respond_to?(:enabled=)
              invalidate_view(m)
              return
            end
            ov.enabled = true if ov.respond_to?(:enabled=)
          end
          invalidate_view(m)
        end

        # Безопасный вызов перерисовки окна просмотра (мгновенный refresh + invalidate)
        # @param model [Sketchup::Model, nil]
        # @return [void]
        def self.invalidate_view(model = nil)
          m = model || (defined?(Sketchup) && Sketchup.respond_to?(:active_model) ? Sketchup.active_model : nil)
          return unless m && m.respond_to?(:active_view)

          v = m.active_view
          if v
            v.invalidate if v.respond_to?(:invalidate)
            v.refresh if v.respond_to?(:refresh)
            if defined?(UI) && UI.respond_to?(:start_timer)
              UI.start_timer(0, false) do
                begin
                  v.invalidate if v.respond_to?(:invalidate)
                  v.refresh if v.respond_to?(:refresh)
                rescue StandardError
                end
              end
            end
          end
        end

        # Синхронизация оверлея при открытии модели: сброс старых настроек сессии
        # и актуализация рамки кадра (4:3 если не сохранено иное)
        # @param model [Sketchup::Model, nil]
        # @param project_data [Model::ProjectData, nil]
        # @return [void]
        def self.on_model_opened(model = nil, project_data = nil)
          m = model || (defined?(Sketchup) && Sketchup.respond_to?(:active_model) ? Sketchup.active_model : nil)
          @current_settings = nil

          pdata = project_data
          if pdata.nil? && m && defined?(Model::SessionStore)
            pdata = Model::SessionStore.data(m)
          end

          info = calculate_target_info(m, pdata ? pdata.pdf_settings : nil)
          ov = find_model_overlay(m) || overlay_instance
          if ov
            ov.visible_cache        = info[:visible]
            ov.ratio_cache          = info[:ratio]
            ov.label_cache          = info[:label]
            ov.width_cache          = info[:render_w]
            ov.height_cache         = info[:render_h]
            ov.border_color_cache   = info[:border_color]
            ov.border_opacity_cache = info[:border_opacity]
            ov.mask_color_cache     = info[:mask_color]
            ov.mask_opacity_cache   = info[:mask_opacity]
          end

          is_active = overlay_active?(m)
          should_show = pdata && pdata.pdf_settings && pdata.pdf_settings[:show_aspect_overlay] && info[:visible] != false
          if should_show
            enable(m)
          elsif is_active || info[:visible] == false
            disable(m) if is_active
            invalidate_view(m)
          end
        end
      end
    end
  end
end
