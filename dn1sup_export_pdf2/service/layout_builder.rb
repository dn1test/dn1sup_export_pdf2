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
      # Страницы строятся по шаблону (из layout.yaml):
      #   image_4_3 — видовой экран модели (Layout::SketchUpModel) или растровый оверрайд (Layout::Image),
      #   params    — пользовательские параметры шаблона со свободным размещением
      #               на странице (X/Y в % рабочей области, выравнивание, кегль, цвет)
      #
        # Документ формируется в многослойной структуре (Viewports, Graphics, Content)
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
        PARAM_TEXT_COLOR = "0F172A" # текст параметров по умолчанию

        # Заголовок параметра печатается ЗАГЛАВНЫМИ буквами кеглем на эту
        # величину больше кегля значения. Подписи внутри строк блоков-групп
        # («Помещение: Гостиная») — только заглавными: LayOut держит максимум
        # два шрифтовых рана в одном тексте, а подписей в блоке несколько.
        PARAM_LABEL_SIZE_DELTA = 1.0

        # Проверка доступности LayOut Ruby API в текущем окружении
        def available?
          defined?(::Layout) && defined?(::Layout::Document)
        end

        # Основной метод экспорта через LayOut API
        def export(controller, custom_output_path = nil, &progress_block)
          unless available?
            raise Locale.t(:lb_layout_missing)
          end

          project_data = controller.project_data
          model        = controller.model
          settings     = project_data.pdf_settings

          enabled_scenes = project_data.scenes.select(&:enabled)
          if enabled_scenes.empty?
            raise Locale.t(:lb_no_scenes)
          end

          pdf_path = custom_output_path || controller.send(:resolve_default_pdf_path)

          # Целевой PDF открыт в просмотрщике → запись упадёт с EACCES.
          # Предупреждаем сразу и не пытаемся сохранить.
          if Model::FileOpener.file_locked?(pdf_path)
            raise Locale.t(:lb_pdf_locked, path: pdf_path)
          end

          FileUtils.mkdir_p(File.dirname(pdf_path))

          temp_images = []
          begin
            total_pages = enabled_scenes.size
            progress_block&.call(0, total_pages, Locale.t(:lb_init))

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
              layers[:viewport]   = doc.layers.add("DN1SUP_Viewports", false) rescue first_layer
              layers[:graphics]   = doc.layers.add("DN1SUP_Graphics", false) rescue (layers[:viewport] || first_layer)
              layers[:content]    = doc.layers.add("DN1SUP_Content", false) rescue (layers[:graphics] || first_layer)
              layers[:default]    = layers[:content] || first_layer
            else
              first_layer = (doc.respond_to?(:layers) && doc.layers) ? (doc.layers.first rescue nil) : nil
              layers = { default: first_layer, viewport: first_layer, graphics: first_layer, content: first_layer }
            end

            # Отключение фоновой сетки для чистого вывода
            if doc.respond_to?(:grid) && doc.grid
              doc.grid.show_grid = false if doc.grid.respond_to?(:show_grid=)
              doc.grid.print_grid = false if doc.grid.respond_to?(:print_grid=)
            end

            ctx = build_context(project_data, model, font_family)
            ctx[:page_w_pt] = in2pt(page_w_in)
            ctx[:page_h_pt] = in2pt(page_h_in)

            # 3. Построение страниц по модульной сетке
            enabled_scenes.each_with_index do |scene_item, idx|
              page_index = idx + 1
              progress_block&.call(page_index, total_pages, Locale.t(:lb_page, cur: page_index, total: total_pages, name: scene_item.name))

              page = if idx.zero?
                       (doc.pages.respond_to?(:initial) ? doc.pages.initial : doc.pages.first) || doc.pages.add(scene_item.name)
                     else
                       doc.pages.add(scene_item.name)
                     end
              page.name = scene_item.name if page.respond_to?(:name=)

              render_modular_page(doc, page, layers, scene_item, page_index, total_pages, page_w_in, page_h_in, margin_in, ctx, temp_images)
            end

              progress_block&.call(total_pages, total_pages, Locale.t(:lb_export_pdf))

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
              begin
                doc.export(pdf_path, export_opts)
              rescue StandardError, ScriptError => e
                warn "[DN1SUP Export PDF] Экспорт с опциями сжатия не удался (#{e.message}) — повтор без опций"
                doc.export(pdf_path)
              end
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
                  # Копия открыта в просмотрщике — не трогаем её, экспорт не валим
                  if Model::FileOpener.file_locked?(last_candidate)
                    warn "Предупреждение: копия _last.pdf открыта в программе просмотра и не обновлена: #{last_candidate}"
                  else
                    FileUtils.mkdir_p(File.dirname(last_candidate))
                    FileUtils.cp(pdf_path, last_candidate)
                    controller.last_pdf_path = last_candidate
                  end
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

            # 6. Резервная копия .skp + привязка её пути к самой свежей записи истории
            if settings[:save_skp_backup] && model && model.respond_to?(:path) && !model.path.empty?
              skp_backup = controller.save_skp_backup
              if skp_backup && project_data.respond_to?(:stamp_history_skp_link!)
                project_data.stamp_history_skp_link!(skp_backup)
              end
            end

            # 7. Запись данных в YAML (проект + настройки/шаблоны расширения)
            if defined?(Model::SessionStore)
              Model::SessionStore.flush(model) if model
            elsif project_data.respond_to?(:save_project_yaml)
              project_data.save_project_yaml(model) if model
              project_data.save_program_settings
            end

            progress_block&.call(total_pages, total_pages, Locale.t(:lb_done))

            # 8. Открытие PDF файла системной программой по умолчанию
            # Открываем именно копию «_last» рядом с .skp, если она создана
            if auto_open_enabled?(settings)
              opened = controller.last_pdf_path || pdf_path
              unless Model::FileOpener.open_path(opened)
                warn "Предупреждение: PDF создан (#{opened}), но не открылся автоматически — откройте его вручную."
              end
            end

            pdf_path
          ensure
            # Удаление временных PNG после экспорта
            RenderService.safe_cleanup_files(temp_images)
          end
        end

        private

        # Защитное чтение флага автооткрытия: ключ может прийти символьным или
        # строковым (YAML-настройки / payload диалога)
        def auto_open_enabled?(settings)
          value = settings[:auto_open_pdf] || settings["auto_open_pdf"]
          !value.nil? && value != false
        end

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

        # Поля страницы в дюймах (margin_mm -> pt -> in).
        # Диапазон 0..100 мм (0..~283pt) — последняя линия защиты от
        # отрицательных/гигантских полей, заданных мимо sanitize_pdf_settings
        MAX_MARGIN_MM = 100.0
        MAX_MARGIN_PT = MAX_MARGIN_MM * PT_PER_INCH / 25.4

        def resolve_margin_inches(settings)
          if settings.key?(:margin_mm) && !settings[:margin_mm].nil?
            settings[:margin_mm].to_f.clamp(0.0, MAX_MARGIN_MM) * PT_PER_INCH / 25.4 / PT_PER_INCH
          elsif settings.key?("margin_mm") && !settings["margin_mm"].nil?
            settings["margin_mm"].to_f.clamp(0.0, MAX_MARGIN_MM) * PT_PER_INCH / 25.4 / PT_PER_INCH
          elsif settings.key?(:margin) && !settings[:margin].nil?
            settings[:margin].to_f.clamp(0.0, MAX_MARGIN_PT) / PT_PER_INCH
          elsif settings.key?("margin") && !settings["margin"].nil?
            settings["margin"].to_f.clamp(0.0, MAX_MARGIN_PT) / PT_PER_INCH
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
            secondary_color: settings[:secondary_color] || "64748B"
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
          get_block_config_from(get_page_cfg(ctx, pt), block_id)
        end

        def get_block_config_from(page_cfg, block_id)
          cfg = page_cfg[block_id] || page_cfg[block_id.to_s] || {}
          cfg.is_a?(Hash) ? cfg : {}
        end

        # ------------------------------------------------------------------
        # Мастер-шаблон: основа для всех страниц, кроме обложек.
        # Включается звездой в списке шаблонов (pdf_settings:
        # master_template_enabled + master_template_key). Параметры мастера
        # идут первыми в зонных стеках, параметры собственного шаблона
        # страницы дополняются рядом; общие настройки стека (line_gap,
        # line_enabled), шрифт страницы и видовой экран (image_4_3) — от
        # мастера. Обложки (cover и шаблоны на базе cover) не затрагиваются.
        # ------------------------------------------------------------------

        # Страница-обложка: встроенный шаблон cover или пользовательский
        # шаблон на его базе (метаданные _base_type)
        def cover_page?(ctx, pt)
          return true if pt.to_s.eql?("cover")

          cfg = get_page_cfg(ctx, pt)
          base = cfg[:_base_type] || cfg["_base_type"]
          base.to_s.strip.downcase.eql?("cover")
        end

        # Активный мастер-шаблон: включен и существует в custom_layouts.
        # Несуществующий ключ (удалённый шаблон, набор без него) — фолбэк.
        def active_master_cfg(ctx)
          settings = ctx[:settings] || {}
          enabled = settings[:master_template_enabled] || settings["master_template_enabled"]
          is_on = enabled == true || enabled.to_s.strip.downcase == "true"
          return nil unless is_on

          key = (settings[:master_template_key] || settings["master_template_key"]).to_s.strip
          return nil if key.empty?

          custom = settings[:custom_layouts] || {}
          cfg = custom[key] || custom[key.to_sym] || {}
          cfg.is_a?(Hash) && !cfg.empty? ? cfg : nil
        end

        # Объединение конфига страницы с мастер-шаблоном. Возвращает исходный
        # page_cfg, если мастер не применим (выключен, обложка, страница уже
        # на мастере). Настройки в ctx не мутируются — возвращается копия.
        def merge_master_page_cfg(ctx, pt, page_cfg)
          # «Без шаблона» (пустой page_type): не применяется никакой шаблон,
          # включая мастер-шаблон
          return page_cfg if pt.to_s.strip.empty?

          master_cfg = active_master_cfg(ctx)
          return page_cfg if master_cfg.nil? || cover_page?(ctx, pt)

          master_key = (ctx[:settings][:master_template_key] || ctx[:settings]["master_template_key"]).to_s.strip
          return page_cfg if master_key.eql?(pt.to_s)

          merged = page_cfg.merge(master_cfg)
          merged[:params] = cfg_params(master_cfg) + cfg_params(page_cfg)
          merged
        end

        def cfg_params(cfg)
          p = cfg[:params] || cfg["params"]
          p.is_a?(Array) ? p.dup : []
        end

        def block_visible?(page_cfg, block_id)
          cfg = page_cfg[block_id] || page_cfg[block_id.to_s] || {}
          return true if cfg.nil? || cfg.empty?

          val = cfg.key?(:visible) ? cfg[:visible] : cfg["visible"]
          return true if val.nil?

          !(val == false || val.to_s.strip.downcase == "false" || val.to_s.strip == "0")
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

        # Ограниченный текстовый блок (box — координаты блока, y — верхняя грань, в pt).
        # opts[:label_len]/opts[:label_size] — второй стилевой ран для заголовка
        # параметра: первые label_len символов печатаются кеглем label_size
        # (LayOut поддерживает максимум два рана в одном тексте)
        def add_bounded_text(ctx, doc, page, layer, text, box, opts = {})
          return if text.to_s.empty?

          # Запас высоты (+1.5 pt) гарантирует, что LayOut не обрежет нижние выносные элементы
          extra_h = 1.5
          text_ent = ::Layout::FormattedText.new(text.to_s, make_bounds_pt(ctx, box[:x], box[:y], box[:width], box[:height] + extra_h))
          text_ent.grow_mode = ::Layout::FormattedText::GROW_MODE_BOUNDED
          style = text_ent.style(0)
          apply_text_style!(style, opts, ctx)
          text_ent.apply_style(style)
          apply_label_run!(text_ent, opts, ctx)
          doc.add_entity(text_ent, layer, page)
          text_ent
        rescue StandardError => e
          warn "Ошибка добавления текста LayOut: #{e.message}"
          nil
        end

        # Ран заголовка: первые label_len символов текста кеглем label_size,
        # остальное оформление (шрифт, цвет, жирность, выравнивание) — из opts.
        # Сбой рана не валит отрисовку — заголовок останется кеглем значения.
        def apply_label_run!(text_ent, opts, ctx)
          len = opts[:label_len].to_i
          return if len <= 0 || !opts[:label_size]

          lstyle = text_ent.style(0)
          apply_text_style!(lstyle, opts.merge(size: opts[:label_size]), ctx)
          text_ent.apply_style(lstyle, 0, len)
        rescue StandardError => e
          warn "Заголовок параметра напечатан кеглем значения (#{e.message})"
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
              # Имя центрируется самим LayOut на ширину зоны — точно по центру
              # колонки при любой фактической ширине строки; квадрат-чекбокс
              # ставится слева от оценочного начала текста.
              w_est = [name.length * size * font_char_width_ratio(font_name), box[:width] * 0.85].min
              text_box = { x: box[:x], y: y_top, width: box[:width], height: pitch }
              text_align = :center
              sq_x = [[box[:x] + (box[:width] - w_est) / 2.0 - side - gap, box[:x]].max,
                      box[:x] + box[:width] - side].min
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

        # Тонкая горизонтальная линия-разделитель между параметрами зоны
        # («Линия» в шапке карточки). Небольшая — шириной с текст строки,
        # выравнивается по колонке. Координаты в pt, y — уровень линии.
        def add_thin_line(ctx, doc, page, layer, x_pt, y_pt, width_pt, color_hex)
          return if width_pt <= 0

          p1 = ::Geom::Point2d.new(pt2in(x_pt), pt2in(lay_y(ctx, y_pt)))
          p2 = ::Geom::Point2d.new(pt2in(x_pt + width_pt), pt2in(lay_y(ctx, y_pt)))
          path = ::Layout::Path.new(p1, p2)
          style = path.style
          style.stroked = true if style.respond_to?(:stroked=)
          style.solid_filled = false if style.respond_to?(:solid_filled=)
          style.stroke_width = pt2in(0.3) if style.respond_to?(:stroke_width=)
          style.stroke_color = layout_color(color_hex) if style.respond_to?(:stroke_color=)
          path.style = style
          doc.add_entity(path, layer, page)
        rescue StandardError => e
          warn "Ошибка отрисовки линии-разделителя параметров: #{e.message}"
          nil
        end

        # Ширина маленького разделителя «Линия» — ширина текста строки (не всей
        # колонки). Точное измерение: пробный текст добавляется в документ —
        # LayOut пересчитывает bounds с учетом шрифта и кегля — и удаляется.
        # Если измерение недоступно (тестовые моки), оценка по числу символов.
        def separator_width_pt(ctx, doc, page, layer, item, max_width_pt)
          if item[:label_size] && !item[:label].to_s.empty?
            # Заголовок печатается ЗАГЛАВНЫМИ кеглем +1 — меряем его отдельно
            # и берем самую широкую строку параметра (заголовок или значение)
            value_text =
              if item[:stadia]
                item[:text].to_s.gsub(/^\[[✓ ]\]\s*/, "")
              else
                item[:render_text].to_s.split("\n", 2)[1].to_s
              end
            w_label = measure_text_width_pt(doc, page, layer, item[:label], item[:label_size], item[:font], ctx[:text_bold])
            w_label = est_line_width_pt(item[:label], item[:label_size], item[:font]) if w_label.nil?
            w_value = measure_text_width_pt(doc, page, layer, value_text, item[:size], item[:font], ctx[:text_bold])
            w_value = est_line_width_pt(value_text, item[:size], item[:font]) if w_value.nil?
            w = [w_label.to_f, w_value.to_f].max
          else
            est_text =
              if item[:stadia]
                item[:text].to_s.gsub(/^\[[✓ ]\]\s*/, "")
              else
                item[:render_text].to_s
              end
            w = measure_text_width_pt(doc, page, layer, est_text, item[:size], item[:font], ctx[:text_bold])
            w = est_line_width_pt(est_text, item[:size], item[:font]) if w.nil?
          end
          # У стадий впереди еще квадрат-чекбокс
          w += item[:size] * 1.15 if item[:stadia]
          w.round(2).clamp(1.0, max_width_pt)
        end

        # Фактическая ширина текста в pt: bounds у Layout::FormattedText
        # пересчитывается только после добавления в документ, поэтому пробу
        # добавляем и тут же убираем. Вне реального LayOut вернет nil.
        def measure_text_width_pt(doc, page, layer, text, size_pt, font_name, bold)
          return nil if text.nil? || text.to_s.empty?

          probe = ::Layout::FormattedText.new(text.to_s, ::Geom::Point2d.new(0, 0), ::Layout::FormattedText::ANCHOR_TYPE_TOP_LEFT)
          style = probe.style(0)
          apply_text_style!(style, { size: size_pt, font: font_name, bold: bold, align: :left, anchor: :top })
          probe.apply_style(style)
          doc.add_entity(probe, layer, page)
          w =
            begin
              probe.bounds.width * PT_PER_INCH
            rescue StandardError
              nil
            end
          # Пробу убираем при любом исходе — она не должна попасть в экспорт
          begin
            doc.remove_entity(probe)
          rescue StandardError
            nil
          end
          w
        rescue StandardError
          nil
        end

        # Оценка ширины текста по числу символов самой длинной строки
        def est_line_width_pt(text, size_pt, font_name)
          longest = text.to_s.split("\n", -1).map(&:length).max.to_i
          longest * size_pt * font_char_width_ratio(font_name)
        end

        # ------------------------------------------------------------------
        # Рендер страницы по модульной сетке
        # ------------------------------------------------------------------

        def render_modular_page(doc, page, layer, scene_item, page_index, total_pages, page_w_in, page_h_in, margin_in, ctx, temp_images)
          ctx[:page_w_pt] ||= in2pt(page_w_in || 11.6929)
          ctx[:page_h_pt] ||= in2pt(page_h_in || 8.2677)

          pt = (scene_item.page_type || :general).to_sym
          page_cfg = get_page_cfg(ctx, pt)
          # Мастер-шаблон как основа (все страницы, кроме обложек):
          # параметры мастера + параметры собственного шаблона страницы
          page_cfg = merge_master_page_cfg(ctx, pt, page_cfg)

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

          # 1. Видовой экран чертежа/модели (Layout::SketchUpModel / Layout::Image)
          is_viewport_on = if scene_item && scene_item.respond_to?(:viewport_visible) && !scene_item.viewport_visible.nil?
                             scene_item.viewport_visible != false
                           else
                             block_visible?(page_cfg, :image_4_3)
                           end

          if is_viewport_on
            img_cfg = get_block_config_from(page_cfg, :image_4_3)
            render_image_block(doc, page, layer, scene_item, full_page_content, img_cfg, ctx, temp_images, pt)
          end

          page_font = if page_cfg[:font_family] && !page_cfg[:font_family].to_s.strip.empty?
                        FontService.layout_font_family(page_cfg[:font_family])
                      else
                        ctx[:font]
                      end
          page_ctx = (page_font != ctx[:font]) ? ctx.merge(font: page_font) : ctx

          # 2. Параметры шаблона со свободным размещением
          render_params(doc, page, cnt_layer, gfx_layer, content, page_cfg, page_ctx, rctx)
        end

        # ------------------------------------------------------------------
        # Блок видового экрана (Layout::SketchUpModel с режимами Vector/Raster/Hybrid либо Layout::Image)
        # ------------------------------------------------------------------

        def render_image_block(doc, page, layer, scene_item, content, img_cfg, ctx, temp_images, pt)
          # Фон сцены (небо/земля): посценный флаг с фолбэком на настройку слота шаблона
          show_bg = if scene_item && scene_item.respond_to?(:viewport_background) && !scene_item.viewport_background.nil?
                      scene_item.viewport_background != false
                    else
                      slot_bg = img_cfg[:show_background] || img_cfg["show_background"]
                      !(slot_bg == false || slot_bg.to_s == "false" || slot_bg == 0 || slot_bg.to_s == "0")
                    end
          # Водяные знаки (DisplayWatermarks) — отдельный от фона посценный флаг;
          # для страниц без сцены наследуем значение фона (прежнее поведение)
          show_wm = if scene_item && scene_item.respond_to?(:viewport_watermarks) && !scene_item.viewport_watermarks.nil?
                      scene_item.viewport_watermarks != false
                    else
                      show_bg
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
                         when "5:4"  then 5.0 / 4.0
                         when "4:5"  then 4.0 / 5.0
                         when "page" then content[:w] / content[:h]
                         when "custom"
                           cw = (ctx[:settings][:custom_ratio_w] || ctx[:settings]["custom_ratio_w"] || 16).to_f
                           ch = (ctx[:settings][:custom_ratio_h] || ctx[:settings]["custom_ratio_h"] || 9).to_f
                           cw = 16.0 if cw <= 0.0
                           ch = 9.0 if ch <= 0.0
                           cw / ch
                         else 4.0 / 3.0
                         end

          raw_scale = if scene_item && scene_item.respond_to?(:scale_pct) && scene_item.scale_pct.to_f > 0
                        scene_item.scale_pct.to_f
                      else
                        (img_cfg[:scale_pct] || img_cfg["scale_pct"] || 100).to_f
                      end
          raw_scale = 100.0 if raw_scale <= 0.0 || raw_scale > 100.0
          scale_factor = raw_scale / 100.0

          align_h = if scene_item && scene_item.respond_to?(:align_h) && !scene_item.align_h.to_s.strip.empty?
                      scene_item.align_h.to_s.strip.downcase
                    else
                      (img_cfg[:align_h] || img_cfg["align_h"] || "center").to_s.strip.downcase
                    end
          align_v = if scene_item && scene_item.respond_to?(:align_v) && !scene_item.align_v.to_s.strip.empty?
                      scene_item.align_v.to_s.strip.downcase
                    else
                      (img_cfg[:align_v] || img_cfg["align_v"] || "center").to_s.strip.downcase
                    end

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

          # Размещение на странице по выравниванию сцены (по умолчанию — по центру)
          img_x = case align_h
                  when "left"  then content[:left]
                  when "right" then content[:left] + content[:w] - img_w
                  else content[:left] + ((content[:w] - img_w) / 2.0)
                  end
          img_y = case align_v
                  when "top"    then content[:top]
                  when "bottom" then content[:top] - content[:h] + img_h
                  else content[:top] - ((content[:h] - img_h) / 2.0)
                  end

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
                temp_skp = File.join(Dir.tmpdir, "dn1sup_model_#{$$}_#{Time.now.to_i}.skp")
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

                # Отключение фона видового экрана (небо/земля) в LayOut при выключенном фоне.
                # Ограничение: в LayOut API нет отдельного управления водяными знаками
                # (есть только display_background=), поэтому в гибридном режиме
                # водяные знаки следуют за переключателем фона, как раньше.
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
          # Пропорции снимка = пропорции кадра ЭТОЙ страницы (scene.aspect_ratio,
          # фолбэк — блок шаблона): target_ratio вычислен выше по scene_item.
          # Раньше здесь пропорции брались из OverlayService по выбранной
          # (первой) странице и кэшировались по ключу шаблона — из-за этого все
          # страницы шаблона получали пропорции первой страницы.
          render_opts = {
            image_width:        ctx[:settings][:image_width],
            render_quality:     ctx[:settings][:render_quality] || "medium",
            scale_multiplier:   ctx[:settings][:scale_multiplier] || "2.0",
            scale_factor:       line_mult || (ctx[:settings][:scale_factor] || 2.0),
            annotation_font_size: ctx[:settings][:annotation_font_size],
            page_size:          ctx[:settings][:page_size] || "A4",
            antialias:          ctx[:settings].fetch(:antialias, true),
            show_background:    show_bg,
            show_watermarks:    show_wm,
            aspect_ratio:       target_ratio,
            image_aspect_ratio: ctx[:settings][:image_aspect_ratio],
            image_format:       ctx[:settings][:image_format] || "png",
            compress_pdf:       ctx[:settings][:compress_pdf]
          }
          scene_obj = scene_item.respond_to?(:scene_ref) ? scene_item.scene_ref : nil
          if scene_obj.nil? && ctx[:model] && ctx[:model].respond_to?(:pages) && scene_item.respond_to?(:name)
            scene_obj = ctx[:model].pages[scene_item.name.to_s] rescue nil
          end
          image_path = RenderService.render_scene_temp(ctx[:model], scene_obj, render_opts)
          temp_images << image_path if image_path

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
        # Параметры шаблона: размещение по зонам страницы
        # ------------------------------------------------------------------

        # Отступ между параметрами в одной зоне по умолчанию (мм);
        # переопределяется общей настройкой шаблона line_gap
        # («размер между строками» в шапке карточки «Параметры страницы»)
        PARAM_ZONE_GAP_MM = 2.5

        # Авто-подпись параметра, когда «Заголовок» включён, а текст подписи
        # (label) не задан: короткие печатные формулировки без эмодзи.
        # Зеркало AUTO_PARAM_LABELS в dialog/html/app.js — держать синхронно.
        AUTO_PARAM_LABELS = {
          "project.articul"      => "Артикул",
          "project.furniture_name" => "Изделие",
          "project.room_name"    => "Помещение",
          "project.address"      => "Адрес",
          "project.company"      => "Компания",
          "project.materials"    => "Материалы и фурнитура",
          "project.lighting"     => "Подсветка и Техника",
          "customer.id"          => "ID заказчика",
          "customer.name"        => "Заказчик",
          "customer.phone"       => "Телефон",
          "customer.email"       => "Email",
          "workflow.author"      => "Автор",
          "workflow.price"       => "Стоимость",
          "workflow.start_date"  => "Дата начала",
          "workflow.end_date"    => "Дата сдачи",
          "workflow.duration"    => "Длительность",
          "workflow.rate"        => "Ставка руб./час",
          "workflow.version"     => "Версия",
          "workflow.revision"    => "Ревизия",
          "workflow.version_rev" => "Версия#Ревизия",
          "workflow.date"        => "Дата",
          "workflow.stadia"      => "Стадии проекта",
          "workflow.last_edit"   => "Последние изменения",
          "workflow.history"     => "История правок",
          "scene.name"           => "Сцена",
          "scene.description"    => "Описание",
          "page.number_total"    => "Страница",
          "page.toc"             => "Содержание"
        }.freeze

        # Текст подписи параметра: поле label без хвостовых «:» (двоеточие после
        # метки добавляет рендерер, иначе на листе печатается «Артикул:: значение»)
        def param_label_text(param)
          raw = (param[:label] || param["label"]).to_s.strip
          raw.empty? ? "" : raw.sub(/:+\s*\z/, "").strip
        end

        # Флаг «Заголовок» параметра: отсутствие поля трактуется как включено
        # (для детей блоков normalize_template_params проставляет false явно)
        def param_show_label?(param, default: true)
          raw = param.key?(:show_label) ? param[:show_label] : param["show_label"]
          raw.nil? ? default : !(raw == false || raw.to_s.strip.downcase == "false")
        end

        # Эффективная подпись параметра на листе: заданный label, иначе
        # авто-подпись из источника; для папок спецификаций — название раздела
        # (объединённый dir.N.line без подписи — заголовок уже внутри значения).
        # Пустая строка — заголовок не печатается даже при включённом «Заголовок».
        def effective_param_label(source, label, rctx)
          return label unless label.empty?

          src = source.to_s.strip
          # Условный источник «Заказчик / Компания»: подпись тоже условная —
          # коммерческий проект печатает «Компания», бытовой — «Заказчик»
          if src == "customer.name_or_company"
            info = (rctx && rctx[:info]) || {}
            return info[:trade].to_s == "1" ? "Компания" : "Заказчик"
          end
          return AUTO_PARAM_LABELS[src] if AUTO_PARAM_LABELS.key?(src)

          m = src.match(/\Adir\.(\d+)\.(title|description|line)\z/)
          if m
            return "" if m[2] == "line"

            idx = m[1].to_i
            base = InfoLineResolver.dir_field(rctx, idx, :title).to_s.strip
            base = "Раздел #{idx + 1}" if base.empty?
            return m[2] == "title" ? "#{base} — название" : "#{base} — спецификация"
          end
          ""
        end

        # Колонка зоны по выравниванию: «слева» — колонка у левого края,
        # «справа» — у правого края, «центр» — симметрично относительно середины.
        # y_top/box_h задаются расчетом высоты группы (в pt, y — верх коробки).
        def param_zone_box(content, align, y_top, box_h)
          case align
          when :center
            w = content[:w] * 0.80
            x = content[:left] + ((content[:w] - w) / 2.0)
          when :right
            w = content[:w] * 0.20
            x = content[:left] + content[:w] - w
          else
            w = content[:w] * 0.20
            x = content[:left]
          end
          { x: x, y: y_top, width: w, height: [box_h, 10.0].max }
        end

        # Расчет высоты многострочного текста в pt (запас на выносные элементы)
        def estimate_text_height(text, size_pt, width_pt, font_name = nil, bold = false)
          return 0.0 if text.to_s.empty?

          char_ratio = font_char_width_ratio(font_name) * (bold ? 1.05 : 1.0)
          pitch_ratio = font_line_pitch_ratio(font_name)

          # Эффективная ширина ~90% от геометрической границы (перенос по словам)
          cpl = [((width_pt.to_f * 0.90) / (size_pt.to_f * char_ratio)).floor, 1].max
          lines = text.to_s.split("\n", -1).sum { |seg| [(seg.length.to_f / cpl).ceil, 1].max }
          lines_count = [lines, 1].max

          ((lines_count * size_pt.to_f * pitch_ratio) + 2.5).round(2)
        end

        # Рендер всех параметров шаблона. Место параметра определяется его
        # выравниваниями: лево/центр/право задает колонку, верх/низ — привязку
        # группы к верхнему или нижнему краю рабочей области. Параметры одной
        # зоны складываются в столбик в порядке списка; зазор между строками
        # задает общая настройка шаблона line_gap («размер между строками», мм),
        # по умолчанию PARAM_ZONE_GAP_MM, а галочка «Линия» (line_enabled)
        # рисует тонкий разделитель между каждой парой соседних строк.
        # Формат: заголовок на своей строке, значение на следующей
        # ([Заголовок\n]Значение) — при включённом «Заголовок» и пустом label
        # подпись берётся из AUTO_PARAM_LABELS; заголовок печатается ЗАГЛАВНЫМИ
        # буквами кеглем на PARAM_LABEL_SIZE_DELTA больше кегля значения;
        # у детей блока подпись печатается перед значением внутри общей строки
        # блока («Помещение: Гостиная | …»); пустое значение или visible: false —
        # параметр не выводится. Стадии проекта (чек-лист) рисуются с квадратами.
        def render_params(doc, page, cnt_layer, gfx_layer, content, page_cfg, ctx, rctx)
          params = page_cfg[:params] || page_cfg["params"]
          return unless params.is_a?(Array)

          # 1. Видимые параметры с непустым значением, разложенные по девяти зонам.
          #    Блоки (group: true) объединяют вложенные параметры: горизонтальные
          #    — в одну строку с разделителем « | », вертикальные — друг под
          #    другом; стиль у блока свой.
          zones = {}
          params.each do |param|
            next unless param.is_a?(Hash)

            raw_vis = param.key?(:visible) ? param[:visible] : param["visible"]
            next if raw_vis == false || raw_vis.to_s.strip.downcase == "false" || raw_vis.to_s.strip == "0"

            is_group = param[:group] == true || param["group"] == true || param[:group].to_s == "true"
            stadia = false

            if is_group
              children = param[:params] || param["params"] || []
              values = children.filter_map do |child|
                next unless child.is_a?(Hash)

                child_src = (child[:source] || child["source"]).to_s.strip
                child_val = InfoLineResolver.resolve_param(rctx, child_src)
                next if child_val.nil? || child_val.to_s.strip.empty?

                child_val = child_val.to_s.strip
                # Подпись ребёнка печатается перед его значением внутри строки
                # блока («Помещение: Гостиная | Адрес: …»)
                if param_show_label?(child, default: false)
                  eff = effective_param_label(child_src, param_label_text(child), rctx)
                  child_val = "#{eff.upcase}: #{child_val}" unless eff.empty?
                end
                child_val
              end
              next if values.empty?
              # Направление блока: горизонтальный — одна строка через « | »,
              # вертикальный — каждый параметр на своей строке (старые блоки
              # без direction — горизонтальные)
              vertical = (param[:direction] || param["direction"]).to_s.strip.downcase == "vertical"
              value = vertical ? values.join("\n") : values.join(" | ")
            else
              source = (param[:source] || param["source"]).to_s.strip
              value = InfoLineResolver.resolve_param(rctx, source)
              next if value.nil? || value.to_s.strip.empty?
              stadia = source == "workflow.stadia"
              value = value.to_s
            end

            show_label = param_show_label?(param)
            # Хвостовые «:» из ввода пользователя срезаем (param_label_text):
            # разделитель заголовка и значения — перенос строки, двоеточие не нужно.
            # «Заголовок» включён, а текст не задан — берём авто-подпись из
            # источника (у блока своего источника нет).
            label = param_label_text(param)
            label = effective_param_label(source, label, rctx) if show_label && !is_group
            # Заголовок печатается ЗАГЛАВНЫМИ буквами независимо от источника подписи
            label = label.upcase

            # Итоговый текст с заголовком: заголовок на своей строке, значение —
            # на следующей. Высота блока считается по нему, иначе длинный
            # заголовок не учитывается и строки наезжают друг на друга
            render_text = (show_label && !label.empty?) ? "#{label}\n#{value}" : value

            align = case (param[:align] || param["align"] || "left").to_s.downcase.strip
                    when "center" then :center
                    when "right"  then :right
                    else :left
                    end
            valign = case (param[:valign] || param["valign"] || "top").to_s.downcase.strip
                     when "bottom" then :bottom
                     when "center" then :center
                     else :top
                     end

            size = (param[:font_size] || param["font_size"] || 10.0).to_f
            size = 10.0 if size <= 0.0

            # Шрифт параметра всегда наследуется из общих настроек (шрифт страницы)
            font = ctx[:font]

            raw_col = (param[:color] || param["color"] || PARAM_TEXT_COLOR).to_s.strip.sub(/^#/, "")
            raw_col = PARAM_TEXT_COLOR if raw_col.empty?

            (zones[[align, valign]] ||= []) << {
              stadia:      stadia,
              text:        value,
              render_text: render_text,
              label:       label,
              show_label:  show_label,
              label_size:  (show_label && !label.empty?) ? (size + PARAM_LABEL_SIZE_DELTA).round(2) : nil,
              size:        size,
              color:       raw_col,
              font:        font
            }
          end
          return if zones.empty?

          # Общие настройки стека параметров на уровне шаблона: «размер между
          # строками» (мм, один для всех параметров и блоков) и галочка «Линия»
          line_gap_mm = (page_cfg[:line_gap] || page_cfg["line_gap"] || PARAM_ZONE_GAP_MM).to_f.clamp(-2.0, 50.0)
          raw_line = page_cfg.key?(:line_enabled) ? page_cfg[:line_enabled] : page_cfg["line_enabled"]
          line_on = !raw_line.nil? && !(raw_line == false || raw_line.to_s.strip.downcase == "false" || raw_line.to_s.strip == "0")
          gap_pt = (line_gap_mm * PT_PER_INCH / 25.4).round(2)

          # 2. Высоты зон считаются заранее: они нужны и для расчета позиции
          #    группы, и для защиты от наложения верхней и нижней групп колонки
          layout = {}
          zones.each do |key, items|
            heights = items.map do |it|
              w = param_zone_box(content, key.first, 0.0, 1.0)[:width]
              est_text = it[:stadia] ? it[:text] : it[:render_text]
              h = estimate_text_height(est_text, it[:size], w, it[:font], ctx[:text_bold])
              if it[:stadia] && it[:show_label] && !it[:label].empty?
                # Заголовок чек-листа — отдельная строка своим (бо́льшим) кеглем
                h += (it[:label_size] || it[:size]) * font_line_pitch_ratio(it[:font])
              elsif it[:label_size]
                # Оценка считает строку заголовка кеглем значения — компенсируем
                # фактический кегль +1, иначе заголовок наезжает на предыдущий параметр
                h += PARAM_LABEL_SIZE_DELTA * font_line_pitch_ratio(it[:font])
              end
              h
            end
            layout[key] = { heights: heights, total_h: heights.sum + ([items.size - 1, 0].max * gap_pt) }
          end

          # 3. Отрисовка зон: группа «верх» начинается от верхнего края рабочей
          #    области, «середина» центрируется в свободной полосе колонки
          #    между верхней и нижней группами, группа «низ» заканчивается у
          #    нижнего края. Группы одной колонки не должны накладываться:
          #    если места не хватает, нижняя прижимается вниз, про среднюю
          #    выводится предупреждение.
          top_used = Hash.new(0.0)
          bottom_used = Hash.new(0.0)
          layout.each do |(al, va), l|
            top_used[al] += l[:total_h] if va == :top
            bottom_used[al] += l[:total_h] if va == :bottom
          end

          zones.each do |(align, valign), items|
            heights = layout[[align, valign]][:heights]
            total_h = layout[[align, valign]][:total_h]

            floor_y = content[:top] - content[:h]
            cur_y =
              case valign
              when :center
                # Средний ряд — по центру свободной полосы колонки: между
                # нижней кромкой верхней группы и верхней кромкой нижней
                # (нет групп — по центру рабочей области страницы)
                band_top = content[:top] - top_used[align] - gap_pt
                band_bottom = floor_y + bottom_used[align] + gap_pt
                if total_h >= band_top - band_bottom
                  warn "Параметры шаблона: средняя группа колонки «#{align}» не помещается между верхней и нижней — возможно наложение"
                  band_top
                else
                  (band_top + band_bottom + total_h) / 2.0
                end
              when :bottom
                start_y = floor_y + total_h
                limit_y = content[:top] - top_used[align] - gap_pt
                if limit_y < floor_y
                  # Колонка переполнена целиком: оставляем честную привязку к
                  # нижнему краю, в полосе столкновения возможно наложение
                  warn "Параметры шаблона: колонка «#{align}» переполнена — нижняя группа выведена от нижнего края, возможно наложение на верхнюю группу"
                  start_y
                else
                  clamped = [start_y, limit_y].min
                  if clamped < start_y
                    warn "Параметры шаблона: нижняя группа колонки «#{align}» не помещается после верхней — прижата вниз, последние строки могут уйти за нижнее поле"
                  end
                  clamped
                end
              else
                content[:top]
              end

            items.each_with_index do |it, i|
              h = heights[i]
              box = param_zone_box(content, align, cur_y, h)

              if it[:stadia] && it[:text].include?("\n")
                # Стадии (чек-лист): заголовок — отдельной строкой над списком,
                # чтобы не ломать разбор строк "[✓]/[ ]" с квадратами-чекбоксами.
                if it[:show_label] && !it[:label].empty?
                  lsize = it[:label_size] || it[:size]
                  pitch = lsize * font_line_pitch_ratio(it[:font])
                  add_bounded_text(ctx, doc, page, cnt_layer, it[:label],
                                   { x: box[:x], y: box[:y], width: box[:width], height: pitch },
                                   size: lsize, color: it[:color], align: align, anchor: :top, font: it[:font])
                  box = box.merge(y: box[:y] - pitch, height: [box[:height] - pitch, 10.0].max)
                end
                draw_stadia_check_rows(ctx, doc, page, cnt_layer,
                                       { text: it[:text], size: it[:size], color: it[:color], align: align },
                                       box, it[:font], 1.0, (gfx_layer || cnt_layer))
              else
                add_bounded_text(ctx, doc, page, cnt_layer, it[:render_text], box,
                                 size: it[:size], color: it[:color], align: align, anchor: :top, font: it[:font],
                                 label_size: it[:label_size], label_len: it[:label_size] ? it[:label].length : 0)
              end

              # Небольшая линия-разделитель «Линия» — в зазоре между соседними
              # строками зоны, шириной с текст строки и выровненная по тексту
              # (слева / по центру / справа колонки), а не на всю ширину колонки
              if line_on && i < items.size - 1
                w_line = separator_width_pt(ctx, doc, page, (gfx_layer || cnt_layer), it, box[:width])
                x_line = case align
                         when :center then box[:x] + (box[:width] - w_line) / 2.0
                         when :right  then box[:x] + box[:width] - w_line
                         else box[:x]
                         end
                add_thin_line(ctx, doc, page, (gfx_layer || cnt_layer),
                              x_line, cur_y - h - gap_pt / 2.0, w_line, it[:color])
              end

              cur_y -= h + gap_pt
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
      end
    end
  end
end
