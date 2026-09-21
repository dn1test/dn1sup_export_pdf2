# План: YAML проекта — в папку артикула, имя project.yaml, артикул обязателен

## Новое поведение

- **Файл данных проекта** всегда лежит внутри папки артикула и называется `project.yaml`:
  `<base_dir|папка .skp>/<Артикул>/project.yaml`. Якорная копия рядом с .skp больше не создаётся.
- **Сохранение без артикула запрещено.** В диалоге при отсутствии артикула показывается модалка
  с редактируемым полем (предзаполнено генератором CF#/HF#) и кнопками «Создать и сохранить» / «Отмена»
  (отмена = не сохранять). Открывается и перед кнопкой экспорта (до промпта ревизии).
  В сценариях без диалога (закрытие SketchUp, быстрый экспорт) YAML проекта просто не пишется;
  настройки расширения (settings.yaml/layout.yaml) сохраняются как раньше.
- **Обнаружение проекта при открытии .skp**: сканируются подпапки `<папка .skp>/*/project.yaml`
  (одна — загружаем; несколько — не выбираем автоматически, пользователь грузит через «Импорт YAML»).
  Старые файлы остаются читаемыми как фолбэк (якорь `<Артикул>.yaml` рядом с .skp, `<Артикул>/<Артикул>.yaml`).
- **Миграция при сохранении**: после записи `project.yaml` удаляются старые дубликаты, созданные
  самим плагином: якорь `<папка .skp>/<Артикул>.yaml` и старый канонический `<Артикул>/<Артикул>.yaml`.
  Общие файлы-шаблоны (`project_config.yaml`, `<имя модели>.yaml`) не трогаются. При смене артикула
  старый якорь удаляется как и раньше.
- **edit_history.yaml** читается из `<Артикул>/edit_history.yaml`, при отсутствии — фолбэк на старое
  место рядом с .skp (файл плагином только читается, не пишется).

## Изменения в коде

### 1. `dn1c_export_pdf2/model/project_data.rb`
- Константа `PROJECT_YAML_NAME = "project.yaml"`; `yaml_filename` → всегда `project.yaml`
  (`resolve_yaml_filename` оставить для legacy-имен при миграции/очистке).
- `yaml_path_for_model`: только `<articul_dir_for_model>/project.yaml`; без артикула → `nil`
  (это и есть запрет сохранения на уровне модели). `articul_dir_for_model` не менять —
  ExportController использует его фолбэки для путей PDF/SKP.
- `save_project_yaml`: guard на непустой артикул (после `sync_project_fields!`) → `false` без записи;
  запись только в `<Артикул>/project.yaml`; блок создания якоря удалить; очистка legacy-файлов
  (якорь текущего и предыдущего артикула, `<Артикул>/<Артикул>.yaml`).
- Новое обнаружение: скан `Dir.glob(<dir>/*/project.yaml)` (ровно один → загрузить);
  `find_yaml_path_for_model` остаётся legacy-фолбэком.
- `load_auto`: приоритет `<Артикул>/project.yaml` → `<Артикул>/<Артикул>.yaml` → legacy-якорь;
  edit_history из папки артикула с фолбэком (в т.ч. блок внутри `load_from_yaml` ~1749).
- Обновить комментарии-контракт в шапке класса (строки 14–18).

### 2. `dn1c_export_pdf2/dialog/html/index.html` + `app.js`
- Модалка `articulPromptModal` по образцу `revisionPromptModal`: поле `inputArticulPrompt`,
  кнопки `btnConfirmArticulSave` / `btnCancelArticulPrompt`, закрытие по Escape.
- `btnSaveYaml` (app.js:6551): если артикул пуст → модалка (предзаполнение через
  `generateArticulLocal(isCommercial)`), по подтверждению — записать артикул в поле и state,
  затем `callRuby("saveProjectYaml", ...)`. Отмена — ничего не сохранять.
- Кнопка экспорта (app.js:6430): проверка артикула до модалки ревизии, тот же промпт,
  после подтверждения — продолжить штатный сценарий экспорта.

### 3. Мелочи
- `export_dialog.rb` `exportYaml` (строка 622): имя по умолчанию в savepanel → `project.yaml`.
- `main.rb` быстрый экспорт — без изменений (flush сам пропустит YAML без артикула).
- `version.rb`: 2.0.0 → 2.1.0.

### 4. Тесты `dn1c_export_pdf2/test/comprehensive_test.rb`
- Обновить под новую схему: `test_yaml_filename_resolution`, `test_auto_yaml_save_on_sketchup_save`,
  `test_save_project_yaml_and_articul_rename`, `test_articul_folder_yaml_canonical_and_anchor`,
  `test_articul_folder_export_structure`, `test_last_pdf_copy_next_to_skp_and_history_link`,
  `test_priority_reading_yaml_primary_model_secondary`, `test_project_config_and_edit_history_structure`.
- Новые тесты: сохранение без артикула не пишет YAML (настройки пишутся); миграция — старые
  якорь и `<Артикул>.yaml` в папке удаляются после записи project.yaml, шаблоны не тронуты;
  обнаружение `*/project.yaml` (одна папка — грузится, несколько — нет); edit_history из папки
  артикула с фолбэком.

### 5. README.MD — обновить разделы о структуре хранения YAML.

## Проверка
- Прогнать headless-тесты: `ruby dn1c_export_pdf2/test/comprehensive_test.rb` (TestRunner.run_all).
- Синтаксическая проверка изменённых .rb под Ruby 3.2 SketchUp (ext_check при живом SketchUp, иначе `ruby -c`).