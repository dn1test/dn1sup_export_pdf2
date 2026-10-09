# frozen_string_literal: true

# -------------------------------------------------------------------------------
# Локализация строк Ruby-стороны, видимых в GUI диалога: тосты (notify_js),
# messagebox, заголовки файловых пикеров, заголовок окна, сообщения прогресса
# экспорта. Язык читается из pdf_settings.language активной сессии
# (config/settings.yaml). Печатное содержимое PDF (подписи параметров,
# штампы, «Страница N | M») локализацией не затрагивается — документ
# формируется на русском независимо от языка интерфейса.
# -------------------------------------------------------------------------------

module DN1Code
  module ExportPdf2
    module Locale
      STRINGS = {
        ru: {
          dialog_title_suffix:     " — Экспорт сцен в PDF",
          create_folder_no_articul: "Артикул не передан — папка проекта не создана",
          create_folder_save_model: "Сначала сохраните модель SketchUp (Ctrl+S) — папка проекта создается рядом с рабочим файлом",
          create_folder_error:    "Ошибка создания папки проекта: {msg}",
          select_dir_title:       "Выберите рабочую папку проекта",
          open_folder_missing:    "Папка не найдена на диске:\n{path}",
          open_file_missing:      "Файл не найден на диске:\n{path}",
          open_skp_not_found:     "SKP-копия для этой правки не найдена:\n{path}",
          save_project_ok:        "Сохранено: YAML проекта ({yaml}) + настройки PDF и шаблоны расширения",
          save_status_ok:         "DN1Sup Export PDF: Данные сохранены ({yaml} + settings.yaml + layout.yaml)",
          save_articul_missing:   "Артикул не указан — данные проекта не сохранены. Создайте артикул и повторите сохранение.",
          save_no_path:           "Не удалось сохранить: сохраните модель SketchUp (Ctrl+S), чтобы появился путь для YAML",
          save_yaml_error:        "Ошибка сохранения YAML: {msg}",
          save_memory_label:      "в память",
          save_ok:                "Сохранено в YAML ({yaml}) + настройки расширения",
          save_error:             "Ошибка сохранения: {msg}",
          send_preparing:         "Подготовка снимков к отправке...",
          send_done:              "Подготовлено снимков: {n}. Отправка на сервер пока не реализована.",
          send_error:             "Ошибка подготовки отправки: {msg}",
          export_yaml_title:      "Экспортировать настройки в YAML",
          export_yaml_ok:         "YAML успешно сохранен",
          export_yaml_error:      "Ошибка: {msg}",
          import_yaml_title:      "Открыть файл YAML конфигурации",
          import_yaml_ok:         "Данные проекта импортированы в память из {file}. Запись на диск — кнопкой «Сохранить»",
          import_yaml_fail:       "Не удалось прочитать YAML файл: {file}",
          set_save_no_name:       "Набор не сохранен: укажите имя набора",
          set_saved:              "Набор шаблонов «{name}» сохранен",
          set_save_failed:        "Не удалось сохранить набор шаблонов",
          set_save_error:         "Ошибка сохранения набора: {msg}",
          set_loaded:             "Набор шаблонов «{name}» загружен",
          set_not_found:          "Набор шаблонов не найден: {name}",
          set_load_error:         "Ошибка загрузки набора: {msg}",
          set_deleted:            "Набор шаблонов «{name}» удален",
          set_delete_failed:      "Не удалось удалить набор шаблонов",
          set_delete_error:       "Ошибка удаления набора: {msg}",
          stadia_empty:           "Список стадий пуст — сохранять нечего",
          stadia_saved:           "Список стадий сохранён по умолчанию ({n} шт.)",
          stadia_save_failed:     "Не удалось сохранить список стадий по умолчанию",
          stadia_save_error:      "Ошибка сохранения стадий по умолчанию: {msg}",
          stats_reset:            "Статистика работы сброшена",
          stats_reset_error:      "Ошибка сброса статистики: {msg}",
          lb_layout_missing:      "LayOut Ruby API не доступен в текущей версии SketchUp.\nУбедитесь, что используется SketchUp Pro с установленным модулем LayOut.",
          lb_no_scenes:           "Не выбрано ни одной сцены для экспорта в LayOut / PDF!",
          lb_pdf_locked:          "Целевой PDF открыт в программе просмотра и заблокирован для записи:\n{path}\nЗакройте его и повторите экспорт.",
          lb_init:                "Инициализация документа LayOut...",
          lb_page:                "Построение страницы LayOut {cur}/{total}: {name}",
          lb_export_pdf:          "Экспорт документа LayOut в PDF...",
          lb_done:                "Экспорт через LayOut API успешно завершен!",
          ec_snapshot:            "{label}-снимок сцены {cur}/{total}: {name}"
        }.freeze,
        en: {
          dialog_title_suffix:     " — Export scenes to PDF",
          create_folder_no_articul: "Articul not passed — project folder not created",
          create_folder_save_model: "Save the SketchUp model first (Ctrl+S) — the project folder is created next to the working file",
          create_folder_error:    "Project folder creation error: {msg}",
          select_dir_title:       "Select the project working folder",
          open_folder_missing:    "Folder not found on disk:\n{path}",
          open_file_missing:      "File not found on disk:\n{path}",
          open_skp_not_found:     "SKP copy for this change not found:\n{path}",
          save_project_ok:        "Saved: project YAML ({yaml}) + PDF settings and extension templates",
          save_status_ok:         "DN1Sup Export PDF: Data saved ({yaml} + settings.yaml + layout.yaml)",
          save_articul_missing:   "Articul is not set — project data was not saved. Create the articul and save again.",
          save_no_path:           "Could not save: save the SketchUp model (Ctrl+S) so a path for the YAML appears",
          save_yaml_error:        "YAML save error: {msg}",
          save_memory_label:      "to memory",
          save_ok:                "Saved to YAML ({yaml}) + extension settings",
          save_error:             "Save error: {msg}",
          send_preparing:         "Preparing snapshots for sending...",
          send_done:              "Snapshots prepared: {n}. Sending to the server is not implemented yet.",
          send_error:             "Send preparation error: {msg}",
          export_yaml_title:      "Export settings to YAML",
          export_yaml_ok:         "YAML saved successfully",
          export_yaml_error:      "Error: {msg}",
          import_yaml_title:      "Open YAML configuration file",
          import_yaml_ok:         "Project data imported into memory from {file}. Write to disk with the “Save” button",
          import_yaml_fail:       "Failed to read the YAML file: {file}",
          set_save_no_name:       "Set not saved: specify the set name",
          set_saved:              "Template set “{name}” saved",
          set_save_failed:        "Failed to save the template set",
          set_save_error:         "Set save error: {msg}",
          set_loaded:             "Template set “{name}” loaded",
          set_not_found:          "Template set not found: {name}",
          set_load_error:         "Set load error: {msg}",
          set_deleted:            "Template set “{name}” deleted",
          set_delete_failed:      "Failed to delete the template set",
          set_delete_error:       "Set deletion error: {msg}",
          stadia_empty:           "The stage list is empty — nothing to save",
          stadia_saved:           "Stage list saved as default ({n} items)",
          stadia_save_failed:     "Failed to save the default stage list",
          stadia_save_error:      "Default stages save error: {msg}",
          stats_reset:            "Work statistics reset",
          stats_reset_error:      "Statistics reset error: {msg}",
          lb_layout_missing:      "LayOut Ruby API is not available in this SketchUp version.\nMake sure SketchUp Pro with the LayOut module installed is used.",
          lb_no_scenes:           "No scenes selected for LayOut / PDF export!",
          lb_pdf_locked:          "The target PDF is open in a viewer and locked for writing:\n{path}\nClose it and retry the export.",
          lb_init:                "Initializing LayOut document...",
          lb_page:                "Building LayOut page {cur}/{total}: {name}",
          lb_export_pdf:          "Exporting LayOut document to PDF...",
          lb_done:                "Export via LayOut API completed successfully!",
          ec_snapshot:            "{label} snapshot of scene {cur}/{total}: {name}"
        }.freeze
      }.freeze

      class << self
        # Текущий язык интерфейса: :ru (умолчание) / :en — из pdf_settings.language
        # активной сессии (settings.yaml, пишется селектом на вкладке «Настройки»)
        # @return [Symbol]
        def lang
          pd = nil
          if defined?(Model::SessionStore)
            model = (defined?(Sketchup) && Sketchup.respond_to?(:active_model)) ? Sketchup.active_model : nil
            pd = begin
              Model::SessionStore.data(model)
            rescue StandardError
              nil
            end
          end
          s = pd && pd.respond_to?(:pdf_settings) ? pd.pdf_settings[:language].to_s : ""
          s.downcase.strip == "en" ? :en : :ru
        end

        # Перевод по ключу с интерполяцией {param}; фолбэк — русский словарь,
        # затем сам ключ (пропущенная строка видна сразу)
        # @param key [Symbol]
        # @param params [Hash{Symbol => Object}]
        # @return [String]
        def t(key, params = {})
          dict = STRINGS[lang] || STRINGS[:ru]
          s = dict[key] || STRINGS[:ru][key]
          return key.to_s if s.nil?

          return s if params.empty?

          s.gsub(/\{(\w+)\}/) do
            val = params[Regexp.last_match(1).to_sym]
            val.nil? ? Regexp.last_match(0) : val.to_s
          end
        end
      end
    end
  end
end
