# frozen_string_literal: true

module DN1Code
  module ExportPdf2
    module Service
      # Конвертация растровых изображений через библиотеку libvips (https://libvips.github.io/libvips/).
      #
      # Биндинг написан напрямую на Fiddle (по образцу FontService с gdi32/user32) — без гемов
      # ruby-vips/ffi, которые не рассчитаны на встроенный Ruby SketchUp. Используется минимум
      # C-API: чтение файла, запись файла, освобождение объекта; параметры сжатия передаются
      # внутри имени файла в «расширенном синтаксисе» libvips: "out.webp[Q=85]".
      #
      # DLL официальной сборки libvips кладутся в <плагин>/vendor/libvips (см. vendor/libvips/README.md).
      # Если DLL не найдена, available? == false, а вызывающий код сохраняет снимок как PNG.
      module VipsService
        extend self

        # Папка с DLL libvips внутри плагина: dn1c_export_pdf2/vendor/libvips
        VENDOR_DIR = File.expand_path("../vendor/libvips", __dir__).freeze

        @available = nil
        @library = nil
        @init_done = false
        @init_failed = false
        @path_prepared = false

        # Найдена ли DLL libvips в папке плагина (без загрузки библиотеки). Результат мемоизируется.
        # @return [Boolean]
        def available?
          @available = !find_dll.nil? if @available.nil?
          @available
        end

        # Конвертация изображения в WebP. Формат чтения libvips определяет по содержимому src,
        # формат записи — по расширению dst (ожидается .webp).
        # @param src [String] путь к исходному изображению (обычно временный PNG)
        # @param dst [String] путь к результату (.webp)
        # @param quality [Integer, nil] качество WebP 1..100; nil/0 — умолчание libvips (80)
        # @param lossless [Boolean] сжатие без потерь
        # @return [String, nil] путь dst при успехе, nil при любой ошибке
        def png_to_webp(src, dst, quality: 85, lossless: false)
          return nil unless available?
          return nil unless init!

          img = new_from_file_fn.call(utf8_str(src), nil)
          return nil if img.nil? || img.null?

          begin
            ok = write_to_file_fn.call(img, utf8_str(webp_target_string(dst, quality: quality, lossless: lossless)), nil).zero?
            warn_vips_error("libvips: не удалось записать #{dst}") unless ok
            File.delete(dst) if !ok && File.exist?(dst)
            ok ? dst : nil
          ensure
            unref_fn.call(img)
          end
        rescue StandardError => e
          warn "libvips: ошибка конвертации #{src} -> #{dst}: #{e.message}"
          File.delete(dst) if File.exist?(dst) rescue nil
          nil
        end

        # Строка назначения с опциями libvips в расширенном синтаксисе имени файла:
        # "out.webp[Q=85]" / "out.webp[lossless=true]"
        # @return [String]
        def webp_target_string(dst, quality: 85, lossless: false)
          opts = []
          opts << "Q=#{quality.to_i}" if quality.to_i.between?(1, 100)
          opts << "lossless=true" if lossless
          opts.empty? ? dst.to_s.dup : "#{dst}[#{opts.join(',')}]"
        end

        private

        # Поиск основной DLL libvips в папке плагина (libvips-42.dll в свежих сборках, libvips-0.dll в старых)
        def find_dll
          Dir.glob(File.join(VENDOR_DIR, "*.dll"))
             .find { |f| File.basename(f).downcase.start_with?("libvips") && File.basename(f).downcase.end_with?(".dll") }
        end

        # Загрузка DLL: зависимости libvips (glib и др.) лежат рядом с ней, но поиск
        # Windows-загрузчика по PATH срабатывает не во всех контекстах, поэтому папка
        # добавляется через SetDllDirectoryW, а каждая DLL папки грузится по полному пути.
        def library
          @library ||= begin
            require "fiddle"
            return nil unless windows?

            dll = find_dll
            if dll.nil?
              @init_failed = true
              nil
            else
              prepare_dll_search(File.dirname(dll))
              load_dlls(File.dirname(dll))
              Fiddle.dlopen(dll)
            end
          end
        rescue StandardError => e
          @init_failed = true
          warn "libvips: не удалось загрузить DLL из #{VENDOR_DIR}: #{e.message}"
          nil
        end

        def windows?
          RUBY_PLATFORM =~ /mswin|mingw|cygwin/
        end

        def prepare_dll_search(dir)
          return if @path_prepared

          entries = ENV["PATH"].to_s.split(File::PATH_SEPARATOR).map { |p| p.strip.downcase }
          ENV["PATH"] = "#{dir}#{File::PATH_SEPARATOR}#{ENV['PATH']}" unless entries.include?(dir.downcase)
          @path_prepared = true
        end

        # Регистрирует папку в поиске загрузчика и грузит все DLL папки по полному пути
        # (сбои отдельных некритичных DLL игнорируются — важна только libvips-*.dll)
        def load_dlls(dir)
          return if @dlls_loaded

          @dlls_loaded = true
          @sibling_handles = []
          set_dll_directory(dir)
          Dir.glob(File.join(dir, "*.dll")).sort.each do |d|
            begin
              @sibling_handles << Fiddle.dlopen(d)
            rescue StandardError
              nil
            end
          end
        end

        def set_dll_directory(dir)
          require "fiddle"
          kernel32 = Fiddle.dlopen("kernel32.dll")
          set_dir = Fiddle::Function.new(kernel32["SetDllDirectoryW"], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
          wpath = (dir + "\0").encode(Encoding::UTF_16LE).bytes.pack("C*")
          ptr = Fiddle::Pointer.malloc(wpath.bytesize)
          ptr[0, wpath.bytesize] = wpath
          set_dir.call(ptr)
        rescue StandardError
          nil
        end

        # vips_init обязателен до любых других вызовов libvips (идемпотентен).
        # argv0 не может быть NULL (внутри вызывается g_path_get_basename) — передаем
        # путь к самой DLL: заодно libvips находит по нему свою папку с модулями.
        def init!
          return false if @init_failed
          return true if @init_done

          dll = find_dll
          if dll.nil?
            @init_failed = true
            return false
          end
          library
          return false if @init_failed

          if init_fn.call(utf8_str(dll)).zero?
            @init_done = true
          else
            @init_failed = true
            warn_vips_error("libvips: сбой vips_init")
          end
          @init_done
        rescue StandardError => e
          @init_failed = true
          warn "libvips: инициализация не удалась: #{e.message}"
          false
        end

        # Привязка функций C-API (vips_image_new_from_file и vips_image_write_to_file —
        # вариадические, завершаются nil-терминатором списка опций; на Win64 фиксированная
        # арность вызова корректна — так же вызывается вариадический SendMessageW в FontService).
        # В монолитной сборке libvips glib слинкован отдельно (libgobject-2.0-0.dll), поэтому
        # g_object_unref ищется по всем DLL папки, а не только в основной библиотеке.
        def bind_fns
          lib = library
          vp  = Fiddle::TYPE_VOIDP
          int = Fiddle::TYPE_INT
          {
            init:        Fiddle::Function.new(sym("vips_init"), [vp], int),
            new_file:    Fiddle::Function.new(sym("vips_image_new_from_file"), [vp, vp], vp),
            write_file:  Fiddle::Function.new(sym("vips_image_write_to_file"), [vp, vp, vp], int),
            unref:       Fiddle::Function.new(sym("g_object_unref"), [vp], Fiddle::TYPE_VOID),
            error_buf:   Fiddle::Function.new(sym("vips_error_buffer"), [], vp),
            error_clear: Fiddle::Function.new(sym("vips_error_clear"), [], Fiddle::TYPE_VOID)
          }
        end

        # Поиск символа в основной DLL libvips, затем в остальных DLL папки (handles,
        # загруженные в load_dlls)
        def sym(name)
          handles = [@library] + @sibling_handles.to_a
          handles.each do |h|
            begin
              return h[name]
            rescue StandardError
              next
            end
          end
          raise Fiddle::DLError, "unknown symbol \"#{name}\""
        end

        def fns
          @fns ||= bind_fns
        rescue StandardError => e
          @init_failed = true
          warn "libvips: не удалось привязать функции (неподдерживаемая сборка?): #{e.message}"
          nil
        end

        def init_fn
          fns[:init]
        end

        def new_from_file_fn
          fns[:new_file]
        end

        def write_to_file_fn
          fns[:write_file]
        end

        def unref_fn
          fns[:unref]
        end

        def error_buf_fn
          fns[:error_buf]
        end

        def error_clear_fn
          fns[:error_clear]
        end

        # Путь передается в libvips как UTF-8: glib на Windows сам конвертирует его в wide-char,
        # поэтому кириллица в путях артикулов работает
        def utf8_str(str)
          s = str.to_s
          return s if s.encoding == Encoding::UTF_8

          s.encode(Encoding::UTF_8)
        rescue StandardError
          s.dup.force_encoding(Encoding::UTF_8)
        end

        def warn_vips_error(context)
          ptr = error_buf_fn.call
          msg = ptr.nil? || ptr.null? ? "" : ptr.to_s.force_encoding(Encoding::UTF_8).strip
          error_clear_fn.call
          warn msg.empty? ? context : "#{context}: #{msg}"
        end
      end
    end
  end
end
