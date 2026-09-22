# frozen_string_literal: true

require "fileutils"
require_relative "../model/path_util"
require_relative "render_service"
require_relative "info_line_resolver"
require_relative "font_service"
require_relative "pdf_font_audit"

module DN1Code
  module ExportPdf2
    module Service
      # Полнофункциональный экспорт PDF и проектов LayOut через SketchUp LayOut Ruby API.
      #
      # Страницы и видовые экраны строятся по модульной сетке (из layout.yaml):
      #   image_4_3 — видовой экран модели (Layout::SketchUpModel) или растровый оверрайд (Layout::Image),
      #   header    — многострочный заголовок проекта и сцены с разделителями,
      #   slot_1..4 — информационные колонки спецификаций и истории,
      #   footer    — нижний колонтитул в 3 колонки,
      #   stamp     — повернутый полупрозрачный водяной знак/штамп.
      #
        # Документ формируется в многослойной структуре (Viewports, Graphics, Content, Annotations)
        # с возможностью выбора режима рендера видовых экранов (Растровый GPU или Гибридный)
        # и сохранения редактируемого файла .layout.
        module LayoutBuilder
          extend self

        PAGE_SIZES_INCHES = {
          "A4"     => { w: 11.6929, h: 8.2677 },
          "A3"     => { w: 16.5354, h: 11.6929 },
          "A2"     => { w: 23.3858, h: 16.5354 },
          "LETTER" => { w: 11.0,    h: 8.5 }
        }.freeze

        PT_PER_INCH = 72.0

        # Цвета оформления
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

          enabled_scenes = project_data.scenes.select(&:enabled)
          if enabled_scenes.empty?
            raise "Не выбрано ни одной сцены для экспорта в LayOut / PDF!"
          end

          pdf_path = custom_output_path || controller.send(:resolve_default_pdf_path)
          FileUtils.mkdir_p(File.dirname(pdf_path))

          temp_images = []
          begin
            total_pages = enabled_scenes.size
            progress_block&.call(0, total_pages, "Инициализация документа LayOut...")

            # Установка шрифта (по умолчанию Sofia Sans Condensed) в систему
            font_family = FontService.layout_font_family(settings)

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
              # Настройка качества разрешения LayOut (low: 96 dpi, medium: 150 dpi, high: 300 dpi)
              q_mode = (settings[:render_quality] || settings["render_quality"] || "").to_s.downcase.strip
              if q_mode.empty?
                w_val = (settings[:image_width] || settings["image_width"] || 2400).to_i
                q_mode = if w_val <= 1400
                           "low"
                         elsif w_val > 2800
                           "high"
                         else
                           "medium"
                         end
              end

              # Настройка качества разрешения LayOut:
              # В Trimble LayOut API:
              #   RESOLUTION_LOW    = 0 -> 36 DPI (черновые миниатюры 377px, где надписи не читаются)
              #   RESOLUTION_MEDIUM = 1 -> 96 DPI (экранный вывод, четкие надписи и размеры)
              #   RESOLUTION_HIGH   = 2 -> 300 DPI (высокое качество для печати)
              res_val = case q_mode
                        when "low"
                          defined?(::Layout::PageInfo::RESOLUTION_MEDIUM) ? ::Layout::PageInfo::RESOLUTION_MEDIUM : 1
                        when "high"
                          defined?(::Layout::PageInfo::RESOLUTION_HIGH) ? ::Layout::PageInfo::RESOLUTION_HIGH : 2
                        else # "medium"
                          defined?(::Layout::PageInfo::RESOLUTION_HIGH) ? ::Layout::PageInfo::RESOLUTION_HIGH : 2
                        end

              if page_info.respond_to?(:image_output_resolution=)
                page_info.image_output_resolution = res_val
              end
              if page_info.respond_to?(:output_resolution=)
                page_info.output_resolution = res_val
              end
            end

            # Создание структурированных слоев документа LayOut
            layers = {}
            if doc.respond_to?(:layers) && doc.layers
              first_layer = doc.layers.first rescue nil
              layers[:viewport]   = doc.layers.add("DN1C_Viewports", false) rescue first_layer
              layers[:graphics]   = doc.layers.add("DN1C_Graphics", false) rescue (layers[:viewport] || first_layer)
              layers[:content]    = doc.layers.add("DN1C_Content", false) rescue (layers[:graphics] || first_layer)
              layers[:annotation] = doc.layers.add("DN1C_Annotations", false) rescue (layers[:content] || first_layer)
              layers[:default]    = layers[:content] || first_layer
            else
              first_layer = (doc.respond_to?(:layers) && doc.layers) ? (doc.layers.first rescue nil) : nil
              layers = { default: first_layer, viewport: first_layer, graphics: first_layer, content: first_layer, annotation: first_layer }
            end

            # Отключение фоновой сетки для чистого вывода
            if doc.respond_to?(:grid) && doc.grid
              doc.grid.show_grid = false if doc.grid.respond_to?(:show_grid=)
              doc.grid.print_grid = false if doc.grid.respond_to?(:print_grid=)
            end

            ctx = build_context(project_data, model, font_family)
            ctx[:page_w_pt] = in2pt(page_w_in)
            ctx[:page_h_pt] = in2pt(page_h_in)
            # Кэш уже отрендеренных растровых изображений сцен (для повторного использования в PNG-снимках)
            ctx[:rendered_scene_images] = {}

            # 3. Построение страниц по модульной сетке
            enabled_scenes.each_with_index do |scene_item, idx|
              page_index = idx + 1
              progress_block&.call(page_index, total_pages, "Построение страницы LayOut #{page_index}/#{total_pages}: #{scene_item.name}")

              page = if idx.zero?
                       (doc.pages.respond_to?(:initial) ? doc.pages.initial : doc.pages.first) || doc.pages.add(scene_item.name)
                     else
                       doc.pages.add(scene_item.name)
                     end
              page.name = scene_item.name if page.respond_to?(:name=)

              render_modular_page(doc, page, layers, scene_item, page_index, total_pages, page_w_in, page_h_in, margin_in, ctx, temp_images)
            end

            progress_block&.call(total_pages, total_pages, "Экспорт документа LayOut в PDF...")

            # 4. Экспорт в PDF: сам документ ВСЕГДА сжимается без потерь (FlateDecode)
            raw_fmt = (settings[:image_format] || "png").to_s.downcase.strip
            is_png_format = (raw_fmt != "jpg" && raw_fmt != "jpeg")

            # Для документа всегда compress: true (сжатие без потерь).
            # Для PNG compress_images: false (сохраняет оригинальный lossless FlateDecode).
            # Для JPEG compress_images: true (сохраняет сжатие JPEG с максимальным качеством 100%).
            export_opts = {
              compress_images: !is_png_format,
              compress:        true
            }
            if doc.method(:export).arity.abs > 1 || doc.method(:export).parameters.any? { |p| p[0] == :rest || p[0] == :opt }
              doc.export(pdf_path, export_opts) rescue doc.export(pdf_path)
            else
              doc.export(pdf_path)
            end

            # Аудит встроенных шрифтов: warn, если запрошенный шрифт из
            # config/fonts заменен LayOut на системный фолбэк
            if File.exist?(pdf_path)
              PdfFontAudit.audit_exported_pdf!(pdf_path, font_family) rescue nil
            end

            # 4b. Копия «_last» рядом с рабочим файлом модели (<имя>_last.pdf),
            # перезаписывается при каждом экспорте. Сбой копии не валит PDF-экспорт.
            if controller.respond_to?(:resolve_last_pdf_path)
              begin
                last_candidate = controller.resolve_last_pdf_path
                if last_candidate && File.expand_path(last_candidate) != File.expand_path(pdf_path)
                  FileUtils.mkdir_p(File.dirname(last_candidate))
                  FileUtils.cp(pdf_path, last_candidate)
                  controller.last_pdf_path = last_candidate
                end
              rescue StandardError => e
                warn "Предупреждение: не удалось создать копию _last.pdf (#{last_candidate}): #{e.message}"
              end
            end

            # 5. Сохранение файла .layout если включено
            if settings[:save_layout_file]
              layout_path = pdf_path.sub(/\.pdf$/i, ".layout")
              doc.save(layout_path) rescue nil
            end

            # 5b. Снимки последних сцен в папку артикула (<Артикул>/images/, PNG или WebP).
            # Синхронно только подготовка PNG-исходников; конвертация в WebP уходит в
            # фоновый пул SnapshotWorker — PDF открывается, не дожидаясь снимков.
            # Сбой снимков не должен валить PDF-экспорт.
            if controller.respond_to?(:export_scene_snapshots) && controller.scene_images_dir
              begin
                controller.export_scene_snapshots(reusable: ctx[:rendered_scene_images], &progress_block)
              rescue StandardError => e
                warn "Предупреждение: не удалось сохранить снимки сцен: #{e.message}"
              end
            end

            # 6. Резервная копия .skp
            if settings[:save_skp_backup] && model && model.respond_to?(:path) && !model.path.empty?
              controller.send(:save_skp_backup)
            end

            # 7. Запись данных в YAML (проект + настройки/шаблоны расширения)
            if defined?(Model::SessionStore)
              Model::SessionStore.flush(model) if model
            elsif project_data.respond_to?(:save_project_yaml)
              project_data.save_project_yaml(model) if model
              project_data.save_program_settings
            end

            progress_block&.call(total_pages, total_pages, "Экспорт через LayOut API успешно завершен!")

            # 8. Открытие PDF файла (openURL требует URL-схему file:///)
            # Открываем именно копию «_last» рядом с .skp, если она создана
            if settings[:auto_open_pdf] && defined?(UI) && UI.respond_to?(:openURL)
              opened = controller.last_pdf_path || pdf_path
              UI.openURL(Model::PathUtil.file_url(opened))
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

        # Поля страницы в дюймах (margin_mm -> pt -> in)
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
            text_bold:     FontService.font_weight_setting(settings) == "bold",
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
        # Доступ к конфигурации модульной сетки
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
          return true if cfg.nil? || cfg.empty?

          val = cfg.key?(:visible) ? cfg[:visible] : cfg["visible"]
          return true if val.nil?

          !(val == false || val.to_s.strip.downcase == "false" || val.to_s.strip == "0")
        end

        # Расчет абсолютных координат блока в пунктах.
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

          raw_vis = cfg.key?(:visible) ? cfg[:visible] : cfg["visible"]
          visible = raw_vis.nil? ? true : !(raw_vis == false || raw_vis.to_s.strip.downcase == "false" || raw_vis.to_s.strip == "0")
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
        # смешиванием с белой бумагой
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

        def apply_text_style!(style, opts, ctx = nil)
          style.font_family = opts[:font] if opts[:font] && style.respond_to?(:font_family=)
          style.font_size   = opts[:size].to_f if opts[:size] && style.respond_to?(:font_size=)
          if opts[:color_obj].is_a?(::Sketchup::Color)
            style.text_color = opts[:color_obj] if style.respond_to?(:text_color=)
          elsif opts[:color]
            style.text_color = layout_color(opts[:color]) if style.respond_to?(:text_color=)
          end
          # Жирность: явный bold в opts или глобальный параметр font_weight
          bold = opts[:bold] || (ctx && ctx[:text_bold]) ? true : false
          style.text_bold = bold if style.respond_to?(:text_bold=)
          style.text_alignment = style_alignment(opts[:align]) if style.respond_to?(:text_alignment=)
          style.text_anchor = style_anchor(opts[:anchor]) if style.respond_to?(:text_anchor=)
        rescue StandardError
          nil
        end

        # Преобразование Y: внутренняя координатная система листа (y вверх, от низа листа),
        # у LayOut бумажные координаты — y вниз, от верхнего левого угла листа.
        def lay_y(ctx, y_pt)
          h_pt = (ctx && ctx[:page_h_pt]) ? ctx[:page_h_pt] : 595.28
          h_pt - y_pt.to_f
        end

        def make_bounds_pt(ctx, x_pt, y_top_pt, w_pt, h_pt)
          raise ArgumentError, "zero size bounds" if w_pt <= 0 || h_pt <= 0

          # y_top_pt — верхняя грань блока; в LayOut это верх рамки (y вниз)
          ::Geom::Bounds2d.new(pt2in(x_pt), pt2in(lay_y(ctx, y_top_pt)), pt2in(w_pt), pt2in(h_pt))
        end

        # Ограниченный текстовый блок (box — координаты блока, y — верхняя грань, в pt)
        def add_bounded_text(ctx, doc, page, layer, text, box, opts = {})
          return if text.to_s.empty?

          # Запас высоты (+1.5 pt) гарантирует, что LayOut не обрежет нижние выносные элементы
          extra_h = 1.5
          text_ent = ::Layout::FormattedText.new(text.to_s, make_bounds_pt(ctx, box[:x], box[:y], box[:width], box[:height] + extra_h))
          text_ent.grow_mode = ::Layout::FormattedText::GROW_MODE_BOUNDED
          style = text_ent.style(0)
          apply_text_style!(style, opts, ctx)
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

        # Многофрагментная строка заголовка через RTF (разные цвета/размеры для элементов)
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
            # Глобальный font_weight=bold распространяется и на RTF-фрагменты
            bold = f[:bold] || ctx[:text_bold] ? true : false
            run = +"\\cf#{idx}\\fs#{half} "
            run << "\\b " if bold
            run << rtf_escape(f[:text])
            run << "\\b0 " if bold
            runs << run
          end
          return if runs.empty?

          colortbl = colors.drop(1).map { |rgb| "\\red#{rgb[0]}\\green#{rgb[1]}\\blue#{rgb[2]};" }.join
          align_code = case opts[:align]
                       when :right then "qr"
                       when :center then "qc"
                       else "ql"
                       end
          font = opts[:font] || ctx[:font] || "Sofia Sans Condensed"
          rtf = "{\\rtf1\\ansi\\deff0{\\fonttbl{\\f0 #{font};}}{\\colortbl;#{colortbl}}" \
                "\\pard\\#{align_code}\\f0 #{runs.join}\\par}"

          extra_h = 1.5
          text_ent = ::Layout::FormattedText.new(" ", make_bounds_pt(ctx, box[:x], box[:y], box[:width], box[:height] + extra_h))
          text_ent.grow_mode = ::Layout::FormattedText::GROW_MODE_BOUNDED
          text_ent.rtf = rtf
          # LayOut игнорирует \fonttbl из RTF, поэтому семейство/кегль дополнительно
          # задаются стилем entity — иначе заголовок печатается дефолтным шрифтом
          # (Microsoft Sans Serif), игнорируя выбор пользователя.
          base_size = fragments.map { |f| f[:size].to_f }.max
          style = text_ent.style(0)
          apply_text_style!(style, size: base_size, align: opts[:align], font: font, bold: ctx[:text_bold])
          text_ent.apply_style(style)
          doc.add_entity(text_ent, layer, page)
          text_ent
        rescue StandardError => e
          warn "Ошибка добавления RTF текста LayOut: #{e.message}"
          nil
        end

        # Горизонтальная разделительная линия (тонкая залитая плашка)
        def add_hline(ctx, doc, page, layer, x_pt, y_center_pt, w_pt, color_hex = SEP_COLOR, thickness_pt = 0.7)
          return if w_pt <= 0 || thickness_pt <= 0

          # верхняя грань плашки = центр + половина толщины
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

        # ------------------------------------------------------------------
        # Стадии проекта (workflow_stadia): строки с квадратами-чекбоксами.
        # Квадрат слева от текста при выравнивании влево, справа от текста —
        # при выравнивании вправо; по центру — слева от текста.
        # ------------------------------------------------------------------
        def draw_stadia_check_rows(ctx, doc, page, layer, item, box, font_name, slot_scale, gfx_layer)
          lines = item[:text].to_s.split("\n", -1)
          return if lines.empty?

          size  = (item[:size] * slot_scale).round(2)
          pitch = size * font_line_pitch_ratio(font_name)
          side  = size * 0.85
          gap   = size * 0.30

          lines.each_with_index do |ln, i|
            y_top = box[:y] - i * pitch
            unless ln.start_with?("[✓]", "[ ]")
              # Заголовок «Стадия проекта» — обычным текстом без квадрата
              add_bounded_text(ctx, doc, page, layer, ln, { x: box[:x], y: y_top, width: box[:width], height: pitch },
                               size: size, color: item[:color], align: item[:align], anchor: :top, font: font_name)
              next
            end

            checked = ln.start_with?("[✓]")
            name = ln.sub(/\A\[[✓ ]\]\s*/, "")
            case item[:align]
            when :right
              sq_x = box[:x] + box[:width] - side
              text_box = { x: box[:x], y: y_top, width: box[:width] - side - gap, height: pitch }
              text_align = :right
            when :center
              w_est = [name.length * size * font_char_width_ratio(font_name), box[:width] * 0.85].min
              text_x = box[:x] + (box[:width] - w_est) / 2.0
              sq_x = [text_x - side - gap, box[:x]].max
              text_box = { x: text_x, y: y_top, width: [[w_est + size, box[:x] + box[:width] - text_x].min, 1.0].max, height: pitch }
              text_align = :left
            else
              sq_x = box[:x]
              text_box = { x: box[:x] + side + gap, y: y_top, width: box[:width] - side - gap, height: pitch }
              text_align = :left
            end

            add_bounded_text(ctx, doc, page, layer, name, text_box,
                             size: size, color: item[:color], align: text_align, anchor: :top, font: font_name)
            add_checkbox(ctx, doc, page, gfx_layer, sq_x, y_top - (pitch - side) / 2.0, side, checked, item[:color])
          end
        rescue StandardError => e
          warn "Ошибка отрисовки стадий с чекбоксами: #{e.message}"
          add_bounded_text(ctx, doc, page, layer, item[:text], box,
                           size: (item[:size] * slot_scale).round(2), color: item[:color], align: item[:align], anchor: :top, font: font_name)
        end

        # Квадрат-чекбокс: пустой или с галкой (checked). Координаты в pt, y — верхняя грань.
        def add_checkbox(ctx, doc, page, layer, x_pt, y_top_pt, side_pt, checked, color_hex)
          return if side_pt <= 0

          rect = ::Layout::Rectangle.new(make_bounds_pt(ctx, x_pt, y_top_pt, side_pt, side_pt))
          style = rect.style
          style.stroked = true if style.respond_to?(:stroked=)
          style.stroke_width = pt2in([side_pt * 0.07, 0.4].max) if style.respond_to?(:stroke_width=)
          style.stroke_color = layout_color(color_hex) if style.respond_to?(:stroke_color=)
          style.solid_filled = false if style.respond_to?(:solid_filled=)
          rect.style = style
          doc.add_entity(rect, layer, page)
          return unless checked

          # Галка — ломаная из трёх точек (доли стороны квадрата, y_top — верх квадрата).
          # Путь по умолчанию замыкается и заливается — заливку отключаем, оставляем обводку.
          p1 = ::Geom::Point2d.new(pt2in(x_pt + side_pt * 0.20), pt2in(lay_y(ctx, y_top_pt - side_pt * 0.52)))
          p2 = ::Geom::Point2d.new(pt2in(x_pt + side_pt * 0.42), pt2in(lay_y(ctx, y_top_pt - side_pt * 0.74)))
          p3 = ::Geom::Point2d.new(pt2in(x_pt + side_pt * 0.82), pt2in(lay_y(ctx, y_top_pt - side_pt * 0.28)))
          path = ::Layout::Path.new(p1, p2)
          path.append_point(p3)
          pstyle = path.style
          pstyle.stroked = true if pstyle.respond_to?(:stroked=)
          pstyle.solid_filled = false if pstyle.respond_to?(:solid_filled=)
          pstyle.stroke_width = pt2in([side_pt * 0.09, 0.5].max) if pstyle.respond_to?(:stroke_width=)
          pstyle.stroke_color = layout_color(color_hex) if pstyle.respond_to?(:stroke_color=)
          pstyle.stroke_cap_style = ::Layout::Style::CAP_STYLE_ROUND if pstyle.respond_to?(:stroke_cap_style=) && defined?(::Layout::Style::CAP_STYLE_ROUND)
          pstyle.stroke_join_style = ::Layout::Style::JOIN_STYLE_ROUND if pstyle.respond_to?(:stroke_join_style=) && defined?(::Layout::Style::JOIN_STYLE_ROUND)
          path.style = pstyle
          doc.add_entity(path, layer, page)
        rescue StandardError => e
          warn "Ошибка отрисовки чекбокса стадии: #{e.message}"
          nil
        end

        # Повернутый текст (штамп): привязка в точке + поворот вокруг нее.
        # Положительный угол в геометрии — против часовой стрелки;
        # в LayOut y направлен вниз, поэтому знак угла инвертируется.
        def add_rotated_text(ctx, doc, page, layer, text, x_pt, y_pt, size_pt, color_obj, bold, angle_deg)
          return if text.to_s.empty?

          anchor_pt = ::Geom::Point2d.new(pt2in(x_pt), pt2in(lay_y(ctx, y_pt)))
          text_ent = ::Layout::FormattedText.new(text.to_s, anchor_pt, ::Layout::FormattedText::ANCHOR_TYPE_TOP_LEFT)
          style = text_ent.style(0)
          apply_text_style!(style, size: size_pt, color_obj: color_obj, font: ctx[:font], bold: bold || ctx[:text_bold])
          text_ent.apply_style(style)
          doc.add_entity(text_ent, layer, page)
          text_ent.transform!(::Geom::Transformation2d.rotation(anchor_pt, -angle_deg * Math::PI / 180.0))
          text_ent
        rescue StandardError => e
          warn "Ошибка добавления штампа LayOut: #{e.message}"
          nil
        end

        # ------------------------------------------------------------------
        # Рендер страницы по модульной сетке
        # ------------------------------------------------------------------

        def render_modular_page(doc, page, layer, scene_item, page_index, total_pages, page_w_in, page_h_in, margin_in, ctx, temp_images)
          ctx[:page_w_pt] ||= in2pt(page_w_in || 11.6929)
          ctx[:page_h_pt] ||= in2pt(page_h_in || 8.2677)

          pt = (scene_item.page_type || :general).to_sym
          page_cfg = get_page_cfg(ctx, pt)

          margin_pt = in2pt(margin_in)
          content = {
            left: margin_pt,
            top:  in2pt(page_h_in) - margin_pt,
            w:    in2pt(page_w_in) - (margin_pt * 2),
            h:    in2pt(page_h_in) - (margin_pt * 2)
          }
          
          full_page_content = {
            left: 0.0,
            top:  in2pt(page_h_in),
            w:    in2pt(page_w_in),
            h:    in2pt(page_h_in)
          }

          rctx = resolver_context(ctx, scene_item, page_index, total_pages)

          # Разделение по специализированным слоям документа
          vp_layer  = layer.is_a?(Hash) ? (layer[:viewport] || layer[:default]) : layer
          gfx_layer = layer.is_a?(Hash) ? (layer[:graphics] || layer[:default]) : layer
          cnt_layer = layer.is_a?(Hash) ? (layer[:content] || layer[:default]) : layer
          ann_layer = layer.is_a?(Hash) ? (layer[:annotation] || layer[:default]) : layer

          # 1. Видовой экран чертежа/модели (Layout::SketchUpModel / Layout::Image)
          is_viewport_on = if scene_item && scene_item.respond_to?(:viewport_visible) && !scene_item.viewport_visible.nil?
                             scene_item.viewport_visible != false
                           else
                             block_visible?(page_cfg, :image_4_3)
                           end

          if is_viewport_on
            img_cfg = get_block_config(ctx, pt, :image_4_3)
            render_image_block(doc, page, layer, scene_item, full_page_content, img_cfg, ctx, temp_images, pt)
          end

          page_font = if page_cfg[:font_family] && !page_cfg[:font_family].to_s.strip.empty?
                        FontService.layout_font_family(page_cfg[:font_family])
                      else
                        ctx[:font]
                      end
          page_ctx = (page_font != ctx[:font]) ? ctx.merge(font: page_font) : ctx

          # 2. Верхний заголовок (Header)
          if block_visible?(page_cfg, :header)
            hdr_box = get_block_box(content, page_cfg, :header, 0.0, 0.0, 100.0, 30.0)
            render_modular_header(doc, page, cnt_layer, hdr_box, page_cfg, page_ctx, rctx, gfx_layer)
          end

          # 3. Информационные слоты поверх видового экрана
          render_modular_slots(doc, page, cnt_layer, content, page_cfg, pt, page_ctx, rctx, gfx_layer)

          # 4. Нижний колонтитул (Footer)
          if block_visible?(page_cfg, :footer)
            ftr_cfg = get_block_config(page_ctx, pt, :footer)
            ftr_box = get_block_box(content, page_cfg, :footer, 0.0, 94.0, 100.0, 6.0)
            render_modular_footer(doc, page, cnt_layer, ftr_box, ftr_cfg, page_ctx, rctx)
          end

          # 5. Штамп/водяной знак
          render_stamp(doc, page, ann_layer, content, page_ctx)
        end

        # ------------------------------------------------------------------
        # Блок видового экрана (Layout::SketchUpModel с режимами Vector/Raster/Hybrid либо Layout::Image)
        # ------------------------------------------------------------------

        def render_image_block(doc, page, layer, scene_item, content, img_cfg, ctx, temp_images, pt)
          # Фон сцены (небо/земля/водяные знаки): посценный флаг с фолбэком на настройку слота шаблона
          show_bg = if scene_item && scene_item.respond_to?(:viewport_background) && !scene_item.viewport_background.nil?
                      scene_item.viewport_background != false
                    else
                      slot_bg = img_cfg[:show_background] || img_cfg["show_background"]
                      !(slot_bg == false || slot_bg.to_s == "false" || slot_bg == 0 || slot_bg.to_s == "0")
                    end

          ratio_str = if scene_item && scene_item.respond_to?(:aspect_ratio) && !scene_item.aspect_ratio.to_s.empty?
                        scene_item.aspect_ratio.to_s.strip
                      else
                        (img_cfg[:aspect_ratio] || img_cfg["aspect_ratio"] || "4:3").to_s.strip
                      end
          target_ratio = case ratio_str
                         when "3:2"  then 3.0 / 2.0
                         when "16:9" then 16.0 / 9.0
                         when "1:1"  then 1.0
                         when "page" then content[:w] / content[:h]
                         else 4.0 / 3.0
                         end

          raw_scale = if scene_item && scene_item.respond_to?(:scale_pct) && scene_item.scale_pct.to_f > 0
                        scene_item.scale_pct.to_f
                      else
                        (img_cfg[:scale_pct] || img_cfg["scale_pct"] || 100).to_f
                      end
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

          vp_layer = layer.is_a?(Hash) ? (layer[:viewport] || layer[:default]) : layer

          mode_str = (ctx[:settings][:layout_render_mode] || "image").to_s.downcase

          # 1. Создание живого видового экрана SketchUp (Layout::SketchUpModel)
          #    Используется для гибридного режима рендеринга видового экрана (Hybrid)
          use_skp_viewport = (mode_str == "hybrid")

          if use_skp_viewport && defined?(::Layout::SketchUpModel) && ctx[:model]
            skp_path = nil

            if ctx[:temp_skp_path] && File.exist?(ctx[:temp_skp_path])
              skp_path = ctx[:temp_skp_path]
            else
              afs_setting = ctx[:settings][:annotation_font_size] || ctx[:settings]["annotation_font_size"]
              has_custom_font = afs_setting && !afs_setting.to_s.strip.empty? && afs_setting.to_s.downcase.strip != "auto"
              is_modified = (ctx[:model].respond_to?(:modified?) && ctx[:model].modified?) || has_custom_font
              has_disk_path = ctx[:model].respond_to?(:path) && !ctx[:model].path.to_s.empty? && File.exist?(ctx[:model].path.to_s)

              # Если в модели есть несохраненные изменения в SketchUp или задан кастомный размер шрифта выносок,
              # создаем временную копию save_copy, чтобы LayOut увидел актуальное состояние, а не старый файл с диска
              if (is_modified || !has_disk_path) && ctx[:model].respond_to?(:save_copy)
                temp_skp = File.join(Dir.tmpdir, "dn1c_model_#{$$}_#{Time.now.to_i}.skp")
                begin
                  RenderService.with_temporary_annotation_font_size(ctx[:model], afs_setting) do
                    ctx[:model].save_copy(temp_skp)
                  end
                  if File.exist?(temp_skp)
                    ctx[:temp_skp_path] = temp_skp
                    temp_images << temp_skp
                    skp_path = temp_skp
                  end
                rescue StandardError
                  skp_path = nil
                end
              end

              skp_path ||= ctx[:model].path.to_s if has_disk_path
            end

            if skp_path && File.exist?(skp_path)
              begin
                bounds = ::Geom::Bounds2d.new(pt2in(img_x), pt2in(lay_y(ctx, img_y)), pt2in(img_w), pt2in(img_h))
                skp_model = ::Layout::SketchUpModel.new(skp_path, bounds)

                # Выбор текущей сцены модели
                target_scene_name = scene_item.respond_to?(:name) ? scene_item.name.to_s : ""
                if skp_model.respond_to?(:scenes) && skp_model.scenes.is_a?(Array)
                  scene_idx = skp_model.scenes.index(target_scene_name)
                  if scene_idx && skp_model.respond_to?(:current_scene=)
                    skp_model.current_scene = scene_idx
                  elsif skp_model.respond_to?(:current_scene=) && skp_model.scenes.size > 1
                    skp_model.current_scene = 1
                  end
                end

                # Сброс переопределений стиля для точного следования стилю сцены SketchUp
                if skp_model.respond_to?(:reset_style)
                  skp_model.reset_style rescue nil
                end

                # Отключение фона видового экрана (небо/земля) в LayOut при выключенном фоне
                if !show_bg && skp_model.respond_to?(:display_background=)
                  begin
                    skp_model.display_background = false
                  rescue StandardError => _e
                    # Не критично: останется фон сцены
                  end
                end

                # Установка режима рендеринга видового экрана (Гибридный)
                if skp_model.respond_to?(:render_mode=)
                  skp_model.render_mode = ::Layout::SketchUpModel::HYBRID_RENDER if defined?(::Layout::SketchUpModel::HYBRID_RENDER)
                end

                # Установка масштаба толщины линий (Line Scale Multiplier)
                # В SketchUp LayOut базовая толщина линий модели равна 0.5 pt
                # При ручном множителе (0.5, 1.0, 1.5, 2.0, 2.5, 3.0) значение одинаково для всех режимов.
                # В режиме "auto" (с уменьшением на 40%):
                # - Растр (Raster): расчет от разрешения (1200px=0.60->0.30pt, 1800px=0.90->0.45pt, 2400px=1.20->0.60pt, 3000px=1.50->0.75pt, 3840px=1.80->0.90pt)
                #   с защитным порогом для больших форматов A3 (min 0.90) и A2 (min 1.20)
                # - Гибрид (Hybrid): подстроен под растр по формату листа (A4=0.60->0.30pt, A3=0.90->0.45pt, A2=1.20->0.60pt)
                sm_setting = ctx[:settings][:scale_multiplier] || ctx[:settings]["scale_multiplier"]
                sf_setting = ctx[:settings][:scale_factor] || ctx[:settings]["scale_factor"]
                page_sz = (ctx[:settings][:page_size] || ctx[:settings]["page_size"] || "A4").to_s.upcase.strip

                line_mult = if sm_setting
                              case sm_setting.to_s.downcase.strip
                              when "auto"
                                base_val = if mode_str == "hybrid"
                                             case page_sz
                                             when "A2" then 1.20
                                             when "A3" then 0.90
                                             else 0.60
                                             end
                                           else
                                             img_w = (ctx[:settings][:image_width] || ctx[:settings]["image_width"] || 2400).to_i
                                             ras_mult = if img_w <= 1400
                                                          0.60
                                                        elsif img_w <= 2000
                                                          0.90
                                                        elsif img_w <= 2800
                                                          1.20
                                                        elsif img_w <= 3400
                                                          1.50
                                                        else
                                                          1.80
                                                        end
                                             case page_sz
                                             when "A2" then [ras_mult, 1.20].max
                                             when "A3" then [ras_mult, 0.90].max
                                             else ras_mult
                                             end
                                           end
                                # При авто scale множитель меньше на 30% (* 0.70)
                                (base_val * 0.70).round(2)
                              else
                                f = sm_setting.to_f
                                f > 0.0 ? f : 2.0
                              end
                            elsif sf_setting && sf_setting.to_f > 0
                              sf_setting.to_f
                            else
                              2.0
                            end

                # Базовая толщина линий модели в LayOut по умолчанию равна 0.5 pt
                base_pt = 0.5
                if skp_model.respond_to?(:line_weight=)
                  skp_model.line_weight = (base_pt * line_mult).round(2)
                end

                # Рендеринг видового экрана, если требуется
                if skp_model.respond_to?(:render_needed?) && skp_model.render_needed?
                  skp_model.render rescue nil
                end

                doc.add_entity(skp_model, vp_layer, page)

                return
              rescue StandardError => e
                warn "Предупреждение: создание Layout::SketchUpModel (#{e.message}), используется растровый вывод"
              end
            end
          end

          # 2. Резервный растровый рендер высокого разрешения через RenderService
          #    (режим "image": Растровый GPU с Ambient Occlusion и мягкими тенями)
          render_opts = {
            image_width:        ctx[:settings][:image_width],
            render_quality:     ctx[:settings][:render_quality] || "medium",
            scale_multiplier:   ctx[:settings][:scale_multiplier] || "2.0",
            scale_factor:       line_mult || (ctx[:settings][:scale_factor] || 2.0),
            annotation_font_size: ctx[:settings][:annotation_font_size],
            page_size:          ctx[:settings][:page_size] || "A4",
            antialias:          ctx[:settings].fetch(:antialias, true),
            show_background:    show_bg,
            aspect_ratio:       target_ratio,
            image_aspect_ratio: ctx[:settings][:image_aspect_ratio],
            image_format:       ctx[:settings][:image_format] || "png",
            compress_pdf:       ctx[:settings][:compress_pdf]
          }
          if defined?(OverlayService)
            scene_aspect_info = ctx[:aspect_cache][pt]
            unless scene_aspect_info
              scene_aspect_info = OverlayService.calculate_target_info(ctx[:model], { template_key: pt }) rescue nil
              ctx[:aspect_cache][pt] = scene_aspect_info
            end
            render_opts[:aspect_ratio] = scene_aspect_info[:ratio] if scene_aspect_info && scene_aspect_info[:ratio]
          end
          scene_obj = scene_item.respond_to?(:scene_ref) ? scene_item.scene_ref : nil
          if scene_obj.nil? && ctx[:model] && ctx[:model].respond_to?(:pages) && scene_item.respond_to?(:name)
            scene_obj = ctx[:model].pages[scene_item.name.to_s] rescue nil
          end
          image_path = RenderService.render_scene_temp(ctx[:model], scene_obj, render_opts)
          temp_images << image_path if image_path
          # Запоминаем растр сцены: PNG-снимок в папку артикула переиспользует его без повторного рендера
          if image_path && scene_item.respond_to?(:name) && ctx[:rendered_scene_images].is_a?(Hash)
            ctx[:rendered_scene_images][scene_item.name] = image_path
          end

          return unless image_path && File.exist?(image_path)

          draw_w, draw_h = fit_image_size(image_path, img_w, img_h)
          return unless draw_w > 0 && draw_h > 0

          bounds = ::Geom::Bounds2d.new(pt2in(img_x), pt2in(lay_y(ctx, img_y)), pt2in(draw_w), pt2in(draw_h))
          img = ::Layout::Image.new(image_path, bounds)
          doc.add_entity(img, vp_layer, page)
        rescue StandardError => e
          warn "Ошибка вставки изображения LayOut: #{e.message}"
        end

        # Вписывает изображение в блок с сохранением пропорций
        def fit_image_size(image_path, box_w_pt, box_h_pt)
          px = png_pixel_size(image_path)
          return [box_w_pt, box_h_pt] unless px

          px_w, px_h = px
          return [box_w_pt, box_h_pt] unless px_w.to_i > 0 && px_h.to_i > 0

          k = [(box_w_pt / px_w.to_f), (box_h_pt / px_h.to_f)].min
          [px_w * k, px_h * k]
        end

        # Чтение размеров изображения (PNG и JPEG) для точного вписывания
        def png_pixel_size(path)
          return nil unless path && File.exist?(path)

          File.open(path, "rb") do |f|
            header = f.read(24)
            return nil unless header

            # PNG: сигнатура \x89PNG, размеры в IHDR
            if header.bytesize >= 24 && header.getbyte(0) == 0x89 && header[1, 3] == "PNG"
              return [header[16, 4].unpack1("N"), header[20, 4].unpack1("N")]
            end

            # JPEG: сигнатура 0xFF, 0xD8
            if header.bytesize >= 2 && header.getbyte(0) == 0xFF && header.getbyte(1) == 0xD8
              f.seek(2)
              while !f.eof?
                b = f.getbyte
                next unless b == 0xFF

                m = f.getbyte
                while m == 0xFF
                  m = f.getbyte
                end
                break if m.nil? || m == 0xDA || m == 0xD9 # SOS или EOI

                len_data = f.read(2)
                break unless len_data && len_data.bytesize == 2
                len = len_data.unpack1("n")
                break if len < 2

                if (0xC0..0xC3).include?(m) || (0xC5..0xC7).include?(m) ||
                   (0xC9..0xCB).include?(m) || (0xCD..0xCF).include?(m)
                  sof = f.read(5)
                  if sof && sof.bytesize == 5
                    h = sof[1, 2].unpack1("n")
                    w = sof[3, 2].unpack1("n")
                    return [w, h] if w > 0 && h > 0
                  end
                  break
                else
                  f.seek(len - 2, IO::SEEK_CUR)
                end
              end
            end
          end
          nil
        rescue StandardError
          nil
        end

        # ------------------------------------------------------------------
        # Верхний заголовок (зеркало PageBase#render_modular_header)
        # ------------------------------------------------------------------

        def render_modular_header(doc, page, layer, hdr_box, page_cfg, ctx, rctx, gfx_layer = nil)
          cfg = page_cfg[:header] || page_cfg["header"] || {}
          content_type = (cfg[:content] || cfg["content"] || "header_title").to_s
          valign = (cfg[:valign] || cfg["valign"] || "top").to_s.to_sym
          font_size = (cfg[:font_size] || cfg["font_size"] || 11.0).to_f
          hdr_font = if cfg[:font_family] && !cfg[:font_family].to_s.strip.empty?
                       FontService.layout_font_family(cfg[:font_family])
                     else
                       ctx[:font]
                     end
          lines = cfg[:lines] || cfg["lines"]
          if lines.nil?
            lines = ["furniture_name", "place_address", "customer_or_company", "scene_name", "scene_description"]
          end
          return if lines.is_a?(Array) && lines.empty?

          if content_type == "custom_text"
            txt = (cfg[:custom_text] || cfg["custom_text"] || "").to_s
            add_bounded_text(ctx, doc, page, layer, txt,
                             { x: hdr_box[:x], y: hdr_box[:y], width: hdr_box[:width], height: hdr_box[:height] },
                             size: font_size, color: HEADER_TEXT_COLOR, bold: true, align: :center, anchor: valign, font: hdr_font)
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
          pitch = font_line_pitch_ratio(hdr_font)
          active_rows.each do |r|
            max_item_sz = grouped_rows[r].map { |it| it[:size] }.max || font_size
            row_heights[r] = [(max_item_sz * pitch).round(2) + 2.0, max_item_sz + 4.0].max
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
                         align: align, font: hdr_font)
            cur_y -= r_h

            if idx < active_rows.size - 1
              sep_y = cur_y - (scaled_item_gap / 2.0)
              line_w = [hdr_box[:width] * 0.45, 130.0].min
              lx = hdr_box[:x] + (hdr_box[:width] - line_w) / 2.0
              add_hline(ctx, doc, page, (gfx_layer || layer), lx, sep_y, line_w, SEP_COLOR, 0.5)
              cur_y -= scaled_item_gap
            end
          end
        end

        # ------------------------------------------------------------------
        # Слоты (информационные колонки спецификаций и истории)
        # ------------------------------------------------------------------

        def render_modular_slots(doc, page, layer, content, page_cfg, pt, ctx, rctx, gfx_layer = nil)
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

              render_modular_slot_card(doc, page, layer, slot_box, "info_lines", q_cfg, opacity, target_slot, ctx, rctx, gfx_layer)
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
            render_modular_slot_card(doc, page, layer, slot_box, content_type, cfg, opacity, slot_id, ctx, rctx, gfx_layer)
          end
        end

        # Карточка слота (информационный блок)
        def render_modular_slot_card(doc, page, layer, slot_box, content_type, cfg, _opacity, slot_id, ctx, rctx, gfx_layer = nil)
          pad = 4
          in_x = slot_box[:x] + pad
          in_y = slot_box[:y] - pad
          in_w = [slot_box[:width] - (pad * 2), 10.0].max
          in_h = [slot_box[:height] - (pad * 2), 10.0].max

          slot_font = if cfg[:font_family] && !cfg[:font_family].to_s.strip.empty?
                        FontService.layout_font_family(cfg[:font_family])
                      else
                        ctx[:font]
                      end

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
            txt_h = estimate_text_height(txt, font_size, in_w, slot_font, ctx[:text_bold])
            txt_box_h = [txt_h + 2.0, in_h].min
            if valign == :bottom
              target_top_y = [in_bottom_y + txt_box_h, in_y].min
              add_bounded_text(ctx, doc, page, layer, txt, { x: in_x, y: target_top_y, width: in_w, height: txt_box_h },
                               size: font_size, color: CUSTOM_TEXT_COLOR, align: align, anchor: :bottom, font: slot_font)
            elsif valign == :center
              offset = [(in_h - txt_box_h) / 2.0, 0.0].max
              target_top_y = in_y - offset
              add_bounded_text(ctx, doc, page, layer, txt, { x: in_x, y: target_top_y, width: in_w, height: txt_box_h },
                               size: font_size, color: CUSTOM_TEXT_COLOR, align: align, anchor: :top, font: slot_font)
            else
              add_bounded_text(ctx, doc, page, layer, txt, { x: in_x, y: in_y, width: in_w, height: in_h },
                               size: font_size, color: CUSTOM_TEXT_COLOR, align: align, anchor: valign, font: slot_font)
            end
            return
          end

          items = []
          line_aligns = cfg[:line_aligns] || cfg["line_aligns"] || {}
          line_sizes = cfg[:line_font_sizes] || cfg["line_font_sizes"] || {}
          line_colors = cfg[:line_colors] || cfg["line_colors"] || {}

          if lines && lines.is_a?(Array)
            line_show_titles = cfg[:line_show_titles] || cfg["line_show_titles"] || {}
            block_show_titles = cfg[:show_titles] != false && cfg["show_titles"] != false && cfg[:show_titles] != "false" && cfg["show_titles"] != "false"

            lines.each do |line_key|
              k_str = line_key.to_s
              k_sym = line_key.to_sym rescue nil

              show_title = if line_show_titles.key?(k_str)
                             line_show_titles[k_str] != false && line_show_titles[k_str] != "false"
                           elsif k_sym && line_show_titles.key?(k_sym)
                             line_show_titles[k_sym] != false && line_show_titles[k_sym] != "false"
                           else
                             block_show_titles
                           end

              line_text = InfoLineResolver.resolve_formatted(rctx, line_key, show_title: show_title)
              next if line_text.nil? || line_text.to_s.empty?

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
            estimate_text_height(it[:text], it[:size], in_w, slot_font, ctx[:text_bold])
          end
          total_items_h = item_heights.sum + ([items.size - 1, 0].max * item_gap)

          slot_scale = 1.0
          if total_items_h > in_h && total_items_h > 0
            slot_scale = [in_h / total_items_h, 0.6].max
            item_gap = (item_gap * slot_scale).round(2)
            item_heights = items.map do |it|
              sc_sz = (it[:size] * slot_scale).round(2)
              estimate_text_height(it[:text], sc_sz, in_w, slot_font, ctx[:text_bold])
            end
            total_items_h = item_heights.sum + ([items.size - 1, 0].max * item_gap)
          end

          # Если даже после масштабирования суммарная высота превышает доступную, уменьшаем межстрочные интервалы
          if total_items_h > in_h && items.size > 1
            excess = total_items_h - in_h
            gap_reduction = [excess / (items.size - 1), [item_gap - 1.0, 0.0].max].min
            if gap_reduction > 0
              item_gap = (item_gap - gap_reduction).round(2)
              total_items_h = item_heights.sum + ([items.size - 1, 0].max * item_gap)
            end
          end

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
            if it[:key] == "workflow_stadia" && it[:text].to_s.include?("\n")
              draw_stadia_check_rows(ctx, doc, page, layer, it, { x: in_x, y: cur_y, width: in_w, height: h },
                                     slot_font, slot_scale, (gfx_layer || layer))
            else
              add_bounded_text(ctx, doc, page, layer, it[:text], { x: in_x, y: cur_y, width: in_w, height: h },
                               size: (it[:size] * slot_scale).round(2), color: it[:color], align: it[:align] || align, anchor: :top, font: slot_font)
            end
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
              add_hline(ctx, doc, page, (gfx_layer || layer), lx, sep_y, line_w, SEP_COLOR, 0.5)
              cur_y -= item_gap
            end
          end
        end

        # Отношение высоты строки (line pitch) к кеглю шрифта в LayOut с запасом для предотвращения обрезания
        def font_line_pitch_ratio(font_name)
          f = font_name.to_s.downcase
          if f.include?("oswald") || f.include?("din")
            1.75
          elsif f.include?("sofia")
            1.38
          elsif f.include?("roboto")
            1.28
          elsif f.include?("ubuntu")
            1.25
          else
            1.35
          end
        end

        # Отношение средней ширины символа к кеглю шрифта
        def font_char_width_ratio(font_name)
          f = font_name.to_s.downcase
          if f.include?("extra")
            0.38
          elsif f.include?("sofia")
            0.43
          elsif f.include?("ubuntu") || f.include?("oswald") || f.include?("din")
            0.45
          elsif f.include?("roboto")
            0.48
          else
            0.50
          end
        end

        # Точный расчет высоты многострочного текста в pt для LayOut FormattedText
        def estimate_text_height(text, size_pt, width_pt, font_name = nil, bold = false)
          return 0.0 if text.to_s.empty?

          # Жирное начертание шире — учитываем в коэффициенте символа
          char_ratio = font_char_width_ratio(font_name) * (bold ? 1.05 : 1.0)
          pitch_ratio = font_line_pitch_ratio(font_name)

          # Учитываем перенос по словам: эффективная ширина ~90% от геометрической границы
          cpl = [((width_pt.to_f * 0.90) / (size_pt.to_f * char_ratio)).floor, 1].max
          lines = text.to_s.split("\n", -1).sum { |seg| [(seg.length.to_f / cpl).ceil, 1].max }
          lines_count = [lines, 1].max

          # Высота строк + базовый вертикальный запас (+2.5 pt на внутренние отступы блока и выносные элементы шрифта)
          ((lines_count * size_pt.to_f * pitch_ratio) + 2.5).round(2)
        end

        # ------------------------------------------------------------------
        # Нижний колонтитул (зеркало PageBase#render_modular_footer)
        # ------------------------------------------------------------------

        def render_modular_footer(doc, page, layer, ftr_box, cfg, ctx, rctx)
          raw_valign = (cfg[:valign] || cfg["valign"] || "bottom").to_s
          valign = (raw_valign == "top") ? :top : :bottom
          font_size = (cfg[:font_size] || cfg["font_size"] || 8.5).to_f
          footer_font = if cfg[:font_family] && !cfg[:font_family].to_s.strip.empty?
                          FontService.layout_font_family(cfg[:font_family])
                        else
                          ctx[:font]
                        end

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

          footer_opts = { size: font_size, color: FOOTER_COLOR, font: footer_font, anchor: valign }

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

          # Координаты штампа в правом нижнем углу
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
