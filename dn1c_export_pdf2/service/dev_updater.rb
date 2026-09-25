# frozen_string_literal: true

require "fileutils"
require_relative "../version"

module DN1Code
  module ExportPdf2
    module Service
      # Сервис обновления расширения из каталога разработки (dev-папки)
      # в системную директорию Plugins SketchUp с поддержкой горячей перезагрузки
      module DevUpdater
        DEFAULT_DEV_DIR = "U:/dn1code/su_plugs_app/dn1c_export_pdf2"

        # Игнорируемые файлы и папки при копировании в Plugins
        EXCLUDE_PATTERNS = [
          /\A\.git/,
          /\A\.zcode/,
          /\A\.tmp/,
          /\Atest/,
          /\Adist/,
          /\Ascratch/,
          /\AGemfile/,
          /\.bak\z/i,
          /\.tmp\z/i
        ].freeze

        module_function

        # Определяет путь к папке разработки (dev_dir)
        # @param custom_path [String, nil] пользовательский путь
        # @return [String, nil] абсолютный путь к папке разработки
        def resolve_dev_dir(custom_path = nil)
          candidates = [
            custom_path,
            ENV["DN1C_DEV_DIR"],
            DEFAULT_DEV_DIR,
            File.expand_path("../..", __dir__) # Если запущено из dev-копии
          ].compact.map { |p| p.to_s.tr("\\", "/").sub(%r{/+\z}, "") }

          candidates.find do |dir|
            !dir.empty? &&
              File.exist?(File.join(dir, "dn1c_export_pdf2.rb")) &&
              File.exist?(File.join(dir, "dn1c_export_pdf2", "main.rb"))
          end
        end

        # Определяет целевой каталог Plugins SketchUp
        # @param custom_plugins_dir [String, nil]
        # @return [String]
        def resolve_plugins_dir(custom_plugins_dir = nil)
          if custom_plugins_dir && Dir.exist?(custom_plugins_dir)
            return custom_plugins_dir.tr("\\", "/")
          end

          if defined?(Sketchup) && Sketchup.respond_to?(:find_support_file)
            su_plugins = Sketchup.find_support_file("Plugins")
            return su_plugins.tr("\\", "/") if su_plugins && Dir.exist?(su_plugins)
          end

          appdata = ENV["APPDATA"] || "C:/Users/#{ENV['USERNAME']}/AppData/Roaming"
          su_ver = defined?(Sketchup) && Sketchup.respond_to?(:version) ? Sketchup.version.to_i : 2026
          su_ver = 2026 if su_ver.zero?

          default_path = File.join(appdata, "SketchUp", "SketchUp #{su_ver}", "SketchUp", "Plugins").tr("\\", "/")
          FileUtils.mkdir_p(default_path) unless Dir.exist?(default_path)
          default_path
        end

        # Копирует файлы плагина из dev-папки в каталог Plugins
        # @param dev_dir [String, nil]
        # @param plugins_dir [String, nil]
        # @return [Hash]
        def update!(dev_dir = nil, plugins_dir = nil)
          src_dir = resolve_dev_dir(dev_dir)
          unless src_dir && Dir.exist?(src_dir)
            return {
              success: false,
              error: "Каталог разработки не найден. Укажите путь к папке с dn1c_export_pdf2.rb (проверено: #{dev_dir || DEFAULT_DEV_DIR})"
            }
          end

          dst_plugins = resolve_plugins_dir(plugins_dir)
          unless dst_plugins && Dir.exist?(dst_plugins)
            return {
              success: false,
              error: "Каталог Plugins SketchUp не найден: #{dst_plugins}"
            }
          end

          # Проверка на одинаковый каталог (чтобы не копировать самого себя)
          src_clean = File.expand_path(src_dir).tr("\\", "/").downcase
          dst_ext = File.expand_path(File.join(dst_plugins, "dn1c_export_pdf2")).tr("\\", "/").downcase
          if src_clean == dst_ext || src_clean == File.expand_path(dst_plugins).tr("\\", "/").downcase
            return {
              success: true,
              same_dir: true,
              dev_dir: src_dir,
              plugins_dir: dst_plugins,
              files_copied: 0,
              version: PLUGIN_VERSION,
              message: "Плагин уже работает напрямую из каталога разработки"
            }
          end

          files_copied = 0

          # 1. Копируем главный загрузчик dn1c_export_pdf2.rb
          root_loader = File.join(src_dir, "dn1c_export_pdf2.rb")
          if File.exist?(root_loader)
            target_loader = File.join(dst_plugins, "dn1c_export_pdf2.rb")
            FileUtils.cp(root_loader, target_loader)
            files_copied += 1
          end

          # 2. Копируем директорию пакета dn1c_export_pdf2/
          src_pkg = File.join(src_dir, "dn1c_export_pdf2")
          dst_pkg = File.join(dst_plugins, "dn1c_export_pdf2")
          FileUtils.mkdir_p(dst_pkg)

          Dir.glob(File.join(src_pkg, "**", "*"), File::FNM_DOTMATCH).each do |entry|
            rel = entry.sub("#{src_pkg}/", "")
            next if rel == "." || rel == ".."
            next if EXCLUDE_PATTERNS.any? { |pat| rel =~ pat }

            dest_entry = File.join(dst_pkg, rel)
            if File.directory?(entry)
              FileUtils.mkdir_p(dest_entry)
            else
              FileUtils.mkdir_p(File.dirname(dest_entry))
              FileUtils.cp(entry, dest_entry)
              files_copied += 1
            end
          end

          {
            success: true,
            same_dir: false,
            dev_dir: src_dir,
            plugins_dir: dst_plugins,
            files_copied: files_copied,
            version: PLUGIN_VERSION,
            updated_at: Time.now.strftime("%Y-%m-%d %H:%M:%S")
          }
        rescue StandardError => e
          {
            success: false,
            error: "#{e.class}: #{e.message}"
          }
        end

        # Перезагружает плагин в памяти SketchUp
        # @param plugins_dir [String, nil]
        # @return [Hash]
        def reload!(plugins_dir = nil)
          target_plugins = resolve_plugins_dir(plugins_dir)

          # Очистка $LOADED_FEATURES для файлов нашего плагина
          purged = 0
          if defined?($LOADED_FEATURES)
            $LOADED_FEATURES.reject! do |path|
              match = path.include?("dn1c_export_pdf2")
              purged += 1 if match
              match
            end
          end

          # Перезагрузка
          loader = File.join(target_plugins, "dn1c_export_pdf2.rb")
          main_rb = File.join(target_plugins, "dn1c_export_pdf2", "main.rb")

          load loader if File.exist?(loader)
          load main_rb if File.exist?(main_rb)

          # main.rb регистрирует наблюдателей только при первичной загрузке
          # (unless file_loaded?) — при горячей перезагрузке повторяем регистрацию
          # вручную (register! идемпотентен: дедупликация по WeakRef)
          Service::ObserverService.register! if defined?(Service::ObserverService)

          # Обновление открытого диалога, если есть
          if defined?(Dialog::ExportDialog)
            Dialog::ExportDialog.refresh_if_open rescue nil
          end

          {
            success: true,
            purged_features: purged,
            reloaded_at: Time.now.strftime("%Y-%m-%d %H:%M:%S"),
            version: (defined?(PLUGIN_VERSION) ? PLUGIN_VERSION : "unknown")
          }
        rescue StandardError => e
          {
            success: false,
            error: "#{e.class}: #{e.message}"
          }
        end

        # Выполняет копирование из dev-папки и сразу перезагружает плагин
        # @param dev_dir [String, nil]
        # @param plugins_dir [String, nil]
        # @return [Hash]
        def update_and_reload!(dev_dir = nil, plugins_dir = nil)
          res = update!(dev_dir, plugins_dir)
          return res unless res[:success]

          reload_res = reload!(plugins_dir)
          res.merge(reload_res)
        end
      end
    end
  end
end
