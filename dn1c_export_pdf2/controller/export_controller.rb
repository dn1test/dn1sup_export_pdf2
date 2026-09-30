# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require_relative "../service/layout_builder"

module DN1Code
  module ExportPdf2
    module Controller
      # Контроллер экспорта: управляет созданием PDF через SketchUp LayOut Ruby API,
      # сохранением резервных копий, PNG-снимками сцен и синхронизацией данных проекта.
      class ExportController
        attr_reader :project_data, :model

        # Путь к копии «_last», заполненный LayoutBuilder после успешного экспорта
        attr_accessor :last_pdf_path

        def initialize(project_data, model = nil)
          @project_data = project_data
          @model        = model || (defined?(Sketchup) ? Sketchup.active_model : nil)
        end

        # Экспорт документа в PDF через SketchUp LayOut Ruby API
        # @param custom_output_path [String, nil] путь к выходному PDF файлу
        # @param progress_block [Proc, nil] блок обратного вызова прогресса (current, total, message)
        # @return [String] абсолютный путь к созданному PDF
        def export(custom_output_path = nil, &progress_block)
          Service::LayoutBuilder.export(self, custom_output_path, &progress_block)
        end

        # Разрешение пути по умолчанию для результирующего PDF файла.
        # PDF пишется в папку артикула: <базовая папка>/<Артикул>/pdf/<Артикул>_01#001.pdf
        # @return [String]
        def resolve_default_pdf_path
          model_path = @model&.respond_to?(:path) ? @model.path : ""
          vrs = @project_data.class.version_rev_suffix(@project_data.project_info)

          if model_path && !model_path.empty?
            art_dir  = @project_data.articul_dir_for_model(@model)
            art_name = @project_data.class.articul_folder_name(@project_data.project_info, @model)
            return File.join(art_dir, "pdf", "#{art_name}_#{vrs}.pdf") if art_dir && art_name

            # Фолбэк: папку артикула определить не удалось — рядом с .skp (прежнее поведение)
            model_dir  = File.dirname(model_path.tr("\\", "/"))
            model_base = File.basename(model_path, ".skp")
            File.join(model_dir, "#{model_base}_#{vrs}.pdf")
          else
            # Если модель еще не сохранена на диске
            File.join(Dir.tmpdir, "SU_Export_#{vrs}.pdf")
          end
        end

        # Путь к «последнему» PDF рядом с рабочим файлом: <dir модели>/<имя>_last.pdf.
        # Перезаписывается при каждом экспорте. nil — модель не сохранена или папка
        # модели недоступна (копия не создаётся, открывается версионный PDF)
        # @return [String, nil]
        def resolve_last_pdf_path
          model_path = @model&.respond_to?(:path) ? @model.path.to_s : ""
          return nil if model_path.empty?

          model_dir  = File.dirname(model_path.tr("\\", "/"))
          return nil unless File.directory?(model_dir)

          model_base = File.basename(model_path, ".skp")
          File.join(model_dir, "#{model_base}_last.pdf")
        end

        # Резервная копия файла модели (.skp) в папку артикула: <Артикул>/skp/<Артикул>_01#001.skp
        # @return [String, nil]
        def save_skp_backup
          return nil unless @model&.respond_to?(:path)

          model_path = @model.path.to_s
          return nil if model_path.empty?

          vrs      = @project_data.class.version_rev_suffix(@project_data.project_info)
          art_dir  = @project_data.articul_dir_for_model(@model)
          art_name = @project_data.class.articul_folder_name(@project_data.project_info, @model)

          if art_dir && art_name
            backup_dir = File.join(art_dir, "skp")
          else
            model_dir  = File.dirname(model_path.tr("\\", "/"))
            model_base = File.basename(model_path, ".skp")
            backup_dir = File.join(model_dir, "#{model_base}_backup")
            art_name   = model_base
          end

          FileUtils.mkdir_p(backup_dir)
          backup_path = File.join(backup_dir, "#{art_name}_#{vrs}.skp")

          if @model.respond_to?(:save_copy)
            @model.save_copy(backup_path)
            backup_path
          end
        end

        # Экспорт снимков включенных сцен в папку артикула: <Артикул>/images/.
        # Набор «последних сцен»: папка очищается и перезаписывается при каждом экспорте.
        # Формат снимков не настраивается: WebP при доступной libvips (конвертация
        # PNG->WebP через libvips, при ошибке конвертации — фолбэк на PNG), иначе PNG.
        #
        # Синхронно делается только подготовка: рендер/раскладка растровых исходников
        # (PNG либо уже отрендеренная JPEG-заготовка страницы PDF) под финальными
        # именами (рендер обязан идти в главном потоке SketchUp). Сама
        # конвертация PNG->WebP при async: true уходит в очередь SnapshotWorker
        # (по одному снимку за тик таймера на главном потоке) — экспорт и
        # открытие PDF не ждут снимков; при async: false конвертация
        # выполняется инлайн (тесты/отладка).
        # Разрешение и пропорции берутся из pdf_settings (image_width / render_quality,
        # image_aspect_ratio / custom_ratio, наценка — aspect_ratio конкретной сцены).
        # @param reusable [Hash] { имя сцены => путь к уже отрендеренному временному изображению }
        # @param async [Boolean] фоновая конвертация WebP через SnapshotWorker
        # @param progress_block [Proc, nil] блок (current, total, message)
        # @return [Array<String>] пути к снимкам (при фоновой конвертации — планируемые пути .webp)
        def export_scene_snapshots(reusable: {}, async: true, &progress_block)
          scenes = @project_data.scenes.select(&:enabled)
          images_dir = scene_images_dir
          return [] if scenes.empty? || images_dir.nil?

          # Очередь снимков обычно уже пуста (конвертация быстрая) — добработать
          # остаток синхронно, не дольше 3 секунд, чтобы не замораживать SketchUp
          # на повторном экспорте. Остаток, не уложившийся в лимит, обрабатываться
          # не будет: ниже папка images очищается, а submit заменяет очередь новой партией.
          Service::SnapshotWorker.drain(3.0) if defined?(Service::SnapshotWorker)
          FileUtils.mkdir_p(images_dir)
          # «Только последние»: снимки удаленных/переименованных сцен не должны оставаться
          Dir.glob(File.join(images_dir, "*.{png,jpg,jpeg,webp}")).each { |f| File.delete(f) rescue nil }

          settings = @project_data.pdf_settings
          # Готовность libvips: не только наличие DLL (available?), но и успешная
          # инициализация. Иначе партия тихо не ставилась в очередь и PNG-исходники
          # оставались висеть без всякого сообщения.
          webp_mode = defined?(Service::VipsService) && Service::VipsService.ensure_started!
          webp_opts = webp_quality_setting(settings)
          # JPEG-заготовку страницы PDF переиспользуем без повторного рендера только когда
          # она всё равно конвертируется в lossy WebP; lossless WebP и PNG-фолбэк требуют
          # полноценный PNG-рендер
          reuse_jpeg = webp_mode && !webp_opts[:lossless]
          jobs      = []
          written   = []

          scenes.each_with_index do |scene_item, idx|
            label = webp_mode ? "WebP" : "PNG"
            progress_block&.call(idx + 1, scenes.size, "#{label}-снимок сцены #{idx + 1}/#{scenes.size}: #{scene_item.name}")

            src = reusable_source(reusable, scene_item, allow_jpeg: reuse_jpeg) ||
                  render_scene_png(scene_item, settings, optimize_png: !webp_mode)
            next unless src && File.exist?(src)

            # Растровый исходник раскладывается до выхода из экспорта: временные файлы кэша
            # PDF-страниц удаляются в ensure LayoutBuilder, фоновой партии нужен свой файл
            ext = File.extname(src).downcase
            raster_target = File.join(images_dir, scene_snapshot_filename(scene_item, idx, ext))
            write_snapshot_png(src, raster_target)
            if File.exist?(src) && File.expand_path(src) != File.expand_path(raster_target)
              # mv невозможен между томами — после копирования временный файл не нужен
              File.delete(src) rescue nil
            end
            next unless File.exist?(raster_target)

            if webp_mode
              jobs << { src:      raster_target,
                        dst:      File.join(images_dir, scene_snapshot_filename(scene_item, idx, ".webp")),
                        quality:  webp_opts[:quality],
                        lossless: webp_opts[:lossless] }
            else
              written << raster_target
            end
          end

          warn_webp_unavailable_once unless webp_mode
          return written if jobs.empty?

          if async && defined?(Service::SnapshotWorker)
            # Фоновая конвертация: возвращаем планируемые пути, файлы появятся в фоне
            Service::SnapshotWorker.submit(jobs)
            jobs.map { |job| job[:dst] }
          else
            jobs.map { |job| convert_snapshot_inline(job) }.compact
          end
        end

        # Папка снимков сцен: <Артикул>/images (или nil, если модель не сохранена)
        # @return [String, nil]
        def scene_images_dir
          art_dir = @project_data.articul_dir_for_model(@model)
          art_dir ? File.join(art_dir, "images") : nil
        end

        private

        # Качество WebP из настроек: 'lossless' -> сжатие без потерь, иначе целое 1..100 (умолчание 85)
        def webp_quality_setting(settings)
          raw = settings[:webp_quality].to_s.downcase.strip
          return { quality: nil, lossless: true } if raw == "lossless"

          q = raw.to_i
          q = 85 if q <= 0 || q > 100
          { quality: q, lossless: false }
        end

        # Синхронная конвертация одного снимка (async: false) — тот же результат,
        # что у фоновой партии SnapshotWorker. При недоступном libvips или ошибке
        # конвертации PNG-исходник остается на месте (снимок не теряется),
        # предупреждение — один раз.
        # @return [String, nil] путь к файлу (.webp либо .png при фолбэке)
        def convert_snapshot_inline(job)
          if defined?(Service::VipsService) &&
             Service::VipsService.png_to_webp(job[:src], job[:dst], quality: job[:quality], lossless: job[:lossless])
            File.delete(job[:src]) if File.exist?(job[:src]) rescue nil
            return job[:dst]
          end

          warn_webp_unavailable_once
          job[:src]
        end

        def warn_webp_unavailable_once
          return if @webp_warned

          @webp_warned = true
          svc = defined?(Service::VipsService) ? Service::VipsService : nil
          if svc.nil? || !svc.available?
            warn "Предупреждение: libvips не найдена (vendor/libvips) — снимки сохраняются как PNG."
          elsif !svc.started?
            warn "Предупреждение: libvips найдена, но инициализация не удалась — снимки сохраняются как PNG."
          else
            warn "Предупреждение: конвертация WebP не удалась, снимок сохранен как PNG."
          end
        end

        # Имя файла снимка сцены: "<NN>_<санитизированное имя><ext>"
        def scene_snapshot_filename(scene_item, index, ext)
          name = @project_data.class.sanitize_filename(scene_item.respond_to?(:name) ? scene_item.name : "scene")
          "#{format('%02d', index + 1)}_#{name}#{ext}"
        end

        # Перемещение (или копирование) временного PNG в целевой PNG-снимок
        def write_snapshot_png(src, target)
          return unless File.exist?(src)

          if File.expand_path(src) != File.expand_path(target)
            FileUtils.mv(src, target) rescue (FileUtils.cp(src, target) rescue nil)
          end
        end

        # Уже отрендеренное в image-режиме изображение сцены (избегаем повторного рендера).
        # JPEG-заготовки страниц PDF переиспользуем только под lossy WebP-конвертацию
        # (allow_jpeg: true) — итоговый снимок всё равно .webp; иначе требуется PNG.
        def reusable_source(reusable, scene_item, allow_jpeg: false)
          return nil unless reusable.is_a?(Hash)

          src = reusable[scene_item.respond_to?(:name) ? scene_item.name : nil].to_s
          return nil if src.empty? || !File.exist?(src)

          ext = File.extname(src).downcase
          return nil unless ext == ".png" || (allow_jpeg && (ext == ".jpg" || ext == ".jpeg"))

          src
        end

        # Рендер сцены во временное изображение с настройками из pdf_settings.
        # optimize_png: false — файл промежуточный (уйдет в WebP-конвертацию), поэтому
        # lossless-переупаковка PNG пропускается: на больших разрешениях она занимает
        # секунды главного потока, а пиксели не меняет.
        def render_scene_png(scene_item, settings, optimize_png: true)
          return nil unless defined?(Service::RenderService)

          scene_obj = scene_item.respond_to?(:scene_ref) ? scene_item.scene_ref : nil
          if scene_obj.nil? && @model.respond_to?(:pages) && scene_item.respond_to?(:name)
            scene_obj = @model.pages[scene_item.name.to_s] rescue nil
          end

          opts = {
            image_width:        settings[:image_width],
            render_quality:     settings[:render_quality] || "medium",
            page_size:          settings[:page_size] || "A4",
            antialias:          settings.fetch(:antialias, true),
            image_aspect_ratio: settings[:image_aspect_ratio],
            image_format:       "png",
            optimize_png:       optimize_png
          }
          # Фон видового экрана: тот же посценный флаг, что и в PDF-вьюпортах —
          # при viewport_background=false небо/земля гасятся (белый фон).
          # По умолчанию фон выключен.
          opts[:show_background] = if scene_item.respond_to?(:viewport_background) && !scene_item.viewport_background.nil?
                                     scene_item.viewport_background != false
                                   else
                                     false
                                   end
          # Водяные знаки — независимый от фона посценный флаг; для страниц без
          # флага наследуем значение фона (прежнее поведение).
          opts[:show_watermarks] = if scene_item.respond_to?(:viewport_watermarks) && !scene_item.viewport_watermarks.nil?
                                     scene_item.viewport_watermarks != false
                                   else
                                     opts[:show_background]
                                   end
          # Пропорция конкретной сцены приоритетна; "page"/"4:3"/custom уходят в глобальную логику
          sc_ratio = scene_aspect_ratio(scene_item)
          opts[:aspect_ratio] = sc_ratio if sc_ratio

          Service::RenderService.render_scene_temp(@model, scene_obj, opts)
        end

        # Числовая пропорция сцены, если она переопределена явно
        def scene_aspect_ratio(scene_item)
          raw = scene_item.respond_to?(:aspect_ratio) ? scene_item.aspect_ratio.to_s.strip : ""
          case raw
          when "3:2"  then 3.0 / 2.0
          when "16:9" then 16.0 / 9.0
          when "1:1"  then 1.0
          when "5:4"  then 5.0 / 4.0
          when "4:5"  then 4.0 / 5.0
          else nil
          end
        end
      end
    end
  end
end
