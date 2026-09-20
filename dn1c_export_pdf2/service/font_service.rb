# frozen_string_literal: true

module DN1Code
  module ExportPdf2
    module Service
      # Сервис управления типографикой и шрифтовыми стилями PDF документа.
      # Регистрирует кастомные TTF-шрифты с кириллицей и задает шкалу размеров.
      module FontService
        # Основное имя зарегистрированного шрифтового семейства по умолчанию
        FONT_NAME = "Sofia Sans Condensed"

        # Список всех 5 шрифтов, поставляемых с расширением
        AVAILABLE_FONTS = {
          "Sofia Sans Condensed" => {
            files: ["SofiaSansCondensed-Regular.ttf"],
            reg: "Sofia Sans Condensed Regular (TrueType)",
            pattern: /Sofia\s*Sans\s*Cond/i
          },
          "Sofia Sans Extra Condensed" => {
            files: ["SofiaSansExtraCond-Regular.ttf"],
            reg: "Sofia Sans ExtraCond Regular (TrueType)",
            pattern: /Sofia\s*Sans\s*Extra\s*Cond/i
          },
          "Oswald" => {
            files: ["Oswald-Light.ttf"],
            reg: "Oswald Light (TrueType)",
            pattern: /Oswald\s*Light/i
          },
          "Roboto Condensed" => {
            files: ["RobotoCondensed-Regular.ttf"],
            reg: "Roboto Condensed Regular (TrueType)",
            pattern: /Roboto\s*Cond/i
          },
          "Ubuntu Condensed" => {
            files: ["UbuntuCondensed-Regular.ttf"],
            reg: "Ubuntu Condensed Regular (TrueType)",
            pattern: /Ubuntu\s*Cond/i
          }
        }.freeze

        # Цепочка семейств шрифтов для LayOut (по убыванию приоритета)
        LAYOUT_FONT_CANDIDATES = [
          "Sofia Sans Condensed", "Sofia Sans Extra Condensed", "Oswald", "Roboto Condensed", "Ubuntu Condensed", "Arial Narrow", "Segoe UI", "Arial"
        ].freeze

        # Точные имена начертаний (face), под которыми шрифты видит GDI/LayOut.
        # Используются только файлы из config/fonts: Oswald бандлится как Light,
        # поэтому запрашивать в LayOut нужно именно "Oswald Light", а не "Oswald"
        # (иначе LayOut может подхватить системный Oswald-Regular).
        LAYOUT_FACE_NAMES = {
          "Oswald" => "Oswald Light",
          # LayOut вырезает из имени семейства стилевой токен "Extra Condensed"
          # (получается несуществующее "Sofia Sans") и подставляет Verdana,
          # поэтому передаётся переименованное семейство — копия того же TTF
          # с внутренним именем "Sofia Sans ExtraCond" (SofiaSansExtraCond-Regular.ttf)
          "Sofia Sans Extra Condensed" => "Sofia Sans ExtraCond"
        }.freeze

        # Замена устаревших семейств: токен в имени => семейство-заменитель.
        # "DIN Condensed" больше не поставляется, старые проекты мигрируют на Oswald.
        LEGACY_FAMILY_ALIASES = { "din" => "Oswald" }.freeze

        # Каталог шрифтов, поставляемых с плагином
        # @return [String]
        def self.bundled_fonts_dir
          File.expand_path("../config/fonts", __dir__)
        end

        # Точное имя начертания для style.font_family в LayOut.
        # Семейство "Oswald" -> "Oswald Light" (файл из config/fonts), остальные — как есть.
        # @param family_name [String]
        # @return [String]
        def self.layout_face_name(family_name)
          LAYOUT_FACE_NAMES[family_name.to_s.strip] || family_name.to_s.strip
        end

        # Каталог пользовательских шрифтов Windows (%LOCALAPPDATA%\Microsoft\Windows\Fonts)
        # @return [String]
        def self.user_fonts_dir
          File.join(ENV["LOCALAPPDATA"] || File.join(Dir.home, "AppData", "Local"),
                    "Microsoft", "Windows", "Fonts")
        end

        # Проверяет, установлен ли конкретный шрифт в системе
        def self.font_installed?(family_name = FONT_NAME)
          cfg = find_font_config(family_name)
          if cfg
            dirs = [user_fonts_dir, File.join(ENV["WINDIR"] || "C:\\Windows", "Fonts")]
            file_present = dirs.any? do |dir|
              next false unless Dir.exist?(dir)
              cfg[:files].any? do |fn|
                File.exist?(File.join(dir, fn))
              end
            end
            return true if file_present || registry_has_font?(cfg[:pattern] || cfg[:reg])
          end

          # Проверка произвольного системного шрифта (Arial, Arial Narrow, Segoe UI и др.)
          pattern = Regexp.new(Regexp.escape(family_name.to_s.strip), Regexp::IGNORECASE)
          registry_has_font?(pattern)
        end

        # Нечёткое сопоставление имени шрифта (включая legacy "DIN Condensed" и
        # начертания вроде "Oswald Light") с ключом AVAILABLE_FONTS.
        # Единственная точка этой эвристики: используется в find_font_config,
        # layout_font_family и PdfFontAudit.
        # @param family_name [String]
        # @return [String, nil] ключ AVAILABLE_FONTS или nil
        def self.match_available_family(family_name)
          name_str = family_name.to_s.strip.downcase
          return nil if name_str.empty?

          AVAILABLE_FONTS.find do |fam, _cfg|
            fam_low = fam.downcase
            fam_low == name_str ||
              (name_str.include?("extra") && fam_low.include?("extra")) ||
              (!name_str.include?("extra") && !fam_low.include?("extra") && name_str.include?("sofia") && fam_low.include?("sofia")) ||
              (name_str.include?("oswald") && fam_low.include?("oswald")) ||
              (name_str.include?("din") && fam_low.include?("oswald")) ||
              (name_str.include?("roboto") && fam_low.include?("roboto")) ||
              (name_str.include?("ubuntu") && fam_low.include?("ubuntu"))
          end&.first
        end

        # Семейство-заменитель для устаревшего имени шрифта, если такое есть
        # @param family_name [String]
        # @return [String, nil]
        def self.legacy_family_for(family_name)
          name_str = family_name.to_s.downcase
          LEGACY_FAMILY_ALIASES.each do |token, fam|
            return fam if name_str.include?(token)
          end
          nil
        end

        # Поиск конфигурации шрифта по имени семейства
        def self.find_font_config(family_name)
          fam = match_available_family(family_name)
          fam && AVAILABLE_FONTS[fam]
        end

        # Универсальная установка активного шрифта
        def self.ensure_font_installed!(family_name = FONT_NAME)
          @installed_fonts_cache ||= {}
          cache_key = family_name.to_s.strip.downcase
          return @installed_fonts_cache[cache_key] if @installed_fonts_cache.key?(cache_key)
          return @installed_fonts_cache[cache_key] = true unless windows?

          cfg = find_font_config(family_name)
          unless cfg
            # Для системных шрифтов (Arial, Segoe UI и т.п.) проверяем их наличие в системе
            return @installed_fonts_cache[cache_key] = font_installed?(family_name)
          end

          @installed_fonts_cache[cache_key] = begin
            require "fileutils"
            FileUtils.mkdir_p(user_fonts_dir)

            installed_any = false
            newly_installed = false
            cfg[:files].each do |file_name|
              source_path = File.join(bundled_fonts_dir, file_name)
              next unless File.exist?(source_path)

              target_path = File.join(user_fonts_dir, file_name)
              unless File.exist?(target_path)
                newly_installed = true
                begin
                  FileUtils.cp(source_path, target_path)
                rescue StandardError => e
                  warn "[DN1C Export PDF] Не удалось скопировать шрифт #{file_name}: #{e.message}"
                end
              end

              active_path = File.exist?(target_path) ? target_path : source_path
              if File.exist?(active_path)
                reg_name = file_name.include?("Light") ? "Oswald Light (TrueType)" : cfg[:reg]
                register_user_font(active_path, reg_name)
                load_font_into_session(active_path)
                installed_any = true
              end
            end

            result = font_installed?(family_name) || installed_any
            if newly_installed
              # Шрифт попадает в коллекцию шрифтов LayOut только при старте
              # приложения — до перезапуска экспорт может идти с системным
              # фолбэком (Verdana), предупреждает пользователя заранее
              warn "[DN1C Export PDF] Шрифт '#{layout_face_name(family_name)}' установлен в систему. " \
                   "Если он не применился к страницам — перезапустите SketchUp и повторите экспорт."
            end
            result
          rescue StandardError => e
            warn "[DN1C Export PDF] Не удалось установить шрифт #{family_name}: #{e.message}"
            false
          end
        end

        # Возвращает точное имя шрифта для style.font_family в LayOut после
        # установки/проверки шрифта (для Oswald — начертание "Oswald Light",
        # т.к. плагин использует только файлы из config/fonts).
        # Поддерживает полную автозамену (шрифтовой fallback):
        # 1. Замена DIN Condensed на Oswald (для обратной совместимости старых проектов).
        # 2. Если выбранный/запрошенный шрифт недоступен в системе и не может быть установлен,
        #    автоматически выбирается первый гарантированно доступный шрифт из цепочки замен (LAYOUT_FONT_CANDIDATES).
        # @param settings [Hash, String, nil]
        # @return [String]
        def self.layout_font_family(settings = nil)
          requested = nil
          if settings.is_a?(Hash)
            requested = settings[:font_family] || settings["font_family"]
          elsif settings.is_a?(String)
            requested = settings
          end
          requested = requested.to_s.strip unless requested.nil?

          matched_name = nil
          if requested && !requested.empty?
            matched_name = match_available_family(requested) || requested
          end

          target_family = matched_name || FONT_NAME

          if windows?
            repair_font_registrations_once!
            installed = ensure_font_installed!(target_family)
            # Учесть замену: если запрошенный шрифт отсутствует и не может быть установлен,
            # производим автозамену на доступного кандидата из списка приоритетов
            unless installed || font_installed?(target_family)
              fallback_cand = LAYOUT_FONT_CANDIDATES.find do |cand|
                ensure_font_installed!(cand) || font_installed?(cand)
              end
              target_family = fallback_cand || FONT_NAME
            end
            unless ensure_font_resolvable!(target_family)
              # Начертание не резолвится даже после перезагрузки в сессию:
              # LayOut подставил бы Verdana — заменяем на резолвимый кандидат
              resolvable_cand = LAYOUT_FONT_CANDIDATES.find do |cand|
                cand != target_family &&
                  (ensure_font_installed!(cand) || font_installed?(cand)) &&
                  ensure_font_resolvable!(cand)
              end
              if resolvable_cand
                warn "[DN1C Export PDF] Шрифт '#{layout_face_name(target_family)}' недоступен " \
                     "в этой сессии — использован '#{layout_face_name(resolvable_cand)}'. " \
                     "Перезапустите SketchUp, чтобы применить выбранный шрифт."
                target_family = resolvable_cand
              end
            end
            layout_face_name(target_family)
          else
            layout_face_name(target_family || LAYOUT_FONT_CANDIDATES.first)
          end
        end

        # Разовая чистка реестра шрифтов за сессию (вызывается перед первым экспортом)
        def self.repair_font_registrations_once!
          @font_repair_done ||= false
          return if @font_repair_done

          @font_repair_done = true
          repair_font_registrations!
        end

        # --- Внутренние хелперы установки шрифта в систему ---

        # Определяет, что код выполняется в Windows
        def self.windows?
          Gem.win_platform? || RUBY_PLATFORM =~ /mswin|mingw/
        end

        # Проверяет запись о шрифте в реестре
        def self.registry_has_font?(pattern)
          require "win32/registry"
          [
            Win32::Registry::HKEY_CURRENT_USER,
            Win32::Registry::HKEY_LOCAL_MACHINE
          ].any? do |hive|
            begin
              hive.open("Software\\Microsoft\\Windows NT\\CurrentVersion\\Fonts") do |reg|
                found = false
                reg.each_value do |name, _type, _value|
                  match = pattern.is_a?(Regexp) ? (name.to_s =~ pattern) : name.to_s.start_with?(pattern.to_s)
                  if match
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
        def self.register_user_font(font_path, reg_name = "Sofia Sans Condensed Regular (TrueType)")
          require "win32/registry"
          # Канонический путь с обратными слэшами — смешанные разделители
          # в реестре мешают загрузке шрифта частью приложений
          Win32::Registry::HKEY_CURRENT_USER.create("Software\\Microsoft\\Windows NT\\CurrentVersion\\Fonts") do |reg|
            reg[reg_name] = font_path.to_s.tr("/", "\\")
          end
          true
        rescue StandardError
          false
        end

        # Каноническое имя записи реестра для файла шрифта из бандла
        def self.canonical_reg_name_for_file(file_name)
          if file_name == "Oswald-Light.ttf"
            "Oswald Light (TrueType)"
          else
            cfg = AVAILABLE_FONTS.values.find { |c| Array(c[:files]).include?(file_name) }
            cfg && cfg[:reg]
          end
        end

        # Чистит HKCU-реестр от дублирующихся записей, указывающих на файлы шрифтов
        # из config/fonts (например "Sofia Sans Extra Condensed (TrueType)" и
        # "Sofia Sans Extra Condensed Regular (TrueType)" на один файл), и удаляет
        # .bak-копии наших шрифтов. Чужие записи не затрагиваются.
        # @return [Integer] количество удалённых дублирующихся записей
        def self.repair_font_registrations!
          return 0 unless windows?

          require "win32/registry"
          bundled_names = AVAILABLE_FONTS.values
                                          .flat_map { |c| Array(c[:files]) }
                                          .compact
                                          .select { |fn| File.exist?(File.join(bundled_fonts_dir, fn)) }
                                          .uniq
          repaired = 0
          Win32::Registry::HKEY_CURRENT_USER.create("Software\\Microsoft\\Windows NT\\CurrentVersion\\Fonts") do |reg|
            dupes = []
            reg.each_value do |name, _type, data|
              next if data.nil? || data.to_s.empty?

              base = File.basename(data.to_s)
              next unless bundled_names.include?(base)

              canonical = canonical_reg_name_for_file(base)
              dupes << name if canonical && name != canonical
            end
            dupes.each do |name|
              begin
                reg.delete_value(name)
                repaired += 1
              rescue StandardError
                # значение могло быть уже удалено параллельным процессом
              end
            end
          end

          begin
            require "fileutils"
            bundled_names.each do |bn|
              FileUtils.rm_f(File.join(user_fonts_dir, "#{bn}.bak"))
            end
          rescue StandardError
            # .bak не критичен
          end
          repaired
        rescue StandardError
          0
        end

        # Проверяет, что GDI реально резолвит шрифт с указанным именем начертания
        # (создаёт HFONT и спрашивает у контекста фактическое имя выбранного шрифта).
        # При ошибке проверки возвращает true (не блокируем экспорт).
        # @param face_name [String]
        # @return [Boolean]
        def self.font_resolvable?(face_name)
          return true unless windows?
          return true if face_name.nil? || face_name.to_s.strip.empty?

          require "fiddle"
          gdi32  = Fiddle.dlopen("gdi32.dll")
          user32 = Fiddle.dlopen("user32.dll")
          vp     = Fiddle::TYPE_VOIDP
          int    = Fiddle::TYPE_INT
          # CreateFontW: 13 int-параметров + lpszFace (раньше было 14+1 —
          # вызов всегда падал с ArgumentError и функция молча возвращала true)
          create_font   = Fiddle::Function.new(gdi32["CreateFontW"],   [int] * 13 + [vp], vp)
          get_dc        = Fiddle::Function.new(user32["GetDC"],        [vp], vp)
          release_dc    = Fiddle::Function.new(user32["ReleaseDC"],    [vp, vp], int)
          select_object = Fiddle::Function.new(gdi32["SelectObject"],  [vp, vp], vp)
          delete_object = Fiddle::Function.new(gdi32["DeleteObject"],  [vp], int)
          get_text_face = Fiddle::Function.new(gdi32["GetTextFaceW"],  [vp, int, vp], int)

          wname = (face_name.to_s + "\0").encode("UTF-16LE")
          fptr = Fiddle::Pointer.malloc(wname.bytesize)
          fptr[0, wname.bytesize] = wname
          # -11 = 11pt (height), 400 = normal weight, 1 = DEFAULT_CHARSET
          hfont = create_font.call(-11, 0, 0, 0, 400, 0, 0, 0, 1, 0, 0, 0, 0, fptr)
          return false if hfont.nil? || hfont.to_i.zero?

          hdc = get_dc.call(nil)
          resolvable = false
          if hdc && !hdc.to_i.zero?
            old = select_object.call(hdc, hfont)
            buf = Fiddle::Pointer.malloc(512)
            n = get_text_face.call(hdc, 128, buf)
            if n > 0
              used = buf[0, n * 2].force_encoding("UTF-16LE").encode("UTF-8").delete("\0").strip
              resolvable = !used.empty? && used.casecmp(face_name.to_s.strip).zero?
            end
            select_object.call(hdc, old) if old && !old.to_i.zero?
            release_dc.call(nil, hdc)
          end
          delete_object.call(hfont)
          resolvable
        rescue StandardError, LoadError
          true
        end

        # Гарантирует, что начертание семейства резолвится GDI. Если нет —
        # повторно подгружает файл шрифта в сессию (AddFontResourceW +
        # WM_FONTCHANGE); если не помогло — предупреждает о необходимости
        # перезапуска SketchUp/LayOut (список шрифтов кэшируется на старте).
        # @param family_name [String] имя семейства из AVAILABLE_FONTS
        # @return [Boolean]
        def self.ensure_font_resolvable!(family_name)
          face = layout_face_name(family_name)
          return true unless windows?
          return true if font_resolvable?(face)

          cfg = find_font_config(family_name)
          if cfg
            file = Array(cfg[:files]).find do |fn|
              File.exist?(File.join(user_fonts_dir, fn)) || File.exist?(File.join(bundled_fonts_dir, fn))
            end
            if file
              path = [File.join(user_fonts_dir, file), File.join(bundled_fonts_dir, file)]
                     .find { |p| File.exist?(p) }
              load_font_into_session(path) if path
            end
          end

          return true if font_resolvable?(face)

          @font_restart_warned ||= {}
          unless @font_restart_warned[face]
            @font_restart_warned[face] = true
            warn "[DN1C Export PDF] Шрифт '#{face}' пока не виден системе. " \
                 "Если в PDF он заменится на fallback — перезапустите SketchUp/LayOut."
          end
          false
        rescue StandardError
          true
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
