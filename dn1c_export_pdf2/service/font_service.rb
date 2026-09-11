# frozen_string_literal: true

module DN1Code
  module ExportPdf2
    module Service
      # Сервис управления типографикой и шрифтовыми стилями PDF документа.
      # Регистрирует кастомный TTF-шрифт DIN Condensed с кириллицей и задает шкалу размеров.
      module FontService
        # Основное имя зарегистрированного шрифтового семейства
        FONT_NAME = "DIN Condensed"

        # Плотный межбуквенный интервал для максимального сжатия ширины шрифта (минимальная ширина)
        CHARACTER_SPACING = -0.25

        # Системные TTF-шрифты с кириллицей для резервной замены DIN Condensed.
        # Стандартные PDF-шрифты (Helvetica) не поддерживают кириллицу и приводят
        # к ошибке Prawn IncompatibleStringEncoding при выводе русского текста.
        FALLBACK_FONT_FILES = [
          "segoeui.ttf", "arial.ttf", "calibri.ttf", "tahoma.ttf", "times.ttf"
        ].freeze

        # Цепочка семейств шрифтов для LayOut (по убыванию приоритета).
        # LayOut использует только шрифты, установленные в системе.
        LAYOUT_FONT_CANDIDATES = [
          "DIN Condensed", "Arial Narrow", "Roboto Condensed", "Segoe UI", "Arial"
        ].freeze

        # Имя семейства, устанавливаемого плагином в пользовательские шрифты Windows
        DIN_FAMILY_NAME = "DIN Condensed"
        DIN_REGISTRY_NAME = "DIN Condensed (TrueType)"

        # Ищет системный TTF-шрифт с поддержкой кириллицы (Windows-каталог Fonts и т.п.)
        # @return [String, nil] абсолютный путь к найденному шрифту или nil
        def self.find_cyrillic_fallback_font
          font_dirs = [
            ENV["WINDIR"] ? File.join(ENV["WINDIR"], "Fonts") : nil,
            "C:/Windows/Fonts",
            "/usr/share/fonts/truetype/dejavu",
            "/System/Library/Fonts"
          ].compact

          FALLBACK_FONT_FILES.each do |fname|
            font_dirs.each do |dir|
              candidate = File.join(dir, fname)
              return candidate if File.exist?(candidate)
            end
          end

          # Дополнительный поиск любых TTF в каталоге Fonts Windows
          font_dirs.each do |dir|
            next unless dir && Dir.exist?(dir)

            any_ttf = Dir.glob(File.join(dir, "*.ttf")).find { |f| File.exist?(f) }
            return any_ttf if any_ttf
          end

          nil
        end

        # Регистрирует семейство шрифтов DIN Condensed в документе Prawn.
        # Если файл шрифта не найден, подключает системный TTF с кириллицей;
        # Helvetica (без кириллицы) используется только как крайняя мера.
        # @param pdf_doc [Prawn::Document] целевой документ PDF
        # @return [void]
        def self.setup_fonts(pdf_doc)
          fonts_dir = File.expand_path("../config/fonts", __dir__)
          din_font_path = File.join(fonts_dir, "DIN Condensed.ttf")

          font_path = nil
          if File.exist?(din_font_path)
            font_path = din_font_path
          else
            font_path = find_cyrillic_fallback_font
            if font_path.nil?
              warn "[DN1C Export PDF] Файл DIN Condensed.ttf не найден и системный TTF не обнаружен — используется Helvetica (кириллица работать не будет)"
            end
          end

          if font_path
            pdf_doc.font_families.update(
              FONT_NAME => {
                normal: font_path,
                bold: font_path,
                italic: font_path,
                bold_italic: font_path
              }
            )
            pdf_doc.font(FONT_NAME)
          else
            # Резервный стандартный PDF шрифт при отсутствии файла DIN Condensed
            pdf_doc.font("Helvetica")
          end

          apply_character_spacing(pdf_doc)
        end

        # Применяет плотный межбуквенный интервал (минимальную ширину шрифта) к операциям вывода текста
        # @param pdf_doc [Prawn::Document]
        def self.apply_character_spacing(pdf_doc)
          return unless pdf_doc.respond_to?(:text_box)
          return if pdf_doc.respond_to?(:_dn1c_condensed_wrapped)

          pdf_doc.define_singleton_method(:_dn1c_condensed_wrapped) { true }

          pdf_doc.singleton_class.class_eval do
            alias_method :_orig_dn1c_text_box, :text_box
            def text_box(string, options = {})
              opts = options.dup
              opts[:character_spacing] = FontService::CHARACTER_SPACING unless opts.key?(:character_spacing)
              _orig_dn1c_text_box(string, opts)
            end

            alias_method :_orig_dn1c_height_of, :height_of
            def height_of(string, options = {})
              opts = options.dup
              opts[:character_spacing] = FontService::CHARACTER_SPACING unless opts.key?(:character_spacing)
              _orig_dn1c_height_of(string, opts)
            end

            if method_defined?(:formatted_text_box)
              alias_method :_orig_dn1c_formatted_text_box, :formatted_text_box
              def formatted_text_box(formatted_text, options = {})
                opts = options.dup
                opts[:character_spacing] = FontService::CHARACTER_SPACING unless opts.key?(:character_spacing)
                _orig_dn1c_formatted_text_box(formatted_text, opts)
              end
            end
          end
        end

        # Применяет предопределенный типографический стиль (шрифт и кегль) к документу PDF
        # @param pdf_doc [Prawn::Document] целевой документ PDF
        # @param style [Symbol] название стиля (:title, :subtitle, :heading, :body, :small, :stamp)
        # @return [void]
        def self.apply_style(pdf_doc, style = :body)
          font_name = (pdf_doc.font_families && pdf_doc.font_families.key?(FONT_NAME)) ? FONT_NAME : "Helvetica"
          case style
          when :title
            pdf_doc.font(font_name, size: 24)
          when :subtitle
            pdf_doc.font(font_name, size: 16)
          when :heading
            pdf_doc.font(font_name, size: 12)
          when :body
            pdf_doc.font(font_name, size: 10)
          when :small
            pdf_doc.font(font_name, size: 8)
          when :stamp
            pdf_doc.font(font_name, size: 26)
          else
            pdf_doc.font(font_name, size: 10)
          end
        end

        # Путь к TTF-файлу DIN Condensed, поставляемому с плагином
        # @return [String, nil]
        def self.bundled_din_font_path
          path = File.join(File.expand_path("../config/fonts", __dir__), "DIN Condensed.ttf")
          File.exist?(path) ? path : nil
        end

        # Каталог пользовательских шрифтов Windows (%LOCALAPPDATA%\Microsoft\Windows\Fonts)
        # @return [String]
        def self.user_fonts_dir
          File.join(ENV["LOCALAPPDATA"] || File.join(Dir.home, "AppData", "Local"),
                    "Microsoft", "Windows", "Fonts")
        end

        # Проверяет, установлено ли семейство DIN Condensed в системе (реестр + каталоги шрифтов)
        # @return [Boolean]
        def self.din_font_installed?
          font_file_installed? || registry_font_present?
        end

        # Устанавливает DIN Condensed в систему, если он отсутствует.
        # Стратегия:
        #   1) копия в пользовательские шрифты (%LOCALAPPDATA%\Microsoft\Windows\Fonts);
        #   2) если копирование запрещено (EACCES) — регистрируется TTF прямо из каталога плагина.
        # Файл регистрируется в HKCU-реестре (персистентно) и подгружается в текущую сессию
        # через AddFontResourceW — перезагрузка не требуется. Ошибки глушатся: экспорт
        # продолжится со стандартным шрифтом-заменой.
        # @return [Boolean] true, если семейство доступно (было или стало) в системе
        def self.ensure_din_font_installed!
          return @din_install_result unless @din_install_result.nil?
          return @din_install_result = true unless windows?

          @din_install_result = begin
            target_path = File.join(user_fonts_dir, "DIN Condensed.ttf")
            source_path = bundled_din_font_path
            return @din_install_result = false if source_path.nil? && !File.exist?(target_path)

            copied = false
            if source_path && !File.exist?(target_path)
              begin
                require "fileutils"
                FileUtils.mkdir_p(user_fonts_dir)
                FileUtils.cp(source_path, target_path)
                copied = true
              rescue StandardError
                copied = false
              end
            end
            copied = true if File.exist?(target_path)

            # Приоритет — копия в пользовательских шрифтах; при недоступности — файл плагина
            active_path = copied ? target_path : source_path
            register_user_font(active_path)
            load_font_into_session(active_path)

            din_font_installed?
          rescue StandardError => e
            warn "[DN1C Export PDF] Не удалось установить шрифт #{DIN_FAMILY_NAME}: #{e.message}"
            false
          end
        end

        # Возвращает имя семейства шрифтов для LayOut после попытки установки DIN Condensed.
        # Проверить фактическую доступность произвольного семейства через Ruby API нельзя,
        # поэтому возвращается первый кандидат — LayOut сам подставит замену, если шрифта нет.
        # @return [String]
        def self.layout_font_family
          if windows?
            ensure_din_font_installed!
            FONT_NAME
          else
            LAYOUT_FONT_CANDIDATES.first
          end
        end

        # --- Внутренние хелперы установки шрифта в систему ---

        # Определяет, что код выполняется в Windows
        def self.windows?
          Gem.win_platform? || RUBY_PLATFORM =~ /mswin|mingw/
        end

        # Ищет файл "DIN Condensed*.ttf" в стандартных каталогах шрифтов Windows
        def self.font_file_installed?
          dirs = [user_fonts_dir, File.join(ENV["WINDIR"] || "C:\\Windows", "Fonts")]
          dirs.any? do |dir|
            Dir.exist?(dir) && !Dir.glob(File.join(dir, "DIN Cond*.ttf")).empty?
          end
        end

        # Проверяет запись о шрифте в реестре (HKCU и HKLM)
        def self.registry_font_present?
          require "win32/registry"
          [
            Win32::Registry::HKEY_CURRENT_USER,
            Win32::Registry::HKEY_LOCAL_MACHINE
          ].any? do |hive|
            begin
              hive.open("Software\\Microsoft\\Windows NT\\CurrentVersion\\Fonts") do |reg|
                found = false
                reg.each_value do |name, _type, _value|
                  if name.to_s.start_with?(DIN_REGISTRY_NAME)
                    found = true
                    break
                  end
                end
                found
              end
            rescue StandardError
              false
            end
          end
        rescue LoadError
          false
        end

        # Регистрирует шрифт в HKCU-реестре (виден после перезапуска приложений)
        def self.register_user_font(font_path)
          require "win32/registry"
          Win32::Registry::HKEY_CURRENT_USER.create("Software\\Microsoft\\Windows NT\\CurrentVersion\\Fonts") do |reg|
            reg[DIN_REGISTRY_NAME] = font_path
          end
          true
        rescue StandardError
          false
        end

        # Подгружает шрифт в текущую сессию Windows через gdi32 AddFontResourceW
        def self.load_font_into_session(font_path)
          require "fiddle"
          gdi32 = Fiddle.dlopen("gdi32.dll")
          add_font = Fiddle::Function.new(gdi32["AddFontResourceW"], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)

          wstr = (font_path.to_s + "\0").encode("UTF-16LE")
          ptr = Fiddle::Pointer.malloc(wstr.bytesize)
          ptr[0, wstr.bytesize] = wstr
          result = add_font.call(ptr)
          return false if result.to_i <= 0

          # Уведомление приложений об изменении списка шрифтов (WM_FONTCHANGE)
          user32 = Fiddle.dlopen("user32.dll")
          send_msg = Fiddle::Function.new(
            user32["SendMessageTimeoutW"],
            [Fiddle::TYPE_LONG, Fiddle::TYPE_INT, Fiddle::TYPE_LONG, Fiddle::TYPE_LONG,
             Fiddle::TYPE_INT, Fiddle::TYPE_INT, Fiddle::TYPE_LONG],
            Fiddle::TYPE_LONG
          )
          hwnd_broadcast = 0xFFFF
          wm_fontchange  = 0x001D
          smto_abortifhung = 0x0002
          send_msg.call(hwnd_broadcast, wm_fontchange, 0, 0, smto_abortifhung, 1000, 0)
          true
        rescue StandardError, LoadError
          false
        end
      end
    end
  end
end
