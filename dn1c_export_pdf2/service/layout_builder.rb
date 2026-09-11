# frozen_string_literal: true

require "fileutils"
require_relative "render_service"
require_relative "info_line_resolver"
require_relative "font_service"

module DN1Code
  module ExportPdf2
    module Service
      # Экспорт PDF через SketchUp LayOut Ruby API.
      #
      # Страницы строятся по той же модульной сетке (custom_layouts из layout.yaml),
      # что и эталонный Prawn-движок (Controller::PageBase#render_modular_page):
      #   image_4_3 — PNG-рендер сцены (тот же RenderService, что и в Prawn),
      #   header    — многострочный заголовок с разделителями,
      #   slot_1..4 — информационные колонки,
      #   footer    — нижний колонтитул в 3 колонки,
      #   stamp     — повернутый полупрозрачный штамп.
      #
      # Все внутренние вычисления ведутся в пунктах (pt), как в Prawn;
      # в координаты LayOut (дюймы, начало — левый нижний угол) переводим
      # только при создании сущностей (PT_PER_INCH).
      module LayoutBuilder
        extend self

        PAGE_SIZES_INCHES = {
          "A4"     => { w: 11.6929, h: 8.2677 },
          "A3"     => { w: 16.5354, h: 11.6929 },
          "A2"     => { w: 23.3858, h: 16.5354 },
          "LETTER" => { w: 11.0,    h: 8.5 }
        }.freeze

        PT_PER_INCH = 72.0

        # Цвета оформления — зеркально PageBase (Prawn)
        SEP_COLOR         = "CBD5E1" # разделительные линии
        FOOTER_COLOR      = "475569" # текст подвала
        SLOT_TEXT_COLOR   = "334155" # строки слотов
        HEADER_TEXT_COLOR = "0F172A" # заголовок по умолчанию
        CUSTOM_TEXT_COLOR = "1E293B" # custom_text слотов
        HEADER_SEP_COLOR  = "CBD5E1" # разделитель " | " в строках заголовка

        # Проверка доступности LayOut Ruby API в текущем окружении
        def available?
          defined?(::Layout) && defined?(::Layout::Document)
        end

        # Основной метод экспорта через LayOut API
        def export(controller, custom_output_path = nil, &progress_block)
          unless available?
            raise "LayOut Ruby API не доступен в текущей версии SketchUp.\n" \
                  "Убедитесь, что используется SketchUp Pro с установленным модулем LayOut."
          end

          project_data = controller.project_data
          model        = controller.model
          settings     = project_data.pdf_settings

          enabled_scenes = project_data.scenes.select { |s| s.enabled && s.page_type != :skip }
          if enabled_scenes.empty?
            raise "Не выбрано ни одной сцены для экспорта в LayOut / PDF!"
          end

          pdf_path = custom_output_path || controller.send(:resolve_default_pdf_path)
          FileUtils.mkdir_p(File.dirname(pdf_path))

          temp_images = []
          begin
            total_pages = enabled_scenes.size
            progress_block&.call(0, total_pages, "Инициализация документа LayOut...")

            # Установка DIN Condensed в систему (визуальное совпадение с Prawn)
            font_family = FontService.layout_font_family

            # 1. Создание нового документа LayOut
            doc = ::Layout::Document.new

            # 2. Настройка параметров листа
            page_dim  = get_page_dimensions(settings)
            page_w_in = page_dim[:w]
            page_h_in = page_dim[:h]
            margin_in = resolve_margin_inches(settings)

            if doc.respond_to?(:page_info) && doc.page_info
              page_info = doc.page_info
              page_info.width  = page_w_in if page_info.respond_to?(:width=)
              page_info.height = page_h_in if page_info.respond_to?(:height=)
              page_info.left_margin   = margin_in if page_info.respond_to?(:left_margin=)
              page_info.right_margin  = margin_in if page_info.respond_to?(:right_margin=)
              page_info.top_margin    = margin_in if page_info.respond_to?(:top_margin=)
              page_info.bottom_margin = margin_in if page_info.respond_to?(:bottom_margin=)
              page_info.show_margins  = false if page_info.respond_to?(:show_margins=)
            end

            layer = doc.layers.first rescue nil
            layer ||= doc.layers.add("DN1C_Export") rescue nil

            ctx = build_context(project_data, model, font_family)
            ctx[:page_w_pt] = in2pt(page_w_in)
            ctx[:page_h_pt] = in2pt(page_h_in)

            # 3. Построение страниц по модульной сетке (как в Prawn)
            enabled_scenes.each_with_index do |scene_item, idx|
              page_index = idx + 1
              progress_block&.call(page_index, total_pages, "Построение страницы LayOut #{page_index}/#{total_pages}: #{scene_item.name}")

              page = if idx.zero?
                       (doc.pages.respond_to?(:initial) ? doc.pages.initial : doc.pages.first) || doc.pages.add(scene_item.name)
                     else
                       doc.pages.add(scene_item.name)
                     end
              page.name = scene_item.name if page.respond_to?(:name=)

              render_modular_page(doc, page, layer, scene_item, page_index, total_pages, page_w_in, page_h_in, margin_in, ctx, temp_images)
            end

            progress_block&.call(total_pages, total_pages, "Экспорт документа LayOut в PDF...")

            # 4. Экспорт в PDF
            doc.export(pdf_path)

            # 5. Сохранение файла .layout если включено
            if settings[:save_layout_file]
              layout_path = pdf_path.sub(/\.pdf$/i, ".layout")
              doc.save(layout_path) rescue nil
            end

            # 6. Резервная копия .skp
            if settings[:save_skp_backup] && model && model.respond_to?(:path) && !model.path.empty?
              controller.send(:save_skp_backup)
            end

            # 7. Сохранение атрибутов и YAML (история правок формируется только пользователем)
            project_data.save_auto(model) if model

            progress_block&.call(total_pages, total_pages, "Экспорт через LayOut API успешно завершен!")

            # 8. Открытие PDF файла (openURL требует URL-схему file:///)
            if settings[:auto_open_pdf] && defined?(UI) && UI.respond_to?(:openURL)
              UI.openURL("file:///" + pdf_path.to_s.tr("\\", "/"))
            end

            pdf_path
          ensure
            # Удаление временных PNG после экспорта
            RenderService.safe_cleanup_files(temp_images)
          end
        end

        private

        # ------------------------------------------------------------------
        # Единицы измерения и геометрия
        # ------------------------------------------------------------------

        def in2pt(value)
          value.to_f * PT_PER_INCH
        end

        def pt2in(value)
          value.to_f / PT_PER_INCH
        end

        # Определение физических размеров листа в дюймах
        def get_page_dimensions(settings)
          size_key = (settings[:page_size] || "A4").to_s.upcase
          base = PAGE_SIZES_INCHES[size_key] || PAGE_SIZES_INCHES["A4"]

          is_portrait = settings[:page_layout].to_s.downcase == "portrait"
          w = is_portrait ? [base[:w], base[:h]].min : [base[:w], base[:h]].max
          h = is_portrait ? [base[:w], base[:h]].max : [base[:w], base[:h]].min

          { w: w, h: h }
        end

        # Поля страницы в дюймах (логика идентична Prawn: margin_mm -> pt -> in)
        def resolve_margin_inches(settings)
          if settings.key?(:margin_mm) && !settings[:margin_mm].nil?
            settings[:margin_mm].to_f * PT_PER_INCH / 25.4 / PT_PER_INCH
          elsif settings.key?("margin_mm") && !settings["margin_mm"].nil?
            settings["margin_mm"].to_f * PT_PER_INCH / 25.4 / PT_PER_INCH
          elsif settings.key?(:margin) && !settings[:margin].nil?
            settings[:margin].to_f / PT_PER_INCH
          elsif settings.key?("margin") && !settings["margin"].nil?
            settings["margin"].to_f / PT_PER_INCH
          else
            15.0 / PT_PER_INCH
          end
        end

        # Контекст рендера (общие данные для всех страниц)
        def build_context(project_data, model, font_family)
          settings = project_data.pdf_settings || {}
          {
            settings:      settings,
            info:          project_data.project_info || {},
            workflow:      (project_data.respond_to?(:workflow) ? project_data.workflow : nil) || {},
            project_data:  project_data,
            model:         model,
            font:          font_family,
            aspect_cache:  {},
            primary_color: settings[:primary_color] || "005EB0",
            secondary_color: settings[:secondary_color] || "64748B",
            stamp_color:   settings[:stamp_color] || "D32F2F"
          }
        end

        # Контекст для InfoLineResolver
        def resolver_context(ctx, scene_item, page_index, total_pages)
          {
            info:         ctx[:info],
            workflow:     ctx[:workflow],
            project_data: ctx[:project_data],
            scene_item:   scene_item,
            page_index:   page_index,
            total_pages:  total_pages
          }
        end

        # ------------------------------------------------------------------
        # Доступ к конфигурации модульной сетки (зеркало PageBase)
        # ------------------------------------------------------------------

        def get_page_cfg(ctx, pt)
          custom = ctx[:settings][:custom_layouts] || {}
          page_cfg = custom[pt] || custom[pt.to_s] || {}
          page_cfg.is_a?(Hash) ? page_cfg : {}
        end

        def get_block_config(ctx, pt, block_id)
          page_cfg = get_page_cfg(ctx, pt)
          cfg = page_cfg[block_id] || page_cfg[block_id.to_s] || {}
          cfg.is_a?(Hash) ? cfg : {}
        end

        def block_visible?(page_cfg, block_id)
          cfg = page_cfg[block_id] || page_cfg[block_id.to_s] || {}
          return true if cfg.empty?
          return false if cfg[:visible] == false || cfg["visible"] == false

          true
        end

        # Расчет абсолютных координат блока в пунктах (зеркало PageBase#get_block_box).
        # content: { left:, top:, w:, h: } — рабочая область листа в pt (top = верхняя грань).
        def get_block_box(content, page_cfg, block_id, def_x, def_y, def_w, def_h)
          cfg = page_cfg[block_id] || page_cfg[block_id.to_s] || {}

          x_pct = (cfg[:x] || cfg["x"] || def_x).to_f
          y_pct = (cfg[:y] || cfg["y"] || def_y).to_f
          w_pct = (cfg[:w] || cfg["w"] || def_w).to_f
          h_pct = (cfg[:h] || cfg["h"] || def_h).to_f

          # Высота заголовка задана жестко 30%, от верхнего края листа
          if block_id.to_s == "header"
            y_pct = 0.0
            h_pct = 30.0
          end

          # Подвал страницы всегда привязан к нижнему краю листа
          if block_id.to_s == "footer"
            h_pct = 4.0 if h_pct <= 0.0
            y_pct = 100.0 - h_pct
          end

          visible = cfg.key?(:visible) ? cfg[:visible] : (cfg.key?("visible") ? cfg["visible"] : true)
          align   = (cfg[:align] || cfg["align"] || "left").to_s.to_sym
          valign  = (cfg[:valign] || cfg["valign"] || (block_id.to_s == "footer" ? "bottom" : "top")).to_s.to_sym

          {
            x:       content[:left] + (content[:w] * (x_pct / 100.0)),
            y:       content[:top] - (content[:h] * (y_pct / 100.0)),
            width:   content[:w] * (w_pct / 100.0),
            height:  content[:h] * (h_pct / 100.0),
            visible: visible,
            align:   align,
            valign:  valign
          }
        end

        # ------------------------------------------------------------------
        # Цвета
        # ------------------------------------------------------------------

        def hex_to_rgb(hex, fallback = [51, 65, 85])
          raw = hex.to_s.strip.sub(/^#/, "")
          return fallback unless raw.match?(/\A[0-9a-fA-F]{6}\z/)

          [raw[0, 2].to_i(16), raw[2, 2].to_i(16), raw[4, 2].to_i(16)]
        end

        def layout_color(hex, fallback = [51, 65, 85])
          r, g, b = hex_to_rgb(hex, fallback)
          ::Sketchup::Color.new(r, g, b)
        end

        # LayOut не поддерживает alpha в цвете текста — эмулируем прозрачность
        # Prawn (transparent(opacity)) смешиванием с белой бумагой
        def tinted_rgb(hex, opacity, fallback = [51, 65, 85])
          r, g, b = hex_to_rgb(hex, fallback)
          k = opacity.to_f.clamp(0.0, 1.0)
          [((255.0 * (1 - k)) + (r * k)).round, ((255.0 * (1 - k)) + (g * k)).round, ((255.0 * (1 - k)) + (b * k)).round]
        end

        # ------------------------------------------------------------------
        # Примитивы LayOut
        # ------------------------------------------------------------------

        def style_alignment(align)
          case align
          when :right  then ::Layout::Style::ALIGN_RIGHT
          when :center then ::Layout::Style::ALIGN_CENTER
          else ::Layout::Style::ALIGN_LEFT
          end
        end

        def style_anchor(anchor)
          case anchor
          when :bottom then ::Layout::Style::ANCHOR_BOTTOM
          when :center then ::Layout::Style::ANCHOR_CENTER
          else ::Layout::Style::ANCHOR_TOP
          end
        end

        def apply_text_style!(style, opts)
          style.font_family = opts[:font] if opts[:font] && style.respond_to?(:font_family=)
          style.font_size   = opts[:size].to_f if style.respond_to?(:font_size=)
          if opts[:color_obj].is_a?(::Sketchup::Color)
            style.text_color = opts[:color_obj] if style.respond_to?(:text_color=)
          elsif opts[:color]
            style.text_color = layout_color(opts[:color]) if style.respond_to?(:text_color=)
          end
          style.text_bold = opts[:bold] ? true : false if style.respond_to?(:text_bold=)
          style.text_alignment = style_alignment(opts[:align]) if style.respond_to?(:text_alignment=)
          style.text_anchor = style_anchor(opts[:anchor]) if style.respond_to?(:text_anchor=)
        rescue StandardError
          nil
        end

        # Преобразование Y: внутренние координаты — как в Prawn (y вверх, от низа листа),
        # у LayOut бумажные координаты — y вниз, от верхнего левого угла листа.
        def lay_y(ctx, y_pt)
          ctx[:page_h_pt] - y_pt.to_f
        end

        def make_bounds_pt(ctx, x_pt, y_top_pt, w_pt, h_pt)
          raise ArgumentError, "zero size bounds" if w_pt <= 0 || h_pt <= 0

          # y_top_pt — верхняя грань блока в системе Prawn; в LayOut это верх рамки (y вниз)
          ::Geom::Bounds2d.new(pt2in(x_pt), pt2in(lay_y(ctx, y_top_pt)), pt2in(w_pt), pt2in(h_pt))
        end

        # Ограниченный текстовый блок (box — координаты в системе Prawn, y — верхняя грань, в pt)
        def add_bounded_text(ctx, doc, page, layer, text, box, opts = {})
          return if text.to_s.empty?

          text_ent = ::Layout::FormattedText.new(text.to_s, make_bounds_pt(ctx, box[:x], box[:y], box[:width], box[:height]))
          text_ent.grow_mode = ::Layout::FormattedText::GROW_MODE_BOUNDED
          style = text_ent.style(0)
          apply_text_style!(style, opts)
          text_ent.apply_style(style)
          doc.add_entity(text_ent, layer, page)
          text_ent
        rescue StandardError => e
          warn "Ошибка добавления текста LayOut: #{e.message}"
          nil
        end

        # RTF-escaped строка (кириллица через \uNNNN?)
        def rtf_escape(text)
          out = +""
          text.to_s.each_char do |ch|
            case ch
            when "\\" then out << "\\\\"
            when "{"  then out << "\\{"
            when "}"  then out << "\\}"
            else
              code = ch.ord
              if code < 128
                out << ch
              else
                signed = code > 32_767 ? code - 65_536 : code
                out << "\\u#{signed}?"
              end
            end
          end
          out
        end

        # Многофрагментная строка заголовка через RTF (разные цвета/размеры как в Prawn formatted_text_box)
        # fragments: [{ text:, size:, color:, bold: }]
        def add_rtf_text(ctx, doc, page, layer, fragments, box, opts = {})
          runs = []
          colors = [[15, 23, 42]]
          fragments.each do |f|
            next if f[:text].to_s.empty?

            rgb = hex_to_rgb(f[:color] || HEADER_TEXT_COLOR, [15, 23, 42])
            idx = colors.index(rgb)
            if idx.nil?
              colors << rgb
              idx = colors.size - 1
            end
            half = [(f[:size].to_f * 2).round, 2].max
            run = +"\\cf#{idx}\\fs#{half} "
            run << "\\b " if f[:bold]
            run << rtf_escape(f[:text])
            run << "\\b0 " if f[:bold]
            runs << run
          end
          return if runs.empty?

          colortbl = colors.drop(1).map { |rgb| "\\red#{rgb[0]}\\green#{rgb[1]}\\blue#{rgb[2]};" }.join
          align_code = case opts[:align]
                       when :right then "qr"
                       when :center then "qc"
                       else "ql"
                       end
          font = opts[:font] || "Arial"
          rtf = "{\\rtf1\\ansi\\deff0{\\fonttbl{\\f0 #{font};}}{\\colortbl;#{colortbl}}" \
                "\\pard\\#{align_code}\\f0 #{runs.join}\\par}"

          text_ent = ::Layout::FormattedText.new(" ", make_bounds_pt(ctx, box[:x], box[:y], box[:width], box[:height]))
          text_ent.grow_mode = ::Layout::FormattedText::GROW_MODE_BOUNDED
          text_ent.rtf = rtf
          doc.add_entity(text_ent, layer, page)
          text_ent
        rescue StandardError => e
          warn "Ошибка добавления RTF текста LayOut: #{e.message}"
          nil
        end

        # Горизонтальная разделительная линия (тонкая залитая плашка)
        def add_hline(ctx, doc, page, layer, x_pt, y_center_pt, w_pt, color_hex = SEP_COLOR, thickness_pt = 0.7)
          return if w_pt <= 0 || thickness_pt <= 0

          # верхняя грань плашки в системе Prawn = центр + половина толщины
          bounds = make_bounds_pt(ctx, x_pt, y_center_pt + thickness_pt / 2.0, w_pt, thickness_pt)
          rect = ::Layout::Rectangle.new(bounds)
          style = rect.style
          if style.respond_to?(:solid_filled=)
            style.solid_filled = true
            style.fill_color = layout_color(color_hex) if style.respond_to?(:fill_color=)
          end
          style.stroked = false if style.respond_to?(:stroked=)
          rect.style = style
          doc.add_entity(rect, layer, page)
          rect
        rescue StandardError => e
          warn "Ошибка добавления линии LayOut: #{e.message}"
          nil
        end

        # Повернутый текст (штамп): привязка в точке + поворот вокруг нее.
        # Prawn rotate: положительный угол — против часовой стрелки (система y вверх);
        # в LayOut y направлен вниз, поэтому знак угла инвертируется.
        def add_rotated_text(ctx, doc, page, layer, text, x_pt, y_pt, size_pt, color_obj, bold, angle_deg)
          return if text.to_s.empty?

          anchor_pt = ::Geom::Point2d.new(pt2in(x_pt), pt2in(lay_y(ctx, y_pt)))
          text_ent = ::Layout::FormattedText.new(text.to_s, anchor_pt, ::Layout::FormattedText::ANCHOR_TYPE_TOP_LEFT)
          style = text_ent.style(0)
          apply_text_style!(style, size: size_pt, color_obj: color_obj, bold: bold, font: ctx[:font])
          text_ent.apply_style(style)
          doc.add_entity(text_ent, layer, page)
          text_ent.transform!(::Geom::Transformation2d.rotation(anchor_pt, -angle_deg * Math::PI / 180.0))
          text_ent
        rescue StandardError => e
          warn "Ошибка добавления штампа LayOut: #{e.message}"
          nil
        end

        # ------------------------------------------------------------------
        # Рендер страницы по модульной сетке (зеркало PageBase#render_modular_page)
        # ------------------------------------------------------------------

        def render_modular_page(doc, page, layer, scene_item, page_index, total_pages, page_w_in, page_h_in, margin_in, ctx, temp_images)
          pt = (scene_item.page_type || :general).to_sym
          page_cfg = get_page_cfg(ctx, pt)

          margin_pt = in2pt(margin_in)
          content = {
            left: margin_pt,
            top:  in2pt(page_h_in) - margin_pt,
            w:    in2pt(page_w_in) - (margin_pt * 2),
            h:    in2pt(page_h_in) - (margin_pt * 2)
          }

          rctx = resolver_context(ctx, scene_item, page_index, total_pages)

          # 1. Изображение чертежа/модели в пропорциях (3:2, 4:3, 16:9) и масштабом ниже всего текста
          if block_visible?(page_cfg, :image_4_3)
            img_cfg = get_block_config(ctx, pt, :image_4_3)
            render_image_block(doc, page, layer, scene_item, content, img_cfg, ctx, temp_images, pt)
          end

          # 2. Верхний заголовок (Header)
          if block_visible?(page_cfg, :header)
            hdr_box = get_block_box(content, page_cfg, :header, 0.0, 0.0, 100.0, 30.0)
            render_modular_header(doc, page, layer, hdr_box, page_cfg, ctx, rctx)
          end

          # 3. 4 информационных слота поверх картинки
          render_modular_slots(doc, page, layer, content, page_cfg, pt, ctx, rctx)

          # 4. Нижний колонтитул (Footer)
          if block_visible?(page_cfg, :footer)
            ftr_cfg = get_block_config(ctx, pt, :footer)
            ftr_box = get_block_box(content, page_cfg, :footer, 0.0, 94.0, 100.0, 6.0)
            render_modular_footer(doc, page, layer, ftr_box, ftr_cfg, ctx, rctx)
          end

          # 5. Штамп/водяной знак
          render_stamp(doc, page, layer, content, ctx)
        end

        # ------------------------------------------------------------------
        # Блок изображения (зеркало PageBase image_4_3 + draw_scene_image)
        # ------------------------------------------------------------------

        def render_image_block(doc, page, layer, scene_item, content, img_cfg, ctx, temp_images, pt)
          ratio_str = (img_cfg[:aspect_ratio] || img_cfg["aspect_ratio"] || "4:3").to_s.strip
          target_ratio = case ratio_str
                         when "3:2"  then 3.0 / 2.0
                         when "16:9" then 16.0 / 9.0
                         else 4.0 / 3.0
                         end

          raw_scale = (img_cfg[:scale_pct] || img_cfg["scale_pct"] || 100).to_f
          raw_scale = 100.0 if raw_scale <= 0.0 || raw_scale > 100.0
          scale_factor = raw_scale / 100.0

          avail_w = content[:w] * scale_factor
          avail_h = content[:h] * scale_factor

          cur_ratio = avail_w / avail_h
          if cur_ratio > target_ratio
            img_h = avail_h
            img_w = avail_h * target_ratio
          else
            img_w = avail_w
            img_h = avail_w / target_ratio
          end

          # Центрирование на странице
          img_x = content[:left] + ((content[:w] - img_w) / 2.0)
          img_y = content[:top] - ((content[:h] - img_h) / 2.0)

          # Источник изображения: оверрайд сцены либо PNG-рендер тем же RenderService, что и Prawn
          image_path = nil
          if scene_item.respond_to?(:image_override) && scene_item.image_override && File.exist?(scene_item.image_override.to_s)
            image_path = scene_item.image_override.to_s
          end

          unless image_path
            render_opts = {
              image_width:        ctx[:settings][:image_width] || 2400,
              scale_factor:       ctx[:settings][:scale_factor] || 2.0,
              antialias:          ctx[:settings].fetch(:antialias, true),
              aspect_ratio:       target_ratio,
              image_aspect_ratio: ctx[:settings][:image_aspect_ratio]
            }
            if defined?(OverlayService)
              scene_aspect_info = ctx[:aspect_cache][pt]
              unless scene_aspect_info
                scene_aspect_info = OverlayService.calculate_target_info(ctx[:model], { template_key: pt }) rescue nil
                ctx[:aspect_cache][pt] = scene_aspect_info
              end
              render_opts[:aspect_ratio] = scene_aspect_info[:ratio] if scene_aspect_info && scene_aspect_info[:ratio]
            end
            image_path = RenderService.render_scene_temp(ctx[:model], scene_item.scene_ref, render_opts)
            temp_images << image_path
          end
          return unless image_path && File.exist?(image_path)

          # Prawn (fit: [w, h], at: [x, y]) вписывает изображение с сохранением пропорций
          # от левого верхнего угла блока — повторяем то же для Layout::Image
          draw_w, draw_h = fit_image_size(image_path, img_w, img_h)
          return unless draw_w > 0 && draw_h > 0

          bounds = ::Geom::Bounds2d.new(pt2in(img_x), pt2in(lay_y(ctx, img_y)), pt2in(draw_w), pt2in(draw_h))
          img = ::Layout::Image.new(image_path, bounds)
          doc.add_entity(img, layer, page)
        rescue StandardError => e
          warn "Ошибка вставки изображения LayOut: #{e.message}"
        end

        # Вписывает изображение в блок с сохранением пропорций (аналог Prawn fit:)
        def fit_image_size(image_path, box_w_pt, box_h_pt)
          px = png_pixel_size(image_path)
          return [box_w_pt, box_h_pt] unless px

          px_w, px_h = px
          return [box_w_pt, box_h_pt] unless px_w.to_i > 0 && px_h.to_i > 0

          k = [(box_w_pt / px_w.to_f), (box_h_pt / px_h.to_f)].min
          [px_w * k, px_h * k]
        end

        # Чтение размеров PNG из заголовка IHDR
        def png_pixel_size(path)
          File.open(path, "rb") do |f|
            data = f.read(24)
            return nil unless data && data.bytesize >= 24 && data[0, 8] == "\x89PNG\r\n\x1a\n".b

            [data[16, 4].unpack1("N"), data[20, 4].unpack1("N")]
          end
        rescue StandardError
          nil
        end

        # ------------------------------------------------------------------
        # Верхний заголовок (зеркало PageBase#render_modular_header)
        # ------------------------------------------------------------------

        def render_modular_header(doc, page, layer, hdr_box, page_cfg, ctx, rctx)
          cfg = page_cfg[:header] || page_cfg["header"] || {}
          content_type = (cfg[:content] || cfg["content"] || "header_title").to_s
          valign = (cfg[:valign] || cfg["valign"] || "top").to_s.to_sym
          font_size = (cfg[:font_size] || cfg["font_size"] || 11.0).to_f
          lines = cfg[:lines] || cfg["lines"]
          if lines.nil?
            lines = ["furniture_name", "place_address", "customer_or_company", "scene_name", "scene_description"]
          end
          return if lines.is_a?(Array) && lines.empty?

          if content_type == "custom_text"
            txt = (cfg[:custom_text] || cfg["custom_text"] || "").to_s
            add_bounded_text(ctx, doc, page, layer, txt,
                             { x: hdr_box[:x], y: hdr_box[:y], width: hdr_box[:width], height: hdr_box[:height] },
                             size: font_size, color: HEADER_TEXT_COLOR, bold: true, align: :center, anchor: valign, font: ctx[:font])
            return
          end

          line_rows       = cfg[:line_rows] || cfg["line_rows"] || {}
          line_font_sizes = cfg[:line_font_sizes] || cfg["line_font_sizes"] || {}
          line_colors     = cfg[:line_colors] || cfg["line_colors"] || {}

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

              val = InfoLineResolver.resolve_header_item(rctx, k_str)
              if val && !val.to_s.strip.empty?
                item_sz = (line_font_sizes[k_str] || line_font_sizes[k.to_sym] || font_size).to_f
                item_sz = font_size if item_sz <= 0.0

                raw_col = (line_colors[k_str] || line_colors[k.to_sym] || HEADER_TEXT_COLOR).to_s.strip
                clean_col = raw_col.sub(/^#/, "")
                clean_col = HEADER_TEXT_COLOR if clean_col.empty?

                grouped_rows[row_num] << {
                  key:   k_str,
                  text:  val.to_s.strip,
                  size:  item_sz,
                  color: clean_col
                }
              end
            end
          end

          active_rows = [1, 2, 3, 4, 5].select { |r| grouped_rows[r] && !grouped_rows[r].empty? }
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
          active_rows.each { |r| scaled_row_heights[r] = row_heights[r] * scale }
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

          active_rows.each_with_index do |r, idx|
            items = grouped_rows[r]
            r_h = scaled_row_heights[r]

            fragments = []
            items.each_with_index do |it, i|
              if i > 0
                fragments << {
                  text:  " | ",
                  size:  [it[:size], items[i - 1][:size]].min * scale,
                  color: HEADER_SEP_COLOR,
                  bold:  false
                }
              end
              fragments << {
                text:  it[:text],
                size:  it[:size] * scale,
                color: it[:color],
                bold:  true
              }
            end

            add_rtf_text(ctx, doc, page, layer, fragments,
                         { x: hdr_box[:x] + 4, y: cur_y, width: hdr_box[:width] - 8, height: r_h },
                         align: align, font: ctx[:font])
            cur_y -= r_h

            if idx < active_rows.size - 1
              sep_y = cur_y - (scaled_item_gap / 2.0)
              line_w = [hdr_box[:width] * 0.45, 130.0].min
              lx = hdr_box[:x] + (hdr_box[:width] - line_w) / 2.0
              add_hline(ctx, doc, page, layer, lx, sep_y, line_w, SEP_COLOR, 0.5)
              cur_y -= scaled_item_gap
            end
          end
        end

        # ------------------------------------------------------------------
        # Слоты (зеркало PageBase#render_modular_page, блок 3)
        # ------------------------------------------------------------------

        def render_modular_slots(doc, page, layer, content, page_cfg, pt, ctx, rctx)
          slot_coords = {
            slot_1: [0.0, 0.0, 25.0, 58.0],
            slot_2: [0.0, 58.0, 25.0, 36.0],
            slot_3: [75.0, 0.0, 25.0, 58.0],
            slot_4: [75.0, 58.0, 25.0, 36.0]
          }

          s1_vis = block_visible?(page_cfg, :slot_1)
          s1_cfg = s1_vis ? get_block_config(ctx, pt, :slot_1) : nil
          s1_lines = s1_cfg ? (s1_cfg[:lines] || s1_cfg["lines"]) : nil
          handled_slots = []

          s1_content = s1_cfg ? (s1_cfg[:content] || s1_cfg["content"]).to_s : ""
          is_info_lines = s1_content == "info_lines" || (s1_content != "custom_text" && s1_content != "project_card" && s1_content != "customer_card" && s1_content != "workflow_status" && s1_content != "history_table")

          if s1_vis && s1_cfg && s1_lines.is_a?(Array) && !s1_lines.empty? && is_info_lines
            handled_slots = [:slot_1, :slot_2, :slot_3, :slot_4]
            line_aligns = s1_cfg[:line_aligns] || s1_cfg["line_aligns"] || {}
            line_valigns = s1_cfg[:line_valigns] || s1_cfg["line_valigns"] || {}

            s1_w = (s1_cfg[:w] || s1_cfg["w"] || 25.0).to_f
            s3_cfg = get_block_config(ctx, pt, :slot_3)
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
              slot_box = {
                x:      content[:left] + (content[:w] * (coords[0] / 100.0)),
                y:      content[:top] - (content[:h] * (coords[1] / 100.0)),
                width:  content[:w] * (coords[2] / 100.0),
                height: content[:h] * (coords[3] / 100.0),
                visible: true,
                align:   z_data[:align].to_sym,
                valign:  z_data[:valign]
              }

              q_cfg = s1_cfg.dup
              q_cfg[:content] = "info_lines"
              q_cfg[:lines] = q_lines
              q_cfg[:align] = z_data[:align]
              q_cfg[:valign] = z_data[:valign]

              render_modular_slot_card(doc, page, layer, slot_box, "info_lines", q_cfg, opacity, target_slot, ctx, rctx)
            end
          end

          # Отрисовка остальных слотов, если они видимы и не были обработаны
          slot_coords.each do |slot_id, defs|
            next if handled_slots.include?(slot_id)
            next unless block_visible?(page_cfg, slot_id)

            cfg = get_block_config(ctx, pt, slot_id)
            lines = cfg[:lines] || cfg["lines"]
            content_type = (cfg[:content] || cfg["content"]).to_s
            content_type = "info_lines" if (content_type.empty? || content_type == "none") && lines.is_a?(Array) && !lines.empty?
            next if content_type.empty? || content_type == "none"

            slot_box = get_block_box(content, page_cfg, slot_id, defs[0], defs[1], defs[2], defs[3])
            opacity = (cfg[:opacity] || cfg["opacity"] || 0.90).to_f
            render_modular_slot_card(doc, page, layer, slot_box, content_type, cfg, opacity, slot_id, ctx, rctx)
          end
        end

        # Карточка слота (зеркало PageBase#render_modular_slot_card)
        def render_modular_slot_card(doc, page, layer, slot_box, content_type, cfg, _opacity, slot_id, ctx, rctx)
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
          lines = cfg[:lines] || cfg["lines"]
          in_bottom_y = slot_box[:y] - slot_box[:height] + pad

          if content_type == "custom_text"
            txt = (cfg[:custom_text] || cfg["custom_text"] || "").to_s
            txt_h = estimate_text_height(txt, font_size, in_w)
            txt_box_h = [txt_h + 2.0, in_h].min
            if valign == :bottom
              target_top_y = [in_bottom_y + txt_box_h, in_y].min
              add_bounded_text(ctx, doc, page, layer, txt, { x: in_x, y: target_top_y, width: in_w, height: txt_box_h },
                               size: font_size, color: CUSTOM_TEXT_COLOR, align: align, anchor: :bottom, font: ctx[:font])
            elsif valign == :center
              offset = [(in_h - txt_box_h) / 2.0, 0.0].max
              target_top_y = in_y - offset
              add_bounded_text(ctx, doc, page, layer, txt, { x: in_x, y: target_top_y, width: in_w, height: txt_box_h },
                               size: font_size, color: CUSTOM_TEXT_COLOR, align: align, anchor: :top, font: ctx[:font])
            else
              add_bounded_text(ctx, doc, page, layer, txt, { x: in_x, y: in_y, width: in_w, height: in_h },
                               size: font_size, color: CUSTOM_TEXT_COLOR, align: align, anchor: valign, font: ctx[:font])
            end
            return
          end

          items = []
          line_aligns = cfg[:line_aligns] || cfg["line_aligns"] || {}
          line_sizes = cfg[:line_font_sizes] || cfg["line_font_sizes"] || {}
          line_colors = cfg[:line_colors] || cfg["line_colors"] || {}

          if lines && lines.is_a?(Array)
            lines.each do |line_key|
              line_text = InfoLineResolver.resolve(rctx, line_key)
              next if line_text.nil? || line_text.to_s.empty?

              k_str = line_key.to_s
              k_sym = line_key.to_sym rescue nil

              it_sz = (line_sizes[k_str] || (k_sym && line_sizes[k_sym]) || font_size).to_f
              it_sz = font_size if it_sz <= 0.0

              raw_col = (line_colors[k_str] || (k_sym && line_colors[k_sym]) || SLOT_TEXT_COLOR).to_s.strip
              it_col = raw_col.sub(/^#/, "")
              it_col = SLOT_TEXT_COLOR if it_col.empty?

              it_align = (line_aligns[k_str] || (k_sym && line_aligns[k_sym]) || align).to_s.to_sym
              it_align = align unless [:left, :right, :center].include?(it_align)

              items << {
                key:   k_str,
                text:  line_text,
                size:  it_sz,
                color: it_col,
                align: it_align
              }
            end
          else
            raw_lines = case content_type
                        when "project_card"
                          InfoLineResolver.default_project_card_lines(rctx)
                        when "customer_card"
                          InfoLineResolver.default_customer_card_lines(rctx)
                        when "workflow_status"
                          InfoLineResolver.default_workflow_status_lines(rctx)
                        when "history_table"
                          InfoLineResolver.default_history_lines(rctx)
                        when "materials_spec"
                          [ctx[:info][:materials].to_s.strip.empty? ? "Фасады, корпус, фурнитура..." : ctx[:info][:materials].to_s.strip]
                        when "appliances_spec"
                          [ctx[:info][:appliances].to_s.strip.empty? ? "Встраиваемая техника и приборы..." : ctx[:info][:appliances].to_s.strip]
                        when "lighting_spec"
                          [ctx[:info][:lighting].to_s.strip.empty? ? "LED подсветка и блоки питания..." : ctx[:info][:lighting].to_s.strip]
                        when "scene_notes"
                          desc = rctx[:scene_item] ? rctx[:scene_item].description : nil
                          [(desc && !desc.empty?) ? desc : (ctx[:info][:notes].to_s.strip.empty? ? "Габаритные размеры и привязки..." : ctx[:info][:notes].to_s.strip)]
                        else
                          []
                        end
            (raw_lines || []).each do |s|
              items << { text: s, size: font_size, color: SLOT_TEXT_COLOR, align: align } if s && !s.empty?
            end
          end

          return if items.empty?

          item_gap = if (cfg.key?(:item_gap_mm) && !cfg[:item_gap_mm].nil?) || (cfg.key?("item_gap_mm") && !cfg["item_gap_mm"].nil?)
                       mm_val = (cfg[:item_gap_mm] || cfg["item_gap_mm"]).to_f
                       (mm_val * PT_PER_INCH / 25.4).round(1)
                     elsif (cfg.key?(:item_gap) && !cfg[:item_gap].nil?) || (cfg.key?("item_gap") && !cfg["item_gap"].nil?)
                       (cfg[:item_gap] || cfg["item_gap"]).to_f
                     else
                       6.0
                     end
          item_heights = items.map do |it|
            [estimate_text_height(it[:text], it[:size], in_w) + 1.0, it[:size] + 2.0].max
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
            add_bounded_text(ctx, doc, page, layer, it[:text], { x: in_x, y: cur_y, width: in_w, height: h },
                             size: it[:size], color: it[:color], align: it[:align] || align, anchor: :top, font: ctx[:font])
            cur_y -= h

            if idx < items.size - 1
              sep_y = cur_y - (item_gap / 2.0)
              line_w = [in_w * 0.75, 120.0].min
              item_align = it[:align] || align
              lx = if item_align == :right
                     in_x + in_w - line_w
                   elsif item_align == :center
                     in_x + (in_w - line_w) / 2.0
                   else
                     in_x
                   end
              add_hline(ctx, doc, page, layer, lx, sep_y, line_w, SEP_COLOR, 0.5)
              cur_y -= item_gap
            end
          end
        end

        # Приблизительная высота многострочного текста в pt
        # (замена Prawn height_of: DIN Condensed узкий, средняя ширина глифа ~0.45 кегля)
        def estimate_text_height(text, size_pt, width_pt)
          cpl = [(width_pt / (size_pt * 0.45)).floor, 1].max
          lines = text.to_s.split("\n", -1).sum { |seg| [(seg.length.to_f / cpl).ceil, 1].max }
          [lines, 1].max * size_pt * 1.25
        end

        # ------------------------------------------------------------------
        # Нижний колонтитул (зеркало PageBase#render_modular_footer)
        # ------------------------------------------------------------------

        def render_modular_footer(doc, page, layer, ftr_box, cfg, ctx, rctx)
          raw_valign = (cfg[:valign] || cfg["valign"] || "bottom").to_s
          valign = (raw_valign == "top") ? :top : :bottom
          font_size = (cfg[:font_size] || cfg["font_size"] || 8.5).to_f

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
            text = InfoLineResolver.resolve(rctx, k)
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

          footer_opts = { size: font_size, color: FOOTER_COLOR, font: ctx[:font], anchor: valign }

          if has_left && has_center && has_right
            w_left = (w_total * 0.35).round(2)
            w_center = (w_total * 0.42).round(2)
            w_right = (w_total - w_left - w_center).round(2)
            x_left = ftr_box[:x] + 4
            x_center = ftr_box[:x] + w_left + 2
            x_right = ftr_box[:x] + w_left + w_center + 4

            add_bounded_text(ctx, doc, page, layer, left_text,   { x: x_left,   y: y_pos, width: w_left - 6,   height: h_pos }, footer_opts.merge(align: :left))
            add_bounded_text(ctx, doc, page, layer, center_text, { x: x_center, y: y_pos, width: w_center - 4, height: h_pos }, footer_opts.merge(align: :center))
            add_bounded_text(ctx, doc, page, layer, right_text,  { x: x_right,  y: y_pos, width: w_right - 12, height: h_pos }, footer_opts.merge(align: :right))
          elsif has_left && has_right && !has_center
            w_left = (w_total * 0.65).round(2)
            w_right = (w_total - w_left).round(2)
            add_bounded_text(ctx, doc, page, layer, left_text,  { x: ftr_box[:x] + 4, y: y_pos, width: w_left - 6,   height: h_pos }, footer_opts.merge(align: :left))
            add_bounded_text(ctx, doc, page, layer, right_text, { x: ftr_box[:x] + w_left + 4, y: y_pos, width: w_right - 12, height: h_pos }, footer_opts.merge(align: :right))
          elsif has_center && !has_left && !has_right
            add_bounded_text(ctx, doc, page, layer, center_text, { x: ftr_box[:x] + 4, y: y_pos, width: w_total - 8, height: h_pos }, footer_opts.merge(align: :center))
          elsif has_left && !has_center && !has_right
            add_bounded_text(ctx, doc, page, layer, left_text, { x: ftr_box[:x] + 4, y: y_pos, width: w_total - 8, height: h_pos }, footer_opts.merge(align: :left))
          elsif has_right && !has_left && !has_center
            add_bounded_text(ctx, doc, page, layer, right_text, { x: ftr_box[:x] + 4, y: y_pos, width: w_total - 12, height: h_pos }, footer_opts.merge(align: :right))
          elsif has_left && has_center && !has_right
            w_left = (w_total * 0.45).round(2)
            w_center = (w_total - w_left).round(2)
            add_bounded_text(ctx, doc, page, layer, left_text,   { x: ftr_box[:x] + 4, y: y_pos, width: w_left - 6,   height: h_pos }, footer_opts.merge(align: :left))
            add_bounded_text(ctx, doc, page, layer, center_text, { x: ftr_box[:x] + w_left + 2, y: y_pos, width: w_center - 6, height: h_pos }, footer_opts.merge(align: :center))
          elsif has_center && has_right && !has_left
            w_center = (w_total * 0.65).round(2)
            w_right = (w_total - w_center).round(2)
            add_bounded_text(ctx, doc, page, layer, center_text, { x: ftr_box[:x] + 4, y: y_pos, width: w_center - 6, height: h_pos }, footer_opts.merge(align: :center))
            add_bounded_text(ctx, doc, page, layer, right_text,  { x: ftr_box[:x] + w_center + 4, y: y_pos, width: w_right - 12, height: h_pos }, footer_opts.merge(align: :right))
          end
        end

        # ------------------------------------------------------------------
        # Штамп (зеркало PageBase#render_stamp)
        # ------------------------------------------------------------------

        def render_stamp(doc, page, layer, content, ctx)
          settings = ctx[:settings]
          stamp_type = settings[:stamp_type].to_s
          return if stamp_type == "none" || stamp_type.empty?

          text1 = case stamp_type
                  when "draft"
                    settings[:stamp_custom] || "НЕ УТВЕРЖДЕН"
                  when "approved"
                    "В ПРОИЗВОДСТВО"
                  else
                    settings[:stamp_custom] || "КОНЦЕПТ"
                  end

          text2 = "Проект не является финальным чертежом"

          # Prawn: pos_x = bounds.right - 260; pos_y = bounds.bottom + 110 (pt)
          pos_x = content[:left] + content[:w] - 260.0
          pos_y = content[:top] - content[:h] + 110.0

          stamp_rgb = tinted_rgb(ctx[:stamp_color], 0.35)
          color = begin
            ::Sketchup::Color.new(*stamp_rgb)
          rescue StandardError
            nil
          end

          add_rotated_text(ctx, doc, page, layer, text1.to_s.upcase, pos_x, pos_y, 28.0, color, true, 25.0)
          add_rotated_text(ctx, doc, page, layer, text2, pos_x - 10, pos_y - 32, 10.0, color, false, 25.0)
        end
      end
    end
  end
end
