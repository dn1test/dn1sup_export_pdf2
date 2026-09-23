# Фикс: PDF не открывается после экспорта (галка «открыть» включена)

## Причина
Открытие выполняется в `service/layout_builder.rb:244-249` через `UI.openURL(Model::PathUtil.file_url(path))`. Механизм ненадёжен на Windows: `UI.openURL` рассчитан на web-URL, а `file:///` с процент-кодированной кириллицей/пробелами (`U:\desktop\su_ai\Кухня проект ~ Тестовый_last.pdf` → `file:///U:/%D0%9A...%20...`) часто молча не открывается. Возвращаемое `true/false` не проверяется, поэтому сбой полностью беззвучен — ни ошибки, ни лога.

## Изменения

### 1. Новый файл `dn1c_export_pdf2/model/file_opener.rb`
Модуль `Model::FileOpener.open_path(path) → Boolean`:
- проверка `File.exist?` → при отсутствии пути `warn` + `false`;
- **основной механизм (Windows): `ShellExecuteW` по СЫРОМУ пути через `fiddle`** (SU2024+ = Ruby 3.x, `Win32API` отсутствует; fiddle есть). Кодировка UTF-16LE, глагол `open`, `SW_SHOWNORMAL`; успех = возврат > 32. Сырой путь — без всякого URL-кодирования, кириллица/`#`/пробелы работают нативно;
- **фолбэк**: `UI.openURL(PathUtil.file_url(path))` (macOS, отсутствие fiddle, сбой ShellExecute) — с проверкой возврата;
- любой сбой → `warn` (никогда не беззвучно);
- `launcher_override` (Proc) — тестовый перехватчик, чтобы тесты под system Ruby на Windows не запускали реальный ShellExecute.

Подключить `require_relative "model/file_opener"` в `main.rb` рядом с `model/path_util`.

### 2. `service/layout_builder.rb` (шаг 8, строки 244-249)
Заменить `UI.openURL(...)` на `Model::FileOpener.open_path(controller.last_pdf_path || pdf_path)`. При `false` — `warn` «PDF создан, но не открылся». Защитное чтение флага в стиле файла: `settings[:auto_open_pdf] || settings["auto_open_pdf"]`.

### 3. `dialog/export_dialog.rb`
Колбэки `openFolder` (строка 631) и `openFile` (строка 647) — тот же ненадёжный `UI.openURL`; перевести на `FileOpener` (messagebox «не найдено» остаётся).

### 4. Тесты (`test/`)
- `comprehensive_test.rb`: после `require` задать `FileOpener.launcher_override = ->(p) { puts "[FileOpener] #{p}"; true }`.
- Обновить тест 70 (строки 5964-6000): ожидать `[FileOpener] <путь _last>` вместо `[UI::openURL] file:///...`.
- Добавить unit-тесты `FileOpener`: несуществующий путь → `false` без вызова лаунчера; лаунчер вернул `false` → `open_path` = `false` (и экспорт при этом не падает — проверка в тесте экспорта).
- Тест `file_url` (6308+) не трогаем — `PathUtil` остаётся как фолбэк.

## Верификация
1. `ruby test/comprehensive_test.rb` — весь набор зелёный (мок-окружение, без GUI).
2. Живая проверка через sketchup-dev MCP: `ext_check` → `ext_install` + `ext_reload` в SketchUp 2026; в консоли проверить `require "fiddle"`, сгенерировать старый `file:///` URL для текущей модели (диагностика), затем `Model::FileOpener.open_path` на реальном PDF — файл должен открыться системной программой.
3. Контрольный экспорт из плагина с включённой галкой — PDF открывается автоматически.

Побочный эффект фикса: PDF откроется родной программой для .pdf (Acrobat/Sumatra/Edge), а не вкладкой браузера.