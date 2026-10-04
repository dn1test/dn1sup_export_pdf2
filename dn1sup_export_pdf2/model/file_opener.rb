# frozen_string_literal: true

module DN1Code
  module ExportPdf2
    module Model
      # Открытие файлов и папок системной программой по умолчанию.
      # Основной механизм на Windows — ShellExecuteW по сырому пути (fiddle):
      # кириллица, '#', пробелы и '~' работают нативно, без URL-кодирования.
      # UI.openURL с file:/// URL ненадёжен (процент-кодированный путь не
      # декодируется обработчиком по умолчанию) и используется только как фолбэк.
      module FileOpener
        class << self
          # Тестовый перехватчик: Proc(path) -> Boolean, подменяет системный вызов
          # целиком (в тестах под system Ruby на Windows fiddle доступен, и без
          # перехватчика ShellExecuteW реально открывал бы файлы).
          attr_accessor :launcher_override

          # Открывает файл или папку системной программой по умолчанию.
          # @param path [String, nil] путь к файлу или папке
          # @return [Boolean] удалось ли открыть
          def open_path(path)
            clean = path.to_s.strip
            if clean.empty? || !File.exist?(clean)
              warn "Не удалось открыть: путь не найден (#{clean})"
              return false
            end

            return launcher_override.call(clean) if launcher_override
            return true if windows? && shell_execute_w(clean)

            open_via_url(clean)
          end

          # Похожа ли ситуация на «файл открыт другой программой»: просмотрщики
          # PDF и офисные редакторы открывают файл без разделяемого доступа на
          # запись, поэтому попытка открыть его в режиме r+b падает с
          # EACCES/EBUSY. Read-only атрибут — не «открыт», возвращаем false.
          # @param path [String, nil] путь к файлу
          # @return [Boolean]
          def file_locked?(path)
            clean = path.to_s.strip
            return false if clean.empty? || !File.exist?(clean)
            return false unless File.writable?(clean)

            File.open(clean, "r+b") {}
            false
          rescue Errno::EACCES, Errno::EBUSY, Errno::EPERM, IOError
            true
          end

          private

          def windows?
            RbConfig::CONFIG["host_os"] =~ /mswin|mingw/
          end

          # @return [Boolean] true при успехе; false — фолбэк на openURL
          def shell_execute_w(path)
            require "fiddle"
            shell32 = Fiddle.dlopen("shell32.dll")
            execute = Fiddle::Function.new(
              shell32["ShellExecuteW"],
              [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP,
               Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
              Fiddle::TYPE_LONG
            )
            ret = execute.call(nil, utf16("open"), utf16(path), nil, nil, 1)
            ret > 32
          rescue StandardError, LoadError => e
            warn "ShellExecuteW недоступен (#{e.message}), фолбэк на UI.openURL"
            false
          end

          # UTF-16LE с явным двухбайтовым NUL-терминатором. Терминатор тоже
          # кодируется в UTF-16LE: конкатенация с ASCII-строкой бросила бы
          # Encoding::CompatibilityError (UTF-16LE не ASCII-совместима).
          def utf16(str)
            (str.encode("UTF-16LE") + "\0".encode("UTF-16LE")).b
          end

          def open_via_url(path)
            return false unless defined?(UI) && UI.respond_to?(:openURL)

            url = PathUtil.file_url(path)
            opened = UI.openURL(url)
            warn "Не удалось открыть «#{path}» через UI.openURL (#{url})" unless opened == true
            opened == true
          end
        end
      end
    end
  end
end
