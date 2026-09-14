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

        # Цепочка семейств шрифтов для LayOut (по убыванию приоритета)
        LAYOUT_FONT_CANDIDATES = [
          "DIN Condensed", "Arial Narrow", "Roboto Condensed", "Segoe UI", "Arial"
        ].freeze



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
