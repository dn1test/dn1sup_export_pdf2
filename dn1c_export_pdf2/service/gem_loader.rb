# frozen_string_literal: true

module DN1Code
  module ExportPdf2
    module Service
      # Сервис проверки и динамической загрузки сторонних библиотек (gem prawn, pdf-core, ttfunk)
      # в среде встроенного Ruby интерпретатора SketchUp.
      module GemLoader
        # Проверяет наличие и загружает gem Prawn и сопутствующие библиотеки.
        # В случае отсутствия выполняет поиск в локальных путях пользователя
        # или выводит сообщение пользователю с инструкцией по установке.
        # @return [Boolean] true, если Prawn успешно загружен или уже определен, иначе false
        def self.ensure_prawn_loaded!
          return true if defined?(Prawn::Document)

          begin
            require "prawn"
            require "pdf/core"
            require "ttfunk"
            true
          rescue LoadError => e
            # Попытка найти gem в стандартных путях SketchUp или локальном кэше гемов
            if defined?(Gem) && Gem.respond_to?(:paths)
              user_gems = File.expand_path("~/.local/share/gem/ruby")
              Dir.glob("#{user_gems}/**/gems/prawn-*/lib").each { |p| $LOAD_PATH.unshift(p) }
              Dir.glob("#{user_gems}/**/gems/pdf-core-*/lib").each { |p| $LOAD_PATH.unshift(p) }
              Dir.glob("#{user_gems}/**/gems/ttfunk-*/lib").each { |p| $LOAD_PATH.unshift(p) }

              begin
                require "prawn"
                return true
              rescue LoadError
                # Ниже покажем диалог
              end
            end

            msg = "Gem 'prawn' не найден в среде SketchUp Ruby.\n" \
                  "Ошибка: #{e.message}\n\n" \
                  "Установите его через консоль Ruby SketchUp командой:\n" \
                  "Gem.install('prawn')"
            
            if defined?(UI) && UI.respond_to?(:messagebox)
              UI.messagebox(msg, defined?(MB_OK) ? MB_OK : 0)
            else
              warn msg
            end
            false
          end
        end
      end
    end
  end
end
