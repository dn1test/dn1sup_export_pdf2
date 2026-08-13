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

# Загрузка сервисов
require_relative "service/gem_loader"
require_relative "service/font_service"
require_relative "service/render_service"
require_relative "service/pdf_builder"
require_relative "service/layout_builder"
require_relative "service/observer_service"

# Загрузка моделей данных
require_relative "model/scene_item"
require_relative "model/project_data"

# Загрузка контроллеров страниц
require_relative "controller/page_base"
require_relative "controller/cover_page"
require_relative "controller/description_page"
require_relative "controller/explain_page"
require_relative "controller/visual_page"
require_relative "controller/general_page"
require_relative "controller/export_controller"

# Загрузка пользовательского интерфейса
require_relative "dialog/export_dialog"

module DN1Code
  module ExportPdf2
    extend self

    def open_export_dialog
      Dialog::ExportDialog.show_dialog
    end

    def quick_export
      model = Sketchup.active_model
      unless model
        UI.messagebox("Нет активной модели SketchUp!", MB_OK)
        return
      end

      project_data = Model::ProjectData.new
      project_data.load_auto(model)

      enabled = project_data.scenes.select { |s| s.enabled && s.page_type != :skip }
      if enabled.empty?
        UI.messagebox("В модели не найдено активных сцен для экспорта. Откройте диалог для настройки сцен.", MB_OK)
        open_export_dialog
        return
      end

      controller = Controller::ExportController.new(project_data, model)
      begin
        pdf_path = controller.export
        UI.messagebox("PDF успешно создан:\n#{pdf_path}", MB_OK)
      rescue StandardError => e
        UI.messagebox("Ошибка экспорта PDF:\n#{e.message}", MB_OK)
      end
    end

    # Регистрация команд, меню, панели инструментов и наблюдателей SketchUp
    unless file_loaded?(__FILE__)
      # Регистрация наблюдателя сохранения и открытия моделей SketchUp
      Service::ObserverService.register!

      # Создание пункта меню в Plugins
      menu = UI.menu("Plugins")
      submenu = menu.add_submenu(NAME_EXTENSION)

      submenu.add_item("Экспорт сцен в PDF (Диалог)...") do
        open_export_dialog
      end

      submenu.add_item("Быстрый экспорт (Quick Export)") do
        quick_export
      end

      # Создание панели инструментов
      toolbar = UI::Toolbar.new(NAME_EXTENSION)
      ico_dir = File.join(__dir__, "ico")

      # Команда 1: Открыть диалог экспорта
      cmd_dialog = UI::Command.new("Экспорт сцен в PDF") { open_export_dialog }
      cmd_dialog.tooltip = "Открыть панель экспорта сцен в PDF"
      cmd_dialog.status_bar_text = "Настройка метаданных, сцен и создание многостраничного PDF документа"
      cmd_dialog.small_icon = File.join(ico_dir, "export_dialog.svg")
      cmd_dialog.large_icon = File.join(ico_dir, "export_dialog.svg")
      toolbar.add_item(cmd_dialog)

      # Команда 2: Быстрый экспорт
      cmd_quick = UI::Command.new("Быстрый экспорт PDF") { quick_export }
      cmd_quick.tooltip = "Быстрый экспорт PDF с текущими настройками"
      cmd_quick.status_bar_text = "Мгновенное создание PDF из активных сцен модели"
      cmd_quick.small_icon = File.join(ico_dir, "quick_export.svg")
      cmd_quick.large_icon = File.join(ico_dir, "quick_export.svg")
      toolbar.add_item(cmd_quick)

      toolbar.restore
      file_loaded(__FILE__)
    end
  end
end
