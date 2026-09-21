# Папка артикула: структурированное хранилище проекта

## Цель
При экспорте создавать (и наполнять) папку по имени артикула в настраиваемой базовой папке:

```
<Базовая папка>/                          # поле base_dir в паспорте проекта
  <Артикул>/                              # напр. "HF#20260921_120000"
    <Артикул>.yaml                        # 1. настройки проекта (канонический файл)
    pdf/                                  # 2. история PDF
      <Артикул>_01#001.pdf                #    версия#ревизия (формат "<NN>#<NNN>")
      <Артикул>_01#001.layout             #    (если save_layout_file)
    skp/                                  # 3. история SKP-копий
      <Артикул>_01#001.skp
    png/                                  # 4. последние сцены (перезаписывается)
      01_Обложка.png
      02_<сцена>.png ...
```

Если `base_dir` пуст — всё создаётся рядом с .skp (как сейчас, нулевая конфигурация). Если модель не сохранена — фолбэк во временную папку (текущее поведение).

Решения по ответам пользователя: базовая папка настраиваемая; PNG — только последние (перезапись при каждом экспорте); имена файлов `<Артикул>_01#001`; снимки — автоматически при каждом экспорте PDF.

## Изменения по файлам

### 1. `dn1c_export_pdf2/model/project_data.rb`
- `default_project`: добавить `base_dir: ""`. Секция `project:` в `save_to_yaml` (`prj_out`, ~строка 1726) — добавить `base_dir`; загрузка (`@project.merge!`) подхватит автоматически.
- Новые методы:
  - `self.articul_folder_name(project_info, model)` — `sanitize_filename(артикул)`, фолбэк: имя .skp, иначе `nil`.
  - `articul_dir_for_model(model)` — `<base_dir||dir модели>/<имя папки>` или `nil`.
  - `self.version_rev_suffix(project_info)` — `sprintf("%02d#%03d", version, revision)` → `"01#001"`.
- `yaml_path_for_model`: при заданном `base_dir` → `<артикул_папка>/<Артикул>.yaml`.
- `save_project_yaml`: при заданном `base_dir` писать канонический yaml в папку артикула **и** служебный якорь-копию рядом с .skp (по нему модель повторно находит проект после перезапуска SketchUp, т.к. `base_dir` хранится в самом yaml). Старая логика удаления якоря при смене артикула сохраняется; папка прежнего артикула не трогается (история).
- `load_auto` (`find_yaml_path_for_model` без изменений): после загрузки якоря рядом с .skp, если в нём `base_dir` + артикул непустые и существует `<base_dir>/<Артикул>/<Артикул>.yaml` — перезагрузить из канонического файла (он приоритетен).

### 2. `dn1c_export_pdf2/controller/export_controller.rb`
- `resolve_default_pdf_path` → `<артикул_папка>/pdf/<Артикул>_01#001.pdf` (при пустом артикуле — имя модели). `.layout` и авто-открытие унаследуются от pdf_path.
- `save_skp_backup` → `<артикул_папка>/skp/<Артикул>_01#001.skp` (вместо `<модель>_backup/`).
- Новый метод `export_scene_pngs(reusable: {}, &progress)`:
  - папка `<артикул_папка>/png`, `mkdir_p`, очистка старых `*.png` («только последние»);
  - опции из `pdf_settings`: `image_width`/`render_quality`/`page_size`, `antialias`, `image_format: "png"`, пропорции: `aspect_ratio` сцены → глобальная `image_aspect_ratio`/`custom_ratio_w/h` → 4:3 (та же логика, что в `render_image_block`);
  - для каждой включённой сцены: если в `reusable[имя сцены]` есть уже отрендеренный временный PNG (image-режим) — переместить его, иначе отрендерить через `RenderService.render_scene_temp` и перенести; имя `<NN>_<санитизированное имя сцены>.png` (NN = двузначный порядок).

### 3. `dn1c_export_pdf2/service/layout_builder.rb`
- В `render_image_block` после растрового рендера (~строка 865): запомнить путь в `ctx[:rendered_scene_images][scene_item.name]`.
- В `export` после успешного `doc.export` (между шагами 5 и 6): вызвать `controller.export_scene_pngs(reusable: ctx[:rendered_scene_images], &progress_block)` в `rescue` (warn) — сбой снимков не валит PDF-экспорт.

### 4. Диалог (`dialog/export_dialog.rb`, `dialog/html/index.html`, `dialog/html/app.js`)
- `index.html` (вкладка «Проект», рядом с полем артикула): поле «Базовая папка артикула» (`#inputBaseDir`) + кнопка обзора.
- `export_dialog.rb`: новый callback `selectBaseDir` (по образцу `selectDirectory`, возвращает путь в JS).
- `app.js`: `base_dir` в `collectFormData()` (project) и вывод значения в форму; `apply_payload!` подхватит через `@project.merge!`.

### 5. Тесты `dn1c_export_pdf2/test/comprehensive_test.rb`
- MockModel с временным .skp; `articul` + `base_dir` во временной базе. После `controller.export`:
  - структура `<base>/<Артикул>/` с yaml, `pdf/<Артикул>_01#001.pdf`, `skp/`, `png/` (кол-во = число включённых сцен, имена `<NN>_<сцена>.png`);
  - якорь-yaml рядом с .skp существует;
  - фолбэк: `base_dir` пуст → папки в каталоге модели.
- Прогон: `ruby test/comprehensive_test.rb` из папки плагина (работает вне SketchUp через `mock_sketchup.rb`).

## Не входит в объём
- Перенос/миграция существующих `<модель>_backup/` и старых PDF — не трогаем.
- `edit_history.yaml` остаётся рядом с .skp.
- История PNG по версиям — отклонена пользователем.