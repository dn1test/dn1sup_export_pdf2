# frozen_string_literal: true

require "securerandom"
require "tmpdir"
require "fileutils"

module DN1Code
  module ExportPdf2
    module Service
      # Сервис высококачественного рендеринга видов и сцен модели SketchUp во временные растровые изображения (PNG).
      module RenderService
        # Соотношение сторон для стандартных печатных листов ISO A (A4, A3, A2) = 1 / sqrt(2) ≈ 0.7071
        DEFAULT_ISO_RATIO = 0.7071

        # Трактовка флага «показывать фон»: nil означает «не трогать» (фон показывается)
        def self.background_enabled?(value)
          value.nil? ||
            (value != false && value.to_s != "false" && value != 0 && value.to_s != "0")
        end

        # Временное отключение фона сцены (небо/земля/туман) на rendering_options модели.
        # Ключа DisplaySky в RenderingOptions нет, поэтому градиент неба гасится принудительно белыми цветами.
        # Водяные знаки (DisplayWatermarks) фоном не управляются — у них отдельная галка,
        # см. apply_watermark_override.
        # @param ro [Sketchup::RenderingOptions, nil] параметры отрисовки модели
        # @param show_bg [Object] флаг «показывать фон»
        # @return [Hash] сохранённые исходные значения — передать в restore_background
        def self.apply_background_override(ro, show_bg)
          orig_bg = {}
          return orig_bg if ro.nil? || background_enabled?(show_bg)

          bg_keys = %w[BackgroundColor SkyColor GroundColor DrawGround DrawUnderground DisplayFog]
          bg_keys.each do |k|
            has_key = ro.respond_to?(:keys) ? ro.keys.include?(k) : !ro[k].nil?
            orig_bg[k] = ro[k] if has_key
          end
          white = defined?(::Sketchup::Color) ? ::Sketchup::Color.new(255, 255, 255) : "white"
          orig_bg.each_key do |k|
            if k == "BackgroundColor" || k == "SkyColor" || k == "GroundColor"
              ro[k] = white
            else
              ro[k] = false
            end
          end
          orig_bg
        end

        # Трактовка флага «показывать водяные знаки»: nil означает «не трогать»
        # (водяные знаки следуют стилю сцены — прежнее поведение для вызовов без флага)
        def self.watermark_enabled?(value)
          !(value == false || value.to_s == "false" || value == 0 || value.to_s == "0")
        end

        # Независимое от фона управление водяными знаками сцены (DisplayWatermarks).
        # @param ro [Sketchup::RenderingOptions, nil] параметры отрисовки модели
        # @param show_wm [Object] флаг «показывать водяные знаки»
        # @return [Hash] сохранённые исходные значения — передать в restore_background
        def self.apply_watermark_override(ro, show_wm)
          orig_wm = {}
          return orig_wm if ro.nil? || show_wm.nil?

          has_key = ro.respond_to?(:keys) ? ro.keys.include?("DisplayWatermarks") : !ro["DisplayWatermarks"].nil?
          orig_wm["DisplayWatermarks"] = ro["DisplayWatermarks"] if has_key
          ro["DisplayWatermarks"] = watermark_enabled?(show_wm)
          orig_wm
        end

        # Восстанавливает параметры фона, изменённые apply_background_override
        # @param ro [Sketchup::RenderingOptions, nil]
        # @param orig_bg [Hash] хеш, возвращённый apply_background_override
        def self.restore_background(ro, orig_bg)
          return if ro.nil? || orig_bg.nil? || orig_bg.empty?

          orig_bg.each { |k, v| ro[k] = v }
        end

        # Выполняет переключение на указанную сцену в SketchUp и экспорт растрового изображения во временный PNG-файл
        # @param model [Sketchup::Model] активная модель SketchUp
        # @param scene [Sketchup::Page, nil] сцена для рендеринга
        # @param options [Hash] параметры рендера (:image_width, :image_height, :scale_factor, :antialias, :ratio,
        #   :optimize_png — false отключает lossless-переупаковку PNG для промежуточных файлов)
        # @return [String] путь к созданному временному файлу PNG
        def self.render_scene_temp(model, scene, options = {})
          q_mode = (options[:render_quality] || options["render_quality"]).to_s.downcase.strip
          width = options[:image_width]
          if !q_mode.empty? || width.nil? || width.to_i <= 0
            dpi = case q_mode
                  when "low" then 96
                  when "high" then 300
                  else 150
                  end
            psz = (options[:page_size] || options["page_size"] || "A4").to_s.upcase.strip
            long_inches = (psz == "A3") ? 16.535433 : 11.692913
            width = (long_inches * dpi).round
          end
          ratio = if options[:ratio]
                    options[:ratio]
                  elsif options[:aspect_ratio] && options[:aspect_ratio].to_f > 0
                    1.0 / options[:aspect_ratio].to_f
                  elsif options[:image_aspect_ratio] && defined?(OverlayService)
                    info = OverlayService.calculate_target_info(model)
                    info[:ratio] > 0 ? (1.0 / info[:ratio]) : DEFAULT_ISO_RATIO
                  else
                    DEFAULT_ISO_RATIO
                  end
          height       = options[:image_height] || (width * ratio).round
          antialias    = options.fetch(:antialias, true)

          # Определение формата: лучший формат по умолчанию — PNG (24-bit TrueColor, без потерь)
          raw_fmt = (options[:image_format] || "png").to_s.downcase.strip
          is_jpeg = (raw_fmt == "jpg" || raw_fmt == "jpeg")
          ext = is_jpeg ? "jpg" : "png"

          # Параметр сжатия: сжатый (true) или без сжатия (false, максимальное качество)
          compress_enabled = options[:compress_pdf] != false && options[:compress_pdf].to_s != "false" && options[:compress_pdf] != "none"

          temp_file = File.join(Dir.tmpdir, "su_scene_#{SecureRandom.hex(8)}.#{ext}").tr("\\", "/")

          # Разрешаем сцену (Sketchup::Page), если передан объект SceneItem, строка или идентификатор
          target_page = scene
          if target_page.is_a?(String) || target_page.is_a?(Symbol)
            target_page = model.pages[target_page.to_s] if model.respond_to?(:pages)
          elsif target_page.respond_to?(:scene_ref) && target_page.scene_ref
            target_page = target_page.scene_ref
          end

          # Переключаем сцену и ее нативный стиль в SketchUp
          if model && target_page
            if model.respond_to?(:pages) && model.pages.respond_to?(:selected_page=)
              begin
                model.pages.selected_page = target_page
              rescue StandardError => _e
                # Переключение сцены не критично
              end
            end
            if target_page.respond_to?(:style) && target_page.style && model.respond_to?(:styles) && model.styles.respond_to?(:selected_style=)
              begin
                model.styles.selected_style = target_page.style
              rescue StandardError => _e
                # Применение стиля не критично
              end
            end
          end

          # Извлекаем параметры стиля сцены (Styles / RenderingOptions)
          style_ro = if target_page.respond_to?(:rendering_options) && target_page.rendering_options
                       target_page.rendering_options
                     elsif target_page.respond_to?(:style) && target_page.style && target_page.style.respond_to?(:rendering_options)
                       target_page.style.rendering_options
                     elsif model.respond_to?(:rendering_options)
                       model.rendering_options
                     else
                       nil
                     end

          # Множитель толщины линий (Line Scale Multiplier)
          # В режиме "auto" для растрового рендера масштаб рассчитывается от разрешения картинки (image_width) с уменьшением на 40%
          sm_setting = options[:scale_multiplier] || options["scale_multiplier"]
          sf_setting = options[:scale_factor] || options["scale_factor"]
          page_sz = (options[:page_size] || options["page_size"] || "A4").to_s.upcase.strip
          line_mult = if sm_setting
                        case sm_setting.to_s.downcase.strip
                        when "auto"
                          img_w = (options[:image_width] || options["image_width"] || width || 2400).to_i
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
                          raw_mult = case page_sz
                                     when "A2" then [ras_mult, 1.20].max
                                     when "A3" then [ras_mult, 0.90].max
                                     else ras_mult
                                     end
                          # При авто scale множитель меньше на 30% (* 0.70)
                          (raw_mult * 0.70).round(2)
                        else
                          f = sm_setting.to_f
                          f > 0.0 ? f : 2.0
                        end
                      elsif sf_setting && sf_setting.to_f > 0
                        sf_setting.to_f
                      else
                        2.0
                      end

          view = model.respond_to?(:active_view) ? model.active_view : nil

          rendered = false
          if view && view.respond_to?(:write_image)
            write_options = {
              filename:     temp_file,
              width:        width,
              height:       height,
              antialias:    antialias,
              scale_factor: line_mult
            }
            # Для JPEG по умолчанию максимальное качество 100% (1.0)
            comp = if options.key?(:jpeg_quality)
                     options[:jpeg_quality].to_f
                   elsif options.key?(:compression) && options[:compression].is_a?(Numeric)
                     options[:compression].to_f
                   else
                     1.0
                   end
            write_options[:compression] = comp if is_jpeg

            # Извлечение и применение параметров толщин линий напрямую из стиля сцены
            ro = (model && model.respond_to?(:rendering_options)) ? model.rendering_options : nil
            orig_widths = {}
            if ro && style_ro
              keys_to_track = %w[SilhouetteWidth ProfileWidth SectionCutWidth DepthQueWidth LineEndWidth LineExtension DrawSilhouettes DrawLineEnds ExtendLines DrawProfilesOnly]
              keys_to_track.each do |k|
                has_key = if ro.respond_to?(:keys)
                            ro.keys.include?(k)
                          elsif ro.respond_to?(:[])
                            !ro[k].nil?
                          else
                            false
                          end
                orig_widths[k] = ro[k] if has_key
              end

              # Базовые параметры берутся напрямую из стиля
              sil_val   = style_ro["SilhouetteWidth"] ? style_ro["SilhouetteWidth"].to_i : (orig_widths["SilhouetteWidth"] || 2).to_i
              prof_val  = style_ro["ProfileWidth"] ? style_ro["ProfileWidth"].to_i : (orig_widths["ProfileWidth"] || sil_val).to_i
              cut_val   = style_ro["SectionCutWidth"] ? style_ro["SectionCutWidth"].to_i : (orig_widths["SectionCutWidth"] || 4).to_i
              dq_val    = style_ro["DepthQueWidth"]   ? style_ro["DepthQueWidth"].to_i   : (orig_widths["DepthQueWidth"] || 4).to_i
              end_val   = style_ro["LineEndWidth"]    ? style_ro["LineEndWidth"].to_i    : (orig_widths["LineEndWidth"] || 1).to_i
              ext_val   = style_ro["LineExtension"]   ? style_ro["LineExtension"].to_i   : (orig_widths["LineExtension"] || 1).to_i

              draw_sil  = (style_ro.respond_to?(:key?) && style_ro.key?("DrawSilhouettes")) ? style_ro["DrawSilhouettes"] : style_ro["DrawSilhouettes"]
              draw_sil  = orig_widths["DrawSilhouettes"] if draw_sil.nil?
              draw_ends = (style_ro.respond_to?(:key?) && style_ro.key?("DrawLineEnds")) ? style_ro["DrawLineEnds"] : style_ro["DrawLineEnds"]
              draw_ends = orig_widths["DrawLineEnds"] if draw_ends.nil?
              ext_lines = (style_ro.respond_to?(:key?) && style_ro.key?("ExtendLines")) ? style_ro["ExtendLines"] : style_ro["ExtendLines"]
              ext_lines = orig_widths["ExtendLines"] if ext_lines.nil?
              prof_only = (style_ro.respond_to?(:key?) && style_ro.key?("DrawProfilesOnly")) ? style_ro["DrawProfilesOnly"] : style_ro["DrawProfilesOnly"]
              prof_only = orig_widths["DrawProfilesOnly"] if prof_only.nil?

              # Устанавливаем флаги отрисовки из стиля
              ro["DrawSilhouettes"]  = draw_sil   unless draw_sil.nil?
              ro["DrawLineEnds"]     = draw_ends  unless draw_ends.nil?
              ro["ExtendLines"]      = ext_lines  unless ext_lines.nil?
              ro["DrawProfilesOnly"] = prof_only  unless prof_only.nil?

              # Масштабируем толщины линий из стиля с учетом множителя разрешения
              ro["SilhouetteWidth"] = [1, (sil_val * line_mult).round].max if sil_val > 0
              ro["ProfileWidth"]    = [1, (prof_val * line_mult).round].max if prof_val > 0 && (ro.respond_to?(:keys) ? ro.keys.include?("ProfileWidth") : !ro["ProfileWidth"].nil?)
              ro["SectionCutWidth"] = [1, (cut_val * line_mult).round].max if cut_val > 0
              ro["DepthQueWidth"]   = [1, (dq_val * line_mult).round].max  if dq_val > 0
              ro["LineEndWidth"]    = [1, (end_val * line_mult).round].max if end_val > 0
              ro["LineExtension"]   = [1, (ext_val * line_mult).round].max if ext_val > 0
            end

            # Временное отключение фона сцены (небо/земля/туман) и водяных знаков при
            # выключенных show_background / show_watermarks — два независимых флага.
            orig_bg = apply_background_override(ro, options[:show_background])
            orig_wm = apply_watermark_override(ro, options.key?(:show_watermarks) ? options[:show_watermarks] : options["show_watermarks"])

            afs_setting = options[:annotation_font_size] || options["annotation_font_size"]
            hide_annot = options[:hide_annotations] == true || options["hide_annotations"] == true
            with_temporary_hidden_annotations(model, hide_annot) do
              with_temporary_annotation_font_size(model, afs_setting) do
                begin
                  view.write_image(write_options)
                  rendered = File.exist?(temp_file)
                rescue StandardError => e
                  warn "[DN1C Export PDF] Ошибка write_image (#{e.message}) — используется резервное изображение"
                ensure
                  # Восстановление исходных параметров отрисовки линий, фона и водяных знаков
                  if ro && !orig_widths.empty?
                    orig_widths.each { |k, v| ro[k] = v }
                  end
                  restore_background(ro, orig_bg)
                  restore_background(ro, orig_wm)
                end
              end
            end

            # Максимальное сжатие PNG без потерь; optimize_png: false — файл промежуточный
            # (конвертируется в WebP и удаляется), переупаковка уровня 9 на больших
            # разрешениях занимает секунды главного потока без выигрыша в пикселях
            optimize_png_lossless(temp_file) if rendered && !is_jpeg && options[:optimize_png] != false
          end

          unless rendered
            # Если рендер запущен в автономном/тестовом окружении или моке, создаем placeholder
            create_fallback_image(temp_file, width, height, scene ? scene.name : "Scene")
          end

          temp_file
        end

        # Выполняет максимальное сжатие PNG без потерь качества (Zlib::BEST_COMPRESSION)
        # @param file_path [String] путь к файлу PNG
        # @return [String] путь к файлу
        def self.optimize_png_lossless(file_path)
          return file_path unless file_path && File.exist?(file_path)

          data = File.binread(file_path)
          return file_path unless data.bytesize > 8 && data[0, 8] == "\x89PNG\r\n\x1a\n".b

          require "zlib" unless defined?(::Zlib)
          pos = 8
          chunks = []
          raw_idat = String.new("".b)

          while pos < data.bytesize
            len = data[pos, 4].unpack1("N")
            type = data[pos + 4, 4]
            chunk_payload = data[pos + 8, len]
            if type == "IDAT".b
              raw_idat << chunk_payload
            else
              chunks << { type: type, data: chunk_payload }
            end
            pos += 12 + len
          end

          return file_path if raw_idat.empty?

          inflated = ::Zlib::Inflate.inflate(raw_idat)
          deflater = ::Zlib::Deflate.new(::Zlib::BEST_COMPRESSION)
          best_idat = deflater.deflate(inflated, ::Zlib::FINISH)
          deflater.close

          new_png = String.new("\x89PNG\r\n\x1a\n".b)
          chunks.each do |c|
            if c[:type] == "IEND".b
              idat_len = [best_idat.bytesize].pack("N")
              idat_crc = [::Zlib.crc32("IDAT".b + best_idat)].pack("N")
              new_png << idat_len << "IDAT".b << best_idat << idat_crc
            end
            c_len = [c[:data].bytesize].pack("N")
            c_crc = [::Zlib.crc32(c[:type] + c[:data])].pack("N")
            new_png << c_len << c[:type] << c[:data] << c_crc
          end

          File.binwrite(file_path, new_png)
          file_path
        rescue StandardError
          file_path
        end

        # Выполняет безопасное удаление временных файлов изображений после завершения сборки PDF
        # @param file_paths [Array<String>, String] список путей к временным файлам
        # @return [void]
        def self.safe_cleanup_files(file_paths)
          # Запуск сборщика мусора для освобождения дескрипторов файлов в Windows
          GC.start
          Array(file_paths).each do |path|
            next unless path && File.exist?(path)

            begin
              File.delete(path)
            rescue StandardError => _e
              # Игнорируем блокировки ОС, временная папка периодически очищается системой
            end
          end
        end

        # Создает минимальное валидное изображение (PNG или JPEG 1x1 пиксель) для тестов и автономного режима
        # @param file_path [String] путь к сохраняемому файлу
        # @param width [Integer] ширина в пикселях
        # @param height [Integer] высота в пикселях
        # @param label [String] текстовая метка
        # @return [void]
        def self.create_fallback_image(file_path, width = 800, height = 600, label = "")
          if file_path.to_s.match?(/\.jpe?g$/i)
            jpeg_1x1 = [
              0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x01, 0x00, 0x48,
              0x00, 0x48, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43, 0x00, 0x08, 0x06, 0x06, 0x07, 0x06, 0x05, 0x08,
              0x07, 0x07, 0x07, 0x09, 0x09, 0x08, 0x0A, 0x0C, 0x14, 0x0D, 0x0C, 0x0B, 0x0B, 0x0C, 0x19, 0x12,
              0x13, 0x0F, 0x14, 0x1D, 0x1A, 0x1F, 0x1E, 0x1D, 0x1A, 0x1C, 0x1C, 0x20, 0x24, 0x2E, 0x27, 0x20,
              0x22, 0x2C, 0x23, 0x1C, 0x1C, 0x28, 0x37, 0x29, 0x2C, 0x30, 0x31, 0x34, 0x34, 0x34, 0x1F, 0x27,
              0x39, 0x3D, 0x38, 0x32, 0x3C, 0x2E, 0x33, 0x34, 0x32, 0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x01,
              0x00, 0x01, 0x01, 0x01, 0x11, 0x00, 0xFF, 0xC4, 0x00, 0x1F, 0x00, 0x00, 0x01, 0x05, 0x01, 0x01,
              0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04,
              0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F,
              0x00, 0xBF, 0x80, 0xFF, 0xD9
            ].pack("C*")
            File.binwrite(file_path, jpeg_1x1)
            return
          end

          png_1x1 = [
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
            0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
            0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
            0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
            0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
            0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
            0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
            0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
            0x42, 0x60, 0x82
          ].pack("C*")

          File.binwrite(file_path, png_1x1)
        end

        # Временно применяет заданный размер шрифта ко всем выноскам и аннотациям модели (Sketchup::Text)
        # на время выполнения переданного блока и гарантированно восстанавливает исходные параметры в ensure.
        # @param model [Sketchup::Model]
        # @param target_font_size [String, Integer, Float, nil]
        def self.with_temporary_annotation_font_size(model, target_font_size)
          target_sz = target_font_size.to_s.downcase.strip
          return yield if target_sz.empty? || target_sz == "auto" || !model || !model.respond_to?(:entities)

          target_pt = target_sz.to_f
          return yield if target_pt <= 0

          orig_fonts = {}
          collect_texts = lambda do |entities|
            texts = (entities.grep(::Sketchup::Text) rescue []) || []
            texts.each do |t|
              next unless t.respond_to?(:font) && t.respond_to?(:font=)
              f = t.font rescue nil
              if f.is_a?(Hash)
                orig_fonts[t] = f
                t.font = { name: f[:name], size: target_pt.to_i, bold: f[:bold], italic: f[:italic] } rescue nil
              end
            end
            ((entities.grep(::Sketchup::Group) rescue []) || []).each { |g| collect_texts.call(g.entities) if g.respond_to?(:entities) }
            ((entities.grep(::Sketchup::ComponentInstance) rescue []) || []).each do |ci|
              collect_texts.call(ci.definition.entities) if ci.respond_to?(:definition) && ci.definition.respond_to?(:entities)
            end
          end

          collect_texts.call(model.entities)

          begin
            yield
          ensure
            orig_fonts.each do |t, f|
              t.font = f if t.respond_to?(:font=) rescue nil
            end
          end
        end

        # Временно скрывает отображение размеров и выносок/текста модели
        # на время выполнения блока (для чистого растрового рендера с тенями).
        # @param model [Sketchup::Model]
        # @param enabled [Boolean]
        def self.with_temporary_hidden_annotations(model, enabled = true)
          return yield unless enabled && model && model.respond_to?(:rendering_options)

          ro = model.rendering_options
          orig_model_dims = ro["DisplayDims"] rescue nil
          orig_model_text = ro["DisplayText"] rescue nil

          orig_page_dims = nil
          orig_page_text = nil
          active_page = model.respond_to?(:pages) ? (model.pages.selected_page rescue nil) : nil
          if active_page && active_page.respond_to?(:rendering_options) && active_page.rendering_options
            orig_page_dims = active_page.rendering_options["DisplayDims"] rescue nil
            orig_page_text = active_page.rendering_options["DisplayText"] rescue nil
            active_page.rendering_options["DisplayDims"] = false rescue nil
            active_page.rendering_options["DisplayText"] = false rescue nil
          end

          ro["DisplayDims"] = false rescue nil
          ro["DisplayText"] = false rescue nil

          begin
            yield
          ensure
            ro["DisplayDims"] = orig_model_dims unless orig_model_dims.nil? rescue nil
            ro["DisplayText"] = orig_model_text unless orig_model_text.nil? rescue nil
            if active_page && active_page.respond_to?(:rendering_options) && active_page.rendering_options
              active_page.rendering_options["DisplayDims"] = orig_page_dims unless orig_page_dims.nil? rescue nil
              active_page.rendering_options["DisplayText"] = orig_page_text unless orig_page_text.nil? rescue nil
            end
          end
        end
      end
    end
  end
end
