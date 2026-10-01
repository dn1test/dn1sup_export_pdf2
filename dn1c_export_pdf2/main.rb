# frozen_string_literal: true

# -------------------------------------------------------------------------------
# Extension Entry Point: DN1C Export PDF 2
# -------------------------------------------------------------------------------

begin
  require "sketchup.rb"
rescue LoadError
  # Outside SketchUp environment (e.g. test runner)
end

# Загрузка версии
require_relative "version"

# Загрузка сервисов (генерация PDF через SketchUp LayOut Ruby API)
require_relative "service/observer_service"
require_relative "service/overlay_service"
require_relative "service/vips_service"
require_relative "service/snapshot_worker"
require_relative "service/stats_tracker"
require_relative "service/dev_updater"

# Загрузка моделей данных
require_relative "model/path_util"
require_relative "model/file_opener"
require_relative "model/model_articul_store"
require_relative "model/project_data"
require_relative "model/session_store"

# Загрузка контроллера экспорта
require_relative "controller/export_controller"

# Загрузка пользовательского интерфейса
require_relative "dialog/export_dialog"

# Пространство имен плагина DN1Code
module DN1Code
  # Основной модуль плагина DN1C Export PDF 2
  module ExportPdf2
    extend self

    # Открывает главное модальное/интерактивное окно настроек и экспорта в PDF
    # @return [void]
    def open_export_dialog
      Dialog::ExportDialog.show_dialog
    end

    # Переключает отображение рамки пропорций кадра через Sketchup::Overlay
    # @return [Boolean]
    def toggle_aspect_overlay
      model = defined?(Sketchup) && Sketchup.respond_to?(:active_model) ? Sketchup.active_model : nil
      new_state = Service::OverlayService.toggle(model)
      Model::SessionStore.update_frame_settings(model, { show_aspect_overlay: new_state }) if defined?(Model::SessionStore)
      new_state
    end

    # Выполняет быстрый экспорт активных сцен текущей модели SketchUp
    # с использованием сохраненных или стандартных параметров без открытия диалога
    # @return [void]
    def quick_export
      model = Sketchup.active_model
      unless model
        UI.messagebox("Нет активной модели SketchUp!", defined?(MB_OK) ? MB_OK : 0)
        return
      end

      project_data = Model::SessionStore.data(model)

      enabled = project_data.scenes.select(&:enabled)
      if enabled.empty?
        UI.messagebox("В модели не найдено активных сцен для экспорта. Откройте диалог для настройки сцен.", defined?(MB_OK) ? MB_OK : 0)
        open_export_dialog
        return
      end

      controller = Controller::ExportController.new(project_data, model)
      begin
        pdf_path = controller.export

        # Привязываем PDF этого экспорта к самой свежей записи истории изменений
        if project_data.respond_to?(:stamp_history_pdf_link!) && project_data.stamp_history_pdf_link!(pdf_path.to_s)
          Model::SessionStore.flush(model) if defined?(Model::SessionStore)
        end

        UI.messagebox("PDF успешно создан:\n#{pdf_path}", defined?(MB_OK) ? MB_OK : 0)
      rescue StandardError => e
        UI.messagebox("Ошибка экспорта PDF:\n#{e.message}", defined?(MB_OK) ? MB_OK : 0)
      end
    end

    # Выполняет обновление плагина из рабочей dev-папки в Plugins и перезагружает его
    # @param dev_dir [String, nil] опциональный путь к папке разработки
    # @return [Hash]
    def update_from_dev(dev_dir = nil)
      res = Service::DevUpdater.update_and_reload!(dev_dir)
      if res[:success]
        msg = "✅ #{NAME_EXTENSION} (v#{PLUGIN_VERSION}) успешно обновлен из dev-папки!\n\n" \
              "Скопировано файлов: #{res[:files_copied]}"
        if res[:warnings] && !res[:warnings].empty?
          msg += "\n\n⚠ Пропущены залоченные файлы (обновятся после перезапуска SketchUp):\n" \
                 "#{res[:warnings].join("\n")}"
        end
        UI.messagebox(msg, defined?(MB_OK) ? MB_OK : 0) if defined?(UI)
      else
        err = "❌ Ошибка обновления из dev-папки:\n#{res[:error]}"
        UI.messagebox(err, defined?(MB_OK) ? MB_OK : 0) if defined?(UI)
      end
      res
    end

    # Выполняет быструю горячую перезагрузку кода плагина в памяти SketchUp
    # @return [Hash]
    def hot_reload
      res = Service::DevUpdater.reload!
      if res[:success]
        UI.messagebox("⚡ Плагин #{NAME_EXTENSION} v#{PLUGIN_VERSION} перезагружен!", defined?(MB_OK) ? MB_OK : 0) if defined?(UI)
      else
        UI.messagebox("❌ Ошибка перезагрузки:\n#{res[:error]}", defined?(MB_OK) ? MB_OK : 0) if defined?(UI)
      end
      res
    end

    # Регистрация команд, меню, панели инструментов и наблюдателей SketchUp
    unless file_loaded?(__FILE__)
      # Регистрация наблюдателя сохранения и открытия моделей SketchUp
      Service::ObserverService.register!

      # Запуск трекера активной работы (статистика на вкладке «Статистика»)
      Service::StatsTracker.register!

      # Создание пункта меню в Plugins с версией в заголовке
      menu = UI.menu("Plugins")
      submenu = menu.add_submenu("#{NAME_EXTENSION} v#{PLUGIN_VERSION}")

      submenu.add_item("Экспорт сцен в PDF (Диалог)...") do
        open_export_dialog
      end

      submenu.add_item("Быстрый экспорт (Quick Export)") do
        quick_export
      end

      item_overlay = submenu.add_item("Рамка пропорций кадра (Overlay)") do
        toggle_aspect_overlay
      end
      submenu.set_validation_proc(item_overlay) do
        model = defined?(Sketchup) && Sketchup.respond_to?(:active_model) ? Sketchup.active_model : nil
        Service::OverlayService.overlay_active?(model) ? MF_CHECKED : MF_UNCHECKED
      end

      submenu.add_separator if submenu.respond_to?(:add_separator)
      submenu.add_item("🔄 Обновить из dev-папки...") do
        update_from_dev
      end
      submenu.add_item("⚡ Перезагрузить расширение (Hot Reload)") do
        hot_reload
      end

      # Создание панели инструментов
      toolbar = UI::Toolbar.new(NAME_EXTENSION)
      ico_dir = File.join(__dir__, "ico")

      # UI::Command требует растровые PNG-иконки (16px малая, 24px большая);
      # SVG оставлен как запасной вариант на случай отсутствия PNG
      icon_path = lambda do |base|
        small_png = File.join(ico_dir, "#{base}.png")
        large_png = File.join(ico_dir, "#{base}_large.png")
        [File.exist?(small_png) ? small_png : File.join(ico_dir, "#{base}.svg"),
         File.exist?(large_png) ? large_png : File.join(ico_dir, "#{base}.svg")]
      end

      # Команда 1: Открыть диалог экспорта
      cmd_dialog = UI::Command.new("Экспорт сцен в PDF") { open_export_dialog }
      cmd_dialog.tooltip = "Открыть панель экспорта сцен в PDF"
      cmd_dialog.status_bar_text = "Настройка метаданных, сцен и создание многостраничного PDF документа"
      cmd_dialog.small_icon, cmd_dialog.large_icon = icon_path.call("export_dialog")
      toolbar.add_item(cmd_dialog)

      # Команда 2: Быстрый экспорт
      cmd_quick = UI::Command.new("Быстрый экспорт PDF") { quick_export }
      cmd_quick.tooltip = "Быстрый экспорт PDF с текущими настройками"
      cmd_quick.status_bar_text = "Мгновенное создание PDF из активных сцен модели"
      cmd_quick.small_icon, cmd_quick.large_icon = icon_path.call("quick_export")
      toolbar.add_item(cmd_quick)

      # Команда 3: Рамка пропорций кадра (Overlay)
      cmd_overlay = UI::Command.new("Рамка пропорций кадра") { toggle_aspect_overlay }
      cmd_overlay.tooltip = "Показать/скрыть рамку пропорций кадра (Overlay)"
      cmd_overlay.status_bar_text = "Отображение границ кадра и пропорций страницы в окне SketchUp"
      cmd_overlay.small_icon, cmd_overlay.large_icon = icon_path.call("frame_overlay")
      cmd_overlay.set_validation_proc do
        model = defined?(Sketchup) && Sketchup.respond_to?(:active_model) ? Sketchup.active_model : nil
        Service::OverlayService.overlay_active?(model) ? MF_CHECKED : MF_UNCHECKED
      end
      toolbar.add_item(cmd_overlay)

      toolbar.restore
      file_loaded(__FILE__)
    end
  end
end
