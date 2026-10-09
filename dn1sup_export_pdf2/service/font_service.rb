# frozen_string_literal: true

module DN1Code
  module ExportPdf2
    module Service
      # Сервис управления типографикой и шрифтовыми стилями PDF документа.
      # Регистрирует вариативные TTF-шрифты с кириллицей (config/fonts) и
      # задает шкалу размеров. Используются ТОЛЬКО шрифты из комплекта
      # плагина: системные шрифты Windows (Arial, Verdana, Segoe UI и т.п.)
      # сознательно не задействованы ни как выбор, ни как fallback.
      module FontService
        # Основное имя зарегистрированного шрифтового семейства по умолчанию
        FONT_NAME = "Sofia Sans Condensed"

        # Список всех 5 шрифтов, поставляемых с расширением (вариативные VF
        # содержат все начертания от Thin до Black в одном файле).
        AVAILABLE_FONTS = {
          "Sofia Sans Condensed" => {
            files: ["SofiaSansCondensed-VariableFont_wght.ttf"],
            reg: "Sofia Sans Condensed Variable (TrueType)",
            pattern: /Sofia\s*Sans\s*Cond/i
          },
          "Sofia Sans Extra Condensed" => {
            files: ["SofiaSansExtraCond-VariableFont_wght.ttf"],
            reg: "Sofia Sans ExtraCond Variable (TrueType)",
            pattern: /Sofia\s*Sans\s*Extra\s*Cond/i
          },
          "Oswald" => {
            files: ["Oswald-VariableFont_wght.ttf"],
            reg: "Oswald Variable (TrueType)",
            pattern: /Oswald/i
          },
          "Roboto Condensed" => {
            files: ["RobotoCondensed-VariableFont_wght.ttf"],
            reg: "Roboto Condensed Variable (TrueType)",
            pattern: /Roboto\s*Cond/i
          },
          "Ubuntu Condensed" => {
            files: ["UbuntuCondensed-Regular.ttf"],
            reg: "Ubuntu Condensed Regular (TrueType)",
            pattern: /Ubuntu\s*Cond/i
          }
        }.freeze

        # Цепочка семейств шрифтов для LayOut (по убыванию приоритета).
        # Только шрифты из комплекта: системные шрифты не используются.
        LAYOUT_FONT_CANDIDATES = [
          "Sofia Sans Condensed", "Sofia Sans Extra Condensed", "Oswald", "Roboto Condensed", "Ubuntu Condensed"
        ].freeze

        # Точные имена начертаний (face), под которыми шрифты видит GDI/LayOut.
        # "Sofia Sans Extra Condensed" передаётся как переименованное семейство
        # "Sofia Sans ExtraCond": VF из config/fonts офлайн-переименован, т.к.
        # LayOut вырезает из имени семейства стилевой токен "Extra Condensed"
        # (получается несуществующее "Sofia Sans") и может подставить Verdana.
        # Заодно уникальное имя исключает коллизии со старыми статическими
        # шрифтами, оставшимися в системе от прежних версий плагина.
        LAYOUT_FACE_NAMES = {
          "Sofia Sans Extra Condensed" => "Sofia Sans ExtraCond"
        }.freeze

        # Замена устаревших семейств: токен в имени => семейство-заменитель.
        # "DIN Condensed" больше не поставляется, старые проекты мигрируют на Oswald.
        LEGACY_FAMILY_ALIASES = { "din" => "Oswald" }.freeze

        # Статические файлы прежних версий плагина. При первом экспорте
        # вычищаются из пользовательской папки шрифтов и HKCU-реестра, чтобы
        # старые копии не затеняли вариативные шрифты нового комплекта.
        LEGACY_FONT_FILES = {
          "Oswald-Light.ttf" => "Oswald Light (TrueType)",
          "RobotoCondensed-Regular.ttf" => "Roboto Condensed Regular (TrueType)",
          "SofiaSansCondensed-Regular.ttf" => "Sofia Sans Condensed Regular (TrueType)",
          "SofiaSansExtraCond-Regular.ttf" => "Sofia Sans ExtraCond Regular (TrueType)",
          "SofiaSansExtraCondensed-Regular.ttf" => "Sofia Sans Extra Condensed Regular (TrueType)"
        }.freeze

        # Допустимые значения параметров начертания (жирности) и ширины шрифта.
        FONT_WEIGHTS = %w[normal bold].freeze
        FONT_WEIGHT_DEFAULT = "normal"

        # Ширина: параметр-модификатор семейства "Sofia Sans Condensed".
        # "extra_condensed" повышает сжатие до Sofia Sans Extra Condensed,
        # "condensed" оставляет базовое семейство. Явно выбранные семейства
        # ("Sofia Sans Extra Condensed", Oswald, Roboto Condensed, Ubuntu
        # Condensed) параметром не изменяются.
        FONT_WIDTHS = %w[condensed extra_condensed].freeze
        FONT_WIDTH_DEFAULT = "condensed"
        FONT_WIDTH_VARIANTS = {
          "condensed" => {
            "Sofia Sans Condensed" => "Sofia Sans Condensed"
          },
          "extra_condensed" => {
            "Sofia Sans Condensed" => "Sofia Sans Extra Condensed"
          }
        }.freeze

        class << self
          # Каталог шрифтов, поставляемых с плагином
          # @return [String]
          def bundled_fonts_dir
            File.expand_path("../config/fonts", __dir__)
          end

          # Точное имя начертания для style.font_family в LayOut.
          # "Sofia Sans Extra Condensed" -> "Sofia Sans ExtraCond" (переименованный VF).
          # @param family_name [String]
          # @return [String]
          def layout_face_name(family_name)
            LAYOUT_FACE_NAMES[family_name.to_s.strip] || family_name.to_s.strip
          end

          # Каталог пользовательских шрифтов Windows (%LOCALAPPDATA%\Microsoft\Windows\Fonts)
          # @return [String]
          def user_fonts_dir
            File.join(ENV["LOCALAPPDATA"] || File.join(Dir.home, "AppData", "Local"),
                      "Microsoft", "Windows", "Fonts")
          end

          # Проверяет, установлен ли шрифт комплекта в пользовательскую папку.
          # Системные шрифты (C:\Windows\Fonts, HKLM) сознательно не учитываются:
          # плагин использует только собственный комплект.
          def font_installed?(family_name = FONT_NAME)
            cfg = find_font_config(family_name)
            return false unless cfg

            dir = user_fonts_dir
            file_present = File.directory?(dir) &&
                           cfg[:files].any? { |fn| File.exist?(File.join(dir, fn)) }
            return true if file_present || registry_has_font?(cfg[:pattern] || cfg[:reg])

            false
          end

          # Нормализованное значение параметра начертания ("normal"/"bold")
          # @param settings [Hash, nil]
          # @return [String]
          def font_weight_setting(settings)
            return FONT_WEIGHT_DEFAULT unless settings.is_a?(Hash)

            w = (settings[:font_weight] || settings["font_weight"]).to_s.downcase.strip
            FONT_WEIGHTS.include?(w) ? w : FONT_WEIGHT_DEFAULT
          end

          # Нормализованное значение параметра ширины ("condensed"/"extra_condensed")
          # @param settings [Hash, nil]
          # @return [String]
          def font_width_setting(settings)
            return FONT_WIDTH_DEFAULT unless settings.is_a?(Hash)

            w = (settings[:font_width] || settings["font_width"]).to_s.downcase.strip
            FONT_WIDTHS.include?(w) ? w : FONT_WIDTH_DEFAULT
          end

          # Применяет параметр ширины к семейству: для базового "Sofia Sans
          # Condensed" возвращает вариант по ключу ширины, остальные семейства
          # (в т.ч. явно выбранное Extra Condensed) остаются без изменений.
          # @param family_name [String]
          # @param width [String] "condensed" | "extra_condensed"
          # @return [String]
          def apply_font_width(family_name, width)
            fam = match_available_family(family_name) || family_name.to_s.strip
            variants = FONT_WIDTH_VARIANTS[width.to_s]
            variants&.[](fam) || fam
          end

          # Нечёткое сопоставление имени шрифта (включая legacy "DIN Condensed" и
          # начертания вроде "Oswald Light") с ключом AVAILABLE_FONTS.
          # Единственная точка этой эвристики: используется в find_font_config,
          # layout_font_family и PdfFontAudit.
          # @param family_name [String]
          # @return [String, nil] ключ AVAILABLE_FONTS или nil
          def match_available_family(family_name)
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
          def legacy_family_for(family_name)
            name_str = family_name.to_s.downcase
            LEGACY_FAMILY_ALIASES.each do |token, fam|
              return fam if name_str.include?(token)
            end
            nil
          end

          # Поиск конфигурации шрифта по имени семейства
          def find_font_config(family_name)
            fam = match_available_family(family_name)
            fam && AVAILABLE_FONTS[fam]
          end

          # Универсальная установка активного шрифта
          def ensure_font_installed!(family_name = FONT_NAME)
            @installed_fonts_cache ||= {}
            cache_key = family_name.to_s.strip.downcase
            return @installed_fonts_cache[cache_key] if @installed_fonts_cache.key?(cache_key)
            return @installed_fonts_cache[cache_key] = true unless windows?

            cfg = find_font_config(family_name)
            unless cfg
              # Небандлные имена не поддерживаются: используем только комплект
              return @installed_fonts_cache[cache_key] = false
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
                    warn "[DN1Sup Export PDF] Не удалось скопировать шрифт #{file_name}: #{e.message}"
                  end
                end

                active_path = File.exist?(target_path) ? target_path : source_path
                if File.exist?(active_path)
                  register_user_font(active_path, cfg[:reg])
                  load_font_into_session(active_path)
                  installed_any = true
                end
              end

              result = font_installed?(family_name) || installed_any
              if newly_installed
                # Шрифт попадает в коллекцию шрифтов LayOut только при старте
                # приложения — до перезапуска экспорт может идти с системным
                # фолбэком (Verdana), предупреждает пользователя заранее
                warn "[DN1Sup Export PDF] Шрифт '#{layout_face_name(family_name)}' установлен в систему. " \
                     "Если он не применился к страницам — перезапустите SketchUp и повторите экспорт."
              end
              result
            rescue StandardError => e
              warn "[DN1Sup Export PDF] Не удалось установить шрифт #{family_name}: #{e.message}"
              false
            end
          end

          # Возвращает точное имя шрифта для style.font_family в LayOut после
          # установки/проверки шрифта (учитывает параметр ширины font_width и
          # переименованные семейства из LAYOUT_FACE_NAMES).
          # Поддерживает полную автозамену (шрифтовой fallback):
          # 1. Замена DIN Condensed на Oswald (для обратной совместимости старых проектов).
          # 2. Если выбранный/запрошенный шрифт недоступен и не может быть установлен,
          #    автоматически выбирается первый доступный шрифт из комплекта
          #    (LAYOUT_FONT_CANDIDATES). Системные шрифты Windows не используются.
          # @param settings [Hash, String, nil]
          # @return [String]
          def layout_font_family(settings = nil)
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
            target_family = apply_font_width(target_family, font_width_setting(settings))

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
                  warn "[DN1Sup Export PDF] Шрифт '#{layout_face_name(target_family)}' недоступен " \
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
          def repair_font_registrations_once!
            @font_repair_done ||= false
            return if @font_repair_done

            @font_repair_done = true
            repair_font_registrations!
            cleanup_legacy_fonts!
          end

          # Определяет, что код выполняется в Windows
          def windows?
            Gem.win_platform? || RUBY_PLATFORM =~ /mswin|mingw/
          end

          # Проверяет запись о шрифте в HKCU-реестре (пользовательские шрифты).
          # HKLM (системные шрифты C:\Windows\Fonts) сознательно не проверяется.
          def registry_has_font?(pattern)
            require "win32/registry"
            Win32::Registry::HKEY_CURRENT_USER.open("Software\\Microsoft\\Windows NT\\CurrentVersion\\Fonts") do |reg|
              reg.each_value do |name, _type, _value|
                match = pattern.is_a?(Regexp) ? (name.to_s =~ pattern) : name.to_s.start_with?(pattern.to_s)
                return true if match
              end
            end
            false
          rescue StandardError, LoadError
            false
          end

          # Регистрирует шрифт в HKCU-реестре (виден после перезапуска приложений)
          def register_user_font(font_path, reg_name = "Sofia Sans Condensed Variable (TrueType)")
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
          def canonical_reg_name_for_file(file_name)
            cfg = AVAILABLE_FONTS.values.find { |c| Array(c[:files]).include?(file_name) }
            cfg&.[](:reg) || LEGACY_FONT_FILES[file_name]
          end

          # Чистит HKCU-реестр от дублирующихся записей, указывающих на файлы шрифтов
          # из config/fonts (например "Sofia Sans Extra Condensed (TrueType)" и
          # "Sofia Sans Extra Condensed Regular (TrueType)" на один файл), и удаляет
          # .bak-копии наших шрифтов. Чужие записи не затрагиваются.
          # @return [Integer] количество удалённых дублирующихся записей
          def repair_font_registrations!
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

          # Миграция со статических шрифтов прежних версий плагина: удаляет
          # из пользовательской папки и HKCU-реестра файлы LEGACY_FONT_FILES.
          # Ручные установки пользователя с другими именами файлов не затрагиваются.
          # @return [Integer] количество удалённых файлов
          def cleanup_legacy_fonts!
            return 0 unless windows?

            require "fileutils"
            require "win32/registry"
            removed = 0
            Win32::Registry::HKEY_CURRENT_USER.create("Software\\Microsoft\\Windows NT\\CurrentVersion\\Fonts") do |reg|
              stale = []
              reg.each_value do |name, _type, data|
                next if data.nil? || data.to_s.empty?

                stale << name if LEGACY_FONT_FILES.key?(File.basename(data.to_s))
              end
              stale.each do |name|
                begin
                  reg.delete_value(name)
                rescue StandardError
                  # уже удалено
                end
              end
            end

            LEGACY_FONT_FILES.each_key do |fn|
              path = File.join(user_fonts_dir, fn)
              next unless File.exist?(path)

              # Выгружаем из GDI-сессии ДО удаления файла: RemoveFontResourceW
              # требует существующий путь, рег-имя тут не подходит
              unload_font_from_session(fn)
              begin
                FileUtils.rm_f(path)
                removed += 1
              rescue StandardError
                # файл занят другим процессом — пропускаем
              end
            end
            removed
          rescue StandardError
            0
          end

          # Проверяет, что GDI реально резолвит шрифт с указанным именем начертания
          # (создаёт HFONT и спрашивает у контекста фактическое имя выбранного шрифта).
          # При ошибке проверки возвращает true (не блокируем экспорт).
          # @param face_name [String]
          # @return [Boolean]
          def font_resolvable?(face_name)
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
          def ensure_font_resolvable!(family_name)
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
              warn "[DN1Sup Export PDF] Шрифт '#{face}' пока не виден системе. " \
                   "Если в PDF он заменится на fallback — перезапустите SketchUp/LayOut."
            end
            false
          rescue StandardError
            true
          end

          # Подгружает шрифт в текущую сессию Windows через gdi32 AddFontResourceW
          def load_font_into_session(font_path)
            require "fiddle"
            gdi32 = Fiddle.dlopen("gdi32.dll")
            add_font = Fiddle::Function.new(gdi32["AddFontResourceW"], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)

            wstr = (font_path.to_s + "\0").encode("UTF-16LE")
            ptr = Fiddle::Pointer.malloc(wstr.bytesize)
            ptr[0, wstr.bytesize] = wstr
            result = add_font.call(ptr)
            return false if result.to_i <= 0

            # Уведомление приложений об изменении списка шрифтов (WM_FONTCHANGE)
            notify_fonts_changed
            true
          rescue StandardError, LoadError
            false
          end

          # Уведомление приложений об изменении списка шрифтов (WM_FONTCHANGE)
          def notify_fonts_changed
            require "fiddle"
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

          # Выгружает шрифт из текущей сессии по имени файла (RemoveFontResourceW)
          def unload_font_from_session(file_or_reg_name)
            require "fiddle"
            gdi32 = Fiddle.dlopen("gdi32.dll")
            remove_font = Fiddle::Function.new(gdi32["RemoveFontResourceW"], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)

            file_name = File.basename(file_or_reg_name.to_s)
            path = File.join(user_fonts_dir, file_name)
            return false unless File.file?(path)

            wstr = (path + "\0").encode("UTF-16LE")
            ptr = Fiddle::Pointer.malloc(wstr.bytesize)
            ptr[0, wstr.bytesize] = wstr
            remove_font.call(ptr)
            true
          rescue StandardError, LoadError
            false
          end
        end
      end
    end
  end
end
