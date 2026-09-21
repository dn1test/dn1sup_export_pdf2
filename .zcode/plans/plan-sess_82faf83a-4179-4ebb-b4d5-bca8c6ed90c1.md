**Причина бага:** кнопка ↗ в истории вызывает Ruby-колбэк `openFile` (dialog/export_dialog.rb:596), который строит URL без кодирования: `UI.openURL("file:///" + путь)`. Символ `#` в пути (`HF#26092`, а также суффикс `_01#001` в каждом экспортированном PDF) трактуется как фрагмент URL — путь обрезается до `U:/desktop/su_ai/HF`, файл не открывается. При отсутствии файла колбэк молчит. Тот же баг в `openFolder` (:591), `openDirectoryPath` (:468) и автооткрытии `_last` PDF (service/layout_builder.rb:245).

**Изменения:**

1. **Новый файл `model/path_util.rb`** — модуль `DN1Code::ExportPdf2::Model::PathUtil`, метод `self.file_url(path)`: нормализация `\` → `/`, разбивка на сегменты, процент-кодирование каждого по RFC 3986 (`#`→`%23`, пробел→`%20`, `&`, `%`, кириллица → UTF-8 байты), склейка `file:///...`. Пустая строка → `nil`. Подключить require_relative в `main.rb` и `export_dialog.rb`.

2. **dialog/export_dialog.rb:**
   - `openFile`: открыть через `PathUtil.file_url`; при ненайденном файле — `UI.messagebox("Файл не найден на диске:\n...")` вместо молчания (как в `openDirectoryPath`).
   - `openFolder`: то же кодирование + сообщение при ненайденном пути.
   - `openDirectoryPath`: заменить сырой URL на `PathUtil.file_url(folder_abs)`.

3. **service/layout_builder.rb:245:** автооткрытие PDF через `PathUtil.file_url` (иначе ломается на артикулах с `#`).

4. **test/comprehensive_test.rb:** юнит-тест `PathUtil.file_url` — путь с `#`, обратные слэши, кириллица, пробелы, пустая строка → `nil`. Существующий тест 70 не ломается (`Chair_last.pdf` без спецсимволов).

**Проверка:** ext_check (синтаксис в Ruby 3.2 SketchUp) → ext_install + ext_reload в живой SketchUp → консольный вызов `Model::PathUtil.file_url` на пути пользователя и реальный клик ↗ по записи истории → прогон comprehensive_test внутри SketchUp.