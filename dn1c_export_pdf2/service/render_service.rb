# frozen_string_literal: true

require "securerandom"
require "tmpdir"
require "fileutils"

module DN1Code
  module ExportPdf2
    module Service
      module RenderService
        # Соотношение сторон для стандартных печатных листов ISO A (A4, A3, A2) = 1 / sqrt(2) ≈ 0.7071
        DEFAULT_ISO_RATIO = 0.7071

        # Рендеринг сцены во временный PNG-файл
        def self.render_scene_temp(model, scene, options = {})
          width        = options[:image_width] || 2400
          ratio        = options[:ratio] || DEFAULT_ISO_RATIO
          height       = options[:image_height] || (width * ratio).round
          scale_factor = options[:scale_factor] || 2.0
          antialias    = options.fetch(:antialias, true)

          temp_file = File.join(Dir.tmpdir, "su_scene_#{SecureRandom.hex(8)}.png").tr("\\", "/")

          # Переключаем сцену в SketchUp
          if model.respond_to?(:pages) && scene
            model.pages.selected_page = scene
          end

          view = model.respond_to?(:active_view) ? model.active_view : nil

          if view && view.respond_to?(:write_image)
            write_options = {
              filename:     temp_file,
              width:        width,
              height:       height,
              antialias:    antialias,
              scale_factor: scale_factor
            }
            view.write_image(write_options)
          else
            # Если рендер запущен в автономном/тестовом окружении или моке, создаем placeholder PNG
            create_fallback_image(temp_file, width, height, scene ? scene.name : "Scene")
          end

          temp_file
        end

        # Безопасное удаление временных файлов после завершения сборки PDF
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

        # Создание простого fallback изображения (1x1 или базовый PNG) для тестов
        def self.create_fallback_image(file_path, width = 800, height = 600, label = "")
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
      end
    end
  end
end
