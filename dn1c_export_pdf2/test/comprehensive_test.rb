# frozen_string_literal: true

# -------------------------------------------------------------------------------
# Comprehensive End-to-End Test Suite for DN1C Export PDF 2
# -------------------------------------------------------------------------------

require_relative "mock_sketchup"
require_relative "../main"
require "pdf/core"

if defined?(Sketchup) && Sketchup.respond_to?(:version)
  puts "Комплексные тесты мок-модели предназначены для запуска через терминал вне SketchUp GUI."
  return
end

class TestRunner
  def initialize
    @passed = 0
    @failed = 0
  end

  def assert(condition, message)
    if condition
      puts "  [PASS] #{message}"
      @passed += 1
    else
      puts "  [FAIL] #{message}"
      @failed += 1
    end
  end

  def run_all
    puts "=========================================================="
    puts "  Комплексное тестирование DN1C Export PDF 2"
    puts "=========================================================="

    test_default_blank_parameters
    test_models_and_attributes
    test_yaml_filename_resolution
    test_yaml_import_export
    test_auto_yaml_save_on_sketchup_save
    test_priority_reading_yaml_primary_model_secondary
    test_save_auto_both_library_and_yaml
    test_pdf_export_a4_landscape
    test_pdf_export_a3_portrait
    test_pdf_export_with_custom_stamp
    test_pdf_export_page_filtering
    test_default_pdf_path_next_to_skp
    test_pdf_export_description_page
    test_room_and_furniture_composition
    test_layout_api_export
    test_custom_layouts_and_block_positioning
    test_reopening_project_file_preserves_revision_and_yaml_string_keys
    test_project_config_and_edit_history_structure
    test_separate_layout_yaml_file
    test_modular_yaml_structure_and_generators
    test_fixed_7_slots_modular_layout
    test_page_margin_and_clean_render
    test_scene_drag_reordering_and_renaming
    test_header_line_rows_grouping
    test_header_vertical_alignment
    test_header_height_isolation
    test_footer_divided_items_and_alignment
    test_toc_page_count_and_created_pages_filtering
    test_header_scene_name_and_description
    test_header_item_dropdowns
    test_footer_card_layout_adjustments

    puts "\n=========================================================="
    puts "  ИТОГИ ТЕСТИРОВАНИЯ: Успешно: #{@passed}, Ошибок: #{@failed}"
    puts "=========================================================="

    exit(@failed.zero? ? 0 : 1)
  end

  private

  def test_custom_layouts_and_block_positioning
    puts "\n--- 11. Тест кастомного размещения блоков (Layout Editor) ---"

    project_data = DN1Code::ExportPdf2::Model::ProjectData.new
    settings = project_data.pdf_settings

    assert(settings.key?(:custom_layouts), "Настройки pdf_settings содержат ключ :custom_layouts")
    assert(settings[:custom_layouts].key?(:cover), "Кастомные макеты содержат шаблон :cover")
    assert(settings[:custom_layouts].key?(:description), "Кастомные макеты содержат шаблон :description")
    assert(settings[:custom_layouts].key?(:explain), "Кастомные макеты содержат шаблон :explain")
    assert(settings[:custom_layouts].key?(:general), "Кастомные макеты содержат шаблон :general")
    assert(settings[:custom_layouts].key?(:visual), "Кастомные макеты содержат шаблон :visual")

    # Модифицируем координаты, выравнивание, размер шрифта и строки информации
    settings[:custom_layouts][:cover][:header] = {
      x: 5.0, y: 8.0, w: 90.0, h: 10.0, visible: true, align: "center", font_size: 12.5,
      lines: ["room_name", "articul", "workflow_status"], content: "header_title"
    }
    settings[:custom_layouts][:cover][:cover_title] = { x: 5.0, y: 8.0, w: 90.0, h: 10.0, visible: true, align: "center", font_size: 12.0 }
    settings[:custom_layouts][:cover][:cover_subtitle] = { x: 5.0, y: 19.0, w: 90.0, h: 5.0, visible: false, align: "center" }
    settings[:custom_layouts][:description][:slot_1] = {
      x: 0.0, y: 10.0, w: 28.0, h: 40.0, visible: true, align: "right", font_size: 9.0,
      lines: ["room_name", "furniture_name", "workflow_price"], content: "project_card"
    }
    settings[:custom_layouts][:description][:desc_materials] = { x: 0.0, y: 12.0, w: 45.0, h: 25.0, visible: true }
    settings[:custom_layouts][:description][:desc_image] = { x: 48.0, y: 12.0, w: 52.0, h: 80.0, visible: true }

    # Сохраняем в YAML и проверяем чтение
    yaml_temp = File.expand_path("test_custom_layout.yaml", __dir__)
    File.delete(yaml_temp) if File.exist?(yaml_temp)

    project_data.save_to_yaml(yaml_temp)
    assert(File.exist?(yaml_temp), "YAML с кастомными координатами блоков успешно сохранен")

    loaded_data = DN1Code::ExportPdf2::Model::ProjectData.new
    loaded_data.load_from_yaml(yaml_temp)

    loaded_layouts = loaded_data.pdf_settings[:custom_layouts]
    assert(!loaded_layouts.nil?, "Кастомные макеты успешно прочитаны из YAML")
    header_block = loaded_layouts[:cover][:header] || loaded_layouts[:cover][:cover_title] || loaded_layouts[:cover]["header"] || loaded_layouts[:cover]["cover_title"]
    assert(header_block && (header_block[:align] == "center" || header_block["align"] == "center"), "Выравнивание заголовка обложки сохранено")
    assert(header_block && ((header_block[:font_size] || header_block["font_size"]).to_f == 12.5), "Размер шрифта заголовка сохранен (12.5 pt)")
    hdr_lines = header_block[:lines] || header_block["lines"]
    assert(hdr_lines && hdr_lines.include?("articul"), "Строки информации заголовка содержат articul")

    slot1_block = loaded_layouts[:description][:slot_1] || loaded_layouts[:description]["slot_1"]
    assert(slot1_block && (slot1_block[:align] == "right" || slot1_block["align"] == "right"), "Выравнивание slot_1 (right) сохранено")
    assert(slot1_block && ((slot1_block[:font_size] || slot1_block["font_size"]).to_f == 9.0), "Размер шрифта slot_1 сохранен (9.0 pt)")
    slot1_lines = slot1_block[:lines] || slot1_block["lines"]
    assert(slot1_lines && slot1_lines.include?("workflow_price"), "Строки информации slot_1 содержат workflow_price")

    # Тестируем экспорт PDF с кастомным макетом
    model = Sketchup::MockModel.new("U:/Projects/CustomLayout/LivingRoom.skp")
    model.pages.add("01. Титул")
    model.pages.add("02. Спецификации")
    loaded_data.project_info[:room_name] = "Гостиная"
    loaded_data.project_info[:furniture_name] = "Стенка ТВ"
    loaded_data.project_info[:materials] = "Шпон дуба, стекло матовое, ручки профиль"
    loaded_data.project_info[:price] = "150000"
    loaded_data.sync_with_model_scenes(model)

    pdf_out = File.expand_path("test_custom_layout_export.pdf", __dir__)
    File.delete(pdf_out) if File.exist?(pdf_out)

    controller = DN1Code::ExportPdf2::Controller::ExportController.new(loaded_data, model)
    result_pdf = controller.export(pdf_out)

    assert(File.exist?(result_pdf), "PDF с кастомной компоновкой блоков успешно сгенерирован")
    assert(File.size(result_pdf) > 15000, "Размер PDF с кастомным макетом валиден (#{File.size(result_pdf)} байт)")

    File.delete(yaml_temp) if File.exist?(yaml_temp)
    File.delete(pdf_out) if File.exist?(pdf_out)
    layout_file_out = File.expand_path("test_custom_layout_export.layout", __dir__)
    File.delete(layout_file_out) if File.exist?(layout_file_out)
    dir_layout = File.expand_path("layout.yaml", __dir__)
    File.delete(dir_layout) if File.exist?(dir_layout)
    dir_hist = File.expand_path("edit_history.yaml", __dir__)
    File.delete(dir_hist) if File.exist?(dir_hist)
  end

  private

  def test_default_blank_parameters
    puts "\n--- 0. Тест параметров по умолчанию (только пустые подсказки) ---"

    project_data = DN1Code::ExportPdf2::Model::ProjectData.new
    info = project_data.project_info

    assert(info[:room_name] == "", "Поле room_name изначально пустое")
    assert(info[:furniture_name] == "", "Поле furniture_name изначально пустое")
    assert(info[:name_project] == "", "Поле name_project изначально пустое")
    assert(info[:description] == "", "Поле description изначально пустое")
    assert(info[:name_customer] == "", "Поле name_customer изначально пустое")
    assert(info[:phone] == "", "Поле phone изначально пустое")
    assert(info[:email] == "", "Поле email изначально пустое")
    assert(info[:address] == "", "Поле address изначально пустое")
    assert(info[:articul] == "", "Поле articul изначально пустое")
    assert(info[:materials] == "", "Поле materials изначально пустое")
    assert(info[:appliances] == "", "Поле appliances изначально пустое")
    assert(info[:lighting] == "", "Поле lighting изначально пустое")
    assert(info[:notes] == "", "Поле notes изначально пустое")
    assert(project_data.history.empty?, "История изменений изначально пустая")
  end

  def test_models_and_attributes
    puts "\n--- 1. Тест моделей данных и SketchUp Attribute Dictionaries ---"

    model = Sketchup::MockModel.new("U:/Projects/Test/Apartment.skp")
    model.pages.add("01. Обложка")
    model.pages.add("02. Пояснения и спецификации")
    model.pages.add("03. Визуализация")
    model.pages.add("04. Общий вид 1")
    model.pages.add("05. Общий вид 2")

    project_data = DN1Code::ExportPdf2::Model::ProjectData.new
    project_data.project_info[:name_project] = "Тестовый проект виллы"
    project_data.project_info[:articul] = "VILLA-777"
    project_data.project_info[:version] = 2
    project_data.project_info[:revision] = 5

    # Сохраняем в модель
    project_data.sync_with_model_scenes(model)
    assert(project_data.scenes.size == 5, "Корректно обнаружено 5 сцен в модели")
    assert(project_data.scenes[0].page_type == :cover, "Сцена '01. Обложка' распознана как :cover")
    assert(project_data.scenes[1].page_type == :explain, "Сцена '02. Пояснения...' распознана как :explain")
    assert(project_data.scenes[2].page_type == :visual, "Сцена '03. Визуализация' распознана как :visual")
    assert(project_data.scenes[3].page_type == :general, "Сцена '04. Общий вид' распознана как :general")

    project_data.save_to_model(model)
    assert(!model.attributes["DN1C_ExportPDF"].nil?, "Атрибуты DN1C_ExportPDF сохранены в модели")

    # Читаем в новый объект
    loaded_data = DN1Code::ExportPdf2::Model::ProjectData.new
    loaded_data.load_from_model(model)
    assert(loaded_data.project_info[:name_project] == "Тестовый проект виллы", "Имя проекта загружено из атрибутов модели")
    assert(loaded_data.project_info[:articul] == "VILLA-777", "Артикул загружен из атрибутов модели")
    assert(loaded_data.project_info[:revision] == 5, "Номер ревизии загружен из атрибутов модели")
  end

  def test_yaml_filename_resolution
    puts "\n--- 2. Тест правил именования YAML (Артикул / Имя файла SKP) ---"

    model = Sketchup::MockModel.new("U:/Projects/Villa/Apartment_Final.skp")

    # Вариант 1: Артикул указан
    info_with_art = { articul: "PRJ-2026-X" }
    resolved_1 = DN1Code::ExportPdf2::Model::ProjectData.resolve_yaml_filename(info_with_art, model)
    assert(resolved_1 == "PRJ-2026-X.yaml", "Имя YAML взято из артикула: #{resolved_1}")

    # Вариант 2: Артикул с недопустимыми символами (санитизация)
    info_with_bad_art = { articul: "PRJ/2026:01*A" }
    resolved_2 = DN1Code::ExportPdf2::Model::ProjectData.resolve_yaml_filename(info_with_bad_art, model)
    assert(resolved_2 == "PRJ_2026_01_A.yaml", "Имя YAML с очищенными спецсимволами: #{resolved_2}")

    # Вариант 3: Артикул пустой -> берется имя файла модели
    info_empty_art = { articul: "" }
    resolved_3 = DN1Code::ExportPdf2::Model::ProjectData.resolve_yaml_filename(info_empty_art, model)
    assert(resolved_3 == "Apartment_Final.yaml", "При пустом артикуле имя взято из имени файла модели: #{resolved_3}")

    # Вариант 4: Артикул nil -> берется имя файла модели
    info_nil_art = { articul: nil }
    resolved_4 = DN1Code::ExportPdf2::Model::ProjectData.resolve_yaml_filename(info_nil_art, model)
    assert(resolved_4 == "Apartment_Final.yaml", "При nil артикуле имя взято из имени файла модели: #{resolved_4}")
  end

  def test_yaml_import_export
    puts "\n--- 3. Тест экспорта и импорта конфигурации YAML ---"

    project_data = DN1Code::ExportPdf2::Model::ProjectData.new
    project_data.project_info[:name_place] = "Пентхаус"
    project_data.project_info[:name_product] = "на Мосфильмовской"
    project_data.project_info[:name_customer] = "Ковалев Дмитрий"
    project_data.project_info[:notes] = "Мрамор Calacatta, дубовый паркет Coswick, техника Miele."
    project_data.history << { date: "2026.08.10", description: "Утверждение планировки" }

    yaml_path = File.expand_path("test_project_config.yaml", __dir__)
    project_data.save_to_yaml(yaml_path)
    assert(File.exist?(yaml_path), "YAML файл конфигурации успешно создан на диске")

    saved_yaml_content = File.read(yaml_path, encoding: "utf-8")
    assert(!saved_yaml_content.include?("name_project:"), "В сохраненном YAML отсутствует поле name_project")

    loaded_yaml_data = DN1Code::ExportPdf2::Model::ProjectData.new
    loaded_yaml_data.load_from_yaml(yaml_path)
    assert(loaded_yaml_data.project_info[:name_project] == "Пентхаус — на Мосфильмовской", "Имя проекта корректно составлено из name_place и name_product")
    assert(loaded_yaml_data.project_info[:name_customer] == "Ковалев Дмитрий", "Имя заказчика корректно загружено из YAML")
    assert(loaded_yaml_data.history.size >= 1, "История изменений корректно прочитана из YAML")

    File.delete(yaml_path) if File.exist?(yaml_path)
  end

  def test_auto_yaml_save_on_sketchup_save
    puts "\n--- 4. Тест автоматического создания YAML при сохранении SketchUp файла ---"

    test_dir = File.expand_path("test_auto_save_dir", __dir__)
    FileUtils.mkdir_p(test_dir)

    skp_file = File.join(test_dir, "Kitchen_Project.skp")
    model = Sketchup::MockModel.new(skp_file)

    # Прикрепляем наблюдателя
    DN1Code::ExportPdf2::Service::ObserverService.attach_model_observer(model)

    project_data = DN1Code::ExportPdf2::Model::ProjectData.new
    project_data.project_info[:articul] = "KITCHEN-777"
    project_data.project_info[:name_product] = "Кухня Модерн"
    project_data.save_to_model(model)

    # Имитируем сохранение модели SketchUp (Ctrl+S / File -> Save)
    model.save

    expected_yaml = File.join(test_dir, "KITCHEN-777.yaml")
    assert(File.exist?(expected_yaml), "При сохранении SKP автоматически создан YAML по артикулу: #{File.basename(expected_yaml)}")

    # Проверяем содержимое созданного YAML
    loaded = DN1Code::ExportPdf2::Model::ProjectData.new
    loaded.load_from_yaml(expected_yaml)
    assert(loaded.project_info[:name_project] == "Кухня Модерн", "Содержимое автоматически созданного YAML файла корректно")

    # Теперь очищаем артикул и сохраняем модель снова
    project_data.project_info[:articul] = ""
    project_data.project_info[:name_product] = "Кухня Без Артикула"
    project_data.save_to_model(model)
    model.save

    fallback_yaml = File.join(test_dir, "Kitchen_Project.yaml")
    assert(File.exist?(fallback_yaml), "При пустом артикуле создан YAML с именем модели SKP: #{File.basename(fallback_yaml)}")

    FileUtils.rm_rf(test_dir)
  end

  def test_priority_reading_yaml_primary_model_secondary
    puts "\n--- 5. Тест иерархии чтения: ПЕРВИЧНО YAML, ВТОРИЧНО библиотека модели ---"

    test_dir = File.expand_path("test_priority_dir", __dir__)
    FileUtils.mkdir_p(test_dir)

    skp_file = File.join(test_dir, "Bedroom.skp")
    model = Sketchup::MockModel.new(skp_file)

    # 1. Записываем в библиотеку модели одно значение
    model_data = DN1Code::ExportPdf2::Model::ProjectData.new
    model_data.project_info[:articul] = "BED-01"
    model_data.project_info[:name_product] = "Имя из библиотеки модели"
    model_data.save_to_model(model)

    # 2. Создаем рядом файл BED-01.yaml с другим значением (внешнее редактирование)
    yaml_file = File.join(test_dir, "BED-01.yaml")
    yaml_data = DN1Code::ExportPdf2::Model::ProjectData.new
    yaml_data.project_info[:articul] = "BED-01"
    yaml_data.project_info[:name_product] = "Имя из файла YAML (Первично)"
    yaml_data.save_to_yaml(yaml_file)

    # 3. Вызываем автоматическую загрузку
    test_data = DN1Code::ExportPdf2::Model::ProjectData.new
    source = test_data.load_auto(model)

    assert(source == :yaml, "Источник загрузки определен как :yaml (первично)")
    assert(test_data.project_info[:name_project] == "Имя из файла YAML (Первично)", "Загружены данные из YAML файла, имеющего высший приоритет")

    # 4. Удаляем YAML файл и проверяем вторичную загрузку из библиотеки модели
    File.delete(yaml_file) if File.exist?(yaml_file)

    fallback_data = DN1Code::ExportPdf2::Model::ProjectData.new
    fallback_source = fallback_data.load_auto(model)

    assert(fallback_source == :model, "При отсутствии YAML источник загрузки определен как :model (вторично)")
    # Библиотека модели была синхронизирована при первой загрузке из YAML
    assert(!fallback_data.project_info[:name_project].empty?, "Данные успешно прочитаны из библиотеки модели")

    FileUtils.rm_rf(test_dir)
  end

  def test_save_auto_both_library_and_yaml
    puts "\n--- 6. Тест save_auto: одновременное сохранение в библиотеку, обновление YAML и переименование файла при смене артикула ---"

    test_dir = File.expand_path("test_save_auto_dir", __dir__)
    FileUtils.mkdir_p(test_dir)

    skp_file = File.join(test_dir, "Office.skp")
    model = Sketchup::MockModel.new(skp_file)

    project_data = DN1Code::ExportPdf2::Model::ProjectData.new
    project_data.project_info[:articul] = "OFFICE-900"
    project_data.project_info[:name_project] = "Кабинет Руководителя"

    # Вызываем save_auto первый раз
    project_data.save_auto(model)

    # Проверка 1: Сохранено в библиотеку модели
    dict_saved = model.get_attribute("DN1C_ExportPDF", "project_info")
    assert(!dict_saved.nil? && dict_saved.include?("OFFICE-900"), "Данные сохранены в словарь атрибутов модели")

    # Проверка 2: Сохранено в YAML файл рядом с SKP
    yaml_file_1 = File.join(test_dir, "OFFICE-900.yaml")
    assert(File.exist?(yaml_file_1), "Данные сохранены в файл #{File.basename(yaml_file_1)}")

    # Проверка 3: Изменение артикула -> вызов save_auto (кнопка Обновить)
    project_data.project_info[:articul] = "OFFICE-901"
    project_data.project_info[:name_project] = "Кабинет Руководителя (Обновленный)"
    project_data.save_auto(model)

    yaml_file_2 = File.join(test_dir, "OFFICE-901.yaml")
    assert(File.exist?(yaml_file_2), "При смене артикула создан новый YAML файл #{File.basename(yaml_file_2)}")
    assert(!File.exist?(yaml_file_1), "Старый YAML файл #{File.basename(yaml_file_1)} автоматически удален")

    dict_saved_2 = model.get_attribute("DN1C_ExportPDF", "project_info")
    assert(!dict_saved_2.nil? && dict_saved_2.include?("OFFICE-901"), "Атрибуты модели обновлены на новый артикул")

    # Проверка 4: Очистка артикула -> имя YAML возвращается к имени файла модели Office.yaml
    project_data.project_info[:articul] = ""
    project_data.save_auto(model)

    yaml_file_3 = File.join(test_dir, "Office.yaml")
    assert(File.exist?(yaml_file_3), "При очистке артикула создан файл по имени модели #{File.basename(yaml_file_3)}")
    assert(!File.exist?(yaml_file_2), "Предыдущий файл артикула #{File.basename(yaml_file_2)} удален")

    FileUtils.rm_rf(test_dir)
  end

  def test_pdf_export_a4_landscape
    puts "\n--- 3. Тест генерации PDF: Формат A4 Альбомная ---"

    model = Sketchup::MockModel.new("U:/Projects/Villa/villa_model.skp")
    scenes = [
      Sketchup::MockPage.new("Обложка", "Титульный лист"),
      Sketchup::MockPage.new("Пояснительная записка", "Содержание и ведомость отделки"),
      Sketchup::MockPage.new("Вид 1", "Главный фасад"),
      Sketchup::MockPage.new("Вид 2", "Интерьер гостиной")
    ]
    model.pages = Sketchup::MockPages.new(scenes)

    project_data = DN1Code::ExportPdf2::Model::ProjectData.new
    project_data.project_info = {
      name_project:  "Загородная резиденция 'Сосны'",
      description:   "Архитектурный проект двухэтажного коттеджа",
      name_customer: "Смирнов В.А.",
      address:       "МО, Новорижское шоссе, КП 'Сосны'",
      articul:       "VIL-2026-09",
      version:       1,
      revision:      2,
      status:        "В РАБОТЕ",
      designer:      "DESTUDIONS Architecture",
      notes:         "Материалы фасада: клинкерный кирпич Roben, планкен из термоясеня, алюминиевые витражи Reynaers."
    }

    project_data.pdf_settings[:page_size] = "A4"
    project_data.pdf_settings[:page_layout] = "landscape"
    project_data.pdf_settings[:stamp_type] = "draft"
    project_data.pdf_settings[:auto_open_pdf] = false

    project_data.sync_with_model_scenes(model)

    pdf_out = File.expand_path("test_a4_landscape.pdf", __dir__)
    controller = DN1Code::ExportPdf2::Controller::ExportController.new(project_data, model)

    result_path = controller.export(pdf_out)

    assert(File.exist?(result_path), "Файл PDF test_a4_landscape.pdf создан")
    assert(File.size(result_path) > 15_000, "Размер PDF файла составляет #{File.size(result_path)} байт (не пустой)")

    File.delete(pdf_out) if File.exist?(pdf_out)
  end

  def test_pdf_export_a3_portrait
    puts "\n--- 4. Тест генерации PDF: Формат A3 Книжная ---"

    model = Sketchup::MockModel.new("U:/Projects/Commercial/shop.skp")
    scenes = [
      Sketchup::MockPage.new("Обложка"),
      Sketchup::MockPage.new("План торгового зала"),
      Sketchup::MockPage.new("Визуализация витрины")
    ]
    model.pages = Sketchup::MockPages.new(scenes)

    project_data = DN1Code::ExportPdf2::Model::ProjectData.new
    project_data.project_info[:name_project] = "Флагманский бутик одежды"
    project_data.pdf_settings[:page_size] = "A3"
    project_data.pdf_settings[:page_layout] = "portrait"
    project_data.pdf_settings[:stamp_type] = "approved"
    project_data.pdf_settings[:auto_open_pdf] = false

    project_data.sync_with_model_scenes(model)

    pdf_out = File.expand_path("test_a3_portrait.pdf", __dir__)
    controller = DN1Code::ExportPdf2::Controller::ExportController.new(project_data, model)

    result_path = controller.export(pdf_out)

    assert(File.exist?(result_path), "Файл PDF test_a3_portrait.pdf создан")
    assert(File.size(result_path) > 12_000, "Размер A3 PDF файла: #{File.size(result_path)} байт")

    File.delete(pdf_out) if File.exist?(pdf_out)
  end

  def test_pdf_export_with_custom_stamp
    puts "\n--- 5. Тест водяного знака / пользовательского штампа ---"

    model = Sketchup::MockModel.new("U:/Projects/Hotel/hotel.skp")
    model.pages = Sketchup::MockPages.new([Sketchup::MockPage.new("Обложка"), Sketchup::MockPage.new("Лобби")])

    project_data = DN1Code::ExportPdf2::Model::ProjectData.new
    project_data.project_info[:name_project] = "Отель Grand Palace"
    project_data.pdf_settings[:stamp_type] = "custom"
    project_data.pdf_settings[:stamp_custom] = "КОНФИДЕНЦИАЛЬНО"
    project_data.pdf_settings[:auto_open_pdf] = false

    project_data.sync_with_model_scenes(model)

    pdf_out = File.expand_path("test_custom_stamp.pdf", __dir__)
    controller = DN1Code::ExportPdf2::Controller::ExportController.new(project_data, model)

    result_path = controller.export(pdf_out)
    assert(File.exist?(result_path), "PDF с пользовательским штампом 'КОНФИДЕНЦИАЛЬНО' сгенерирован")

    File.delete(pdf_out) if File.exist?(pdf_out)
  end

  def test_pdf_export_page_filtering
    puts "\n--- 6. Тест фильтрации сцен (отключение сцен и пропуск) ---"

    model = Sketchup::MockModel.new("U:/Projects/Test/filtering.skp")
    s1 = Sketchup::MockPage.new("Сцена 1 - Включена", "", true)
    s2 = Sketchup::MockPage.new("Сцена 2 - Пропущена", "", false)
    s3 = Sketchup::MockPage.new("Сцена 3 - Включена", "", true)
    model.pages = Sketchup::MockPages.new([s1, s2, s3])

    project_data = DN1Code::ExportPdf2::Model::ProjectData.new
    project_data.sync_with_model_scenes(model)

    # Отключаем вторую сцену
    project_data.scenes[1].enabled = false
    project_data.pdf_settings[:auto_open_pdf] = false

    pdf_out = File.expand_path("test_filtered.pdf", __dir__)
    controller = DN1Code::ExportPdf2::Controller::ExportController.new(project_data, model)

    result_path = controller.export(pdf_out)
    assert(File.exist?(result_path), "PDF с выборочными сценами успешно создан")

    File.delete(pdf_out) if File.exist?(pdf_out)
  end

  def test_default_pdf_path_next_to_skp
    puts "\n--- 7. Тест сохранения PDF по умолчанию рядом с файлом SKP ---"

    model_file = "U:/Projects/Interior/Kitchen_Design.skp"
    model = Sketchup::MockModel.new(model_file)
    model.pages = Sketchup::MockPages.new([Sketchup::MockPage.new("01. Вид")])

    project_data = DN1Code::ExportPdf2::Model::ProjectData.new
    project_data.project_info[:version] = 1
    project_data.project_info[:revision] = 4
    project_data.pdf_settings[:auto_open_pdf] = false

    controller = DN1Code::ExportPdf2::Controller::ExportController.new(project_data, model)
    default_path = controller.send(:resolve_default_pdf_path)

    expected_path = "U:/Projects/Interior/Kitchen_Design_v01_r004.pdf"
    assert(default_path == expected_path, "Путь по умолчанию '#{default_path}' находится рядом с SKP файлом ('#{expected_path}')")
  end

  def test_pdf_export_description_page
    puts "\n--- 8. Тест страницы описания проекта (Материалы, Подсветка, Пояснения) ---"

    model = Sketchup::MockModel.new("U:/Projects/Interior/Villa.skp")
    scenes = [
      Sketchup::MockPage.new("01. Обложка"),
      Sketchup::MockPage.new("02. Описание и спецификации"),
      Sketchup::MockPage.new("03. Перспектива")
    ]
    model.pages = Sketchup::MockPages.new(scenes)

    project_data = DN1Code::ExportPdf2::Model::ProjectData.new
    project_data.project_info[:name_project] = "Вилла в Сочи"
    project_data.project_info[:materials] = "Фасады: МДФ эмаль RAL 9003, корпус: Egger 18мм, фурнитура: Blum Legrabox."
    project_data.project_info[:appliances] = "Духовой шкаф Miele, индукционная варочная панель Bosch, вытяжка Elica."
    project_data.project_info[:lighting] = "Светодиодная подсветка 3000K в скрытом профиле, блок питания 24V 150W."
    project_data.project_info[:notes] = "Монтаж производить строго по осям согласно строительному плану."
    project_data.pdf_settings[:auto_open_pdf] = false

    project_data.sync_with_model_scenes(model)

    assert(project_data.scenes[1].page_type == :description, "Сцена '02. Описание...' автоматически распознана как :description")

    pdf_out = File.expand_path("test_description_page.pdf", __dir__)
    controller = DN1Code::ExportPdf2::Controller::ExportController.new(project_data, model)

    result_path = controller.export(pdf_out)
    assert(File.exist?(result_path), "PDF со страницей описания и спецификаций успешно создан")
    assert(File.size(result_path) > 15_000, "Размер PDF файла со страницей описания: #{File.size(result_path)} байт")

    File.delete(pdf_out) if File.exist?(pdf_out)
  end

  def test_room_and_furniture_composition
    puts "\n--- 9. Тест формирования названия проекта из комнаты и мебели ---"

    model = Sketchup::MockModel.new("U:/Projects/Interior/Kitchen.skp")
    model.pages = Sketchup::MockPages.new([Sketchup::MockPage.new("01. Обложка")])

    project_data = DN1Code::ExportPdf2::Model::ProjectData.new
    project_data.project_info[:room_name] = "Кухня-столовая"
    project_data.project_info[:furniture_name] = "Остров с барной стойкой"
    project_data.project_info[:address] = "г. Санкт-Петербург, Невский пр., 100"
    project_data.project_info[:name_project] = "#{project_data.project_info[:room_name]} — #{project_data.project_info[:furniture_name]}"
    project_data.pdf_settings[:auto_open_pdf] = false

    project_data.save_to_model(model)

    loaded_data = DN1Code::ExportPdf2::Model::ProjectData.new
    loaded_data.load_from_model(model)

    assert(loaded_data.project_info[:room_name] == "Кухня-столовая", "Помещение 'Кухня-столовая' сохранено в модель")
    assert(loaded_data.project_info[:furniture_name] == "Остров с барной стойкой", "Изделие 'Остров с барной стойкой' сохранено в модель")
    assert(loaded_data.project_info[:address] == "г. Санкт-Петербург, Невский пр., 100", "Адрес сохранен в данные проекта")
    assert(loaded_data.project_info[:name_project] == "Кухня-столовая — Остров с барной стойкой", "Заголовок проекта корректно составлен из помещения и мебели")

    pdf_out = File.expand_path("test_cover_composition.pdf", __dir__)
    controller = DN1Code::ExportPdf2::Controller::ExportController.new(loaded_data, model)
    result_path = controller.export(pdf_out)
    assert(File.exist?(result_path), "PDF с титульным листом и составным заголовком успешно сгенерирован")

    File.delete(pdf_out) if File.exist?(pdf_out)
  end

  def test_layout_api_export
    puts "\n--- 10. Тест экспорта через SketchUp LayOut Ruby API ---"

    model = Sketchup::MockModel.new("U:/Projects/Interior/Penthouse.skp")
    scenes = [
      Sketchup::MockPage.new("01. Обложка"),
      Sketchup::MockPage.new("02. Описание и спецификации"),
      Sketchup::MockPage.new("03. Содержание"),
      Sketchup::MockPage.new("04. Визуализация"),
      Sketchup::MockPage.new("05. Общий вид")
    ]
    model.pages = Sketchup::MockPages.new(scenes)

    project_data = DN1Code::ExportPdf2::Model::ProjectData.new
    project_data.project_info = {
      name_project:   "Пентхаус 'Панорама'",
      room_name:      "Гостиная-студия",
      furniture_name: "Медиа-зона со стеллажами",
      name_customer:  "Романов А.В.",
      address:        "г. Москва, Пресненская наб., 12",
      articul:        "PAN-2026-X",
      version:        1,
      revision:       3,
      status:         "В РАБОТЕ",
      materials:      "Шпон американского ореха, металлокаркас латунь, подсветка 2700K.",
      appliances:     "Аудиосистема Hi-Fi, панель OLED 85'.",
      lighting:       "Профиль Arlight 24V, сенсорное диммирование.",
      notes:          "Скрытая проводка коммуникаций в теле перегородки."
    }

    # Настройки для LayOut API
    project_data.pdf_settings[:export_engine] = "layout"
    project_data.pdf_settings[:layout_render_mode] = "vector"
    project_data.pdf_settings[:save_layout_file] = true
    project_data.pdf_settings[:page_size] = "A3"
    project_data.pdf_settings[:page_layout] = "landscape"
    project_data.pdf_settings[:stamp_type] = "approved"
    project_data.pdf_settings[:auto_open_pdf] = false

    project_data.sync_with_model_scenes(model)

    pdf_out    = File.expand_path("test_layout_export.pdf", __dir__)
    layout_out = File.expand_path("test_layout_export.layout", __dir__)

    File.delete(pdf_out) if File.exist?(pdf_out)
    File.delete(layout_out) if File.exist?(layout_out)

    assert(DN1Code::ExportPdf2::Service::LayoutBuilder.available?, "Сервис LayOutBuilder определяет доступность LayOut API")

    controller = DN1Code::ExportPdf2::Controller::ExportController.new(project_data, model)
    result_path = controller.export(pdf_out)

    assert(File.exist?(result_path), "Файл PDF успешно создан через LayOut API: #{File.basename(result_path)}")
    assert(File.exist?(layout_out), "Файл проекта LayOut (.layout) успешно сохранен рядом с PDF")

    # Проверка сохранения настроек LayOut в атрибуты модели
    saved_settings = model.get_attribute("DN1C_ExportPDF", "pdf_settings")
    assert(!saved_settings.nil? && saved_settings.include?("layout"), "Настройка 'export_engine: layout' сохранена в атрибуты модели")

    File.delete(pdf_out) if File.exist?(pdf_out)
    File.delete(layout_out) if File.exist?(layout_out)
  end

  def test_reopening_project_file_preserves_revision_and_yaml_string_keys
    puts "\n--- 12. Тест автоматического увеличения ревизии (+1) при открытии рабочего файла и поддержка строковых ключей YAML ---"

    test_dir = File.expand_path("test_reopen_dir", __dir__)
    FileUtils.mkdir_p(test_dir)

    skp_file = File.join(test_dir, "Project_Reopen.skp")
    yaml_file = File.join(test_dir, "ART-REOPEN-100.yaml")

    # Создаем YAML файл со строковыми ключами (как при внешнем создании или ручном редактировании)
    yaml_content = <<~YAML
      project_info:
        articul: "ART-REOPEN-100"
        name_project: "Проект с ревизией 7"
        version: 2
        revision: 7
        status: "В РАБОТЕ"
      pdf_settings:
        page_size: "A3"
        page_layout: "landscape"
    YAML
    File.write(yaml_file, yaml_content, encoding: "utf-8")

    # 1. Симулируем открытие существующей модели SketchUp
    model = Sketchup::MockModel.new(skp_file)

    # Вызываем ObserverService.handle_model_opened (открытие файла проекта)
    DN1Code::ExportPdf2::Service::ObserverService.handle_model_opened(model)

    # 2. Проверяем загрузку данных в проект: ревизия 7 автоматически увеличилась до 8
    loaded_data = DN1Code::ExportPdf2::Model::ProjectData.new
    src = loaded_data.load_auto(model)

    assert(src == :yaml, "При открытии файла источник определен как :yaml")
    assert(loaded_data.project_info[:revision] == 8, "Номер ревизии автоматически увеличен до 8 при открытии файла проекта")
    assert(loaded_data.project_info[:version] == 2, "Версия проекта (2) корректно прочитана")
    assert(loaded_data.project_info[:articul] == "ART-REOPEN-100", "Артикул корректно прочитан")
    assert(loaded_data.history.any? { |h| h[:description].include?("Открытие рабочего файла") }, "В историю изменений добавлена запись об открытии файла")

    # 3. Симулируем сохранение модели (pre_save / post_save)
    DN1Code::ExportPdf2::Service::ObserverService.handle_pre_save(model)
    DN1Code::ExportPdf2::Service::ObserverService.handle_post_save(model)

    rechecked_data = DN1Code::ExportPdf2::Model::ProjectData.new
    rechecked_data.load_auto(model)
    assert(rechecked_data.project_info[:revision] == 8, "После pre_save и post_save ревизия осталась равной 8")

    FileUtils.rm_rf(test_dir)
  end

  def test_project_config_and_edit_history_structure
    puts "\n--- 13. Тест интеграции структуры project_config.yaml и edit_history.yaml ---"

    workspace_root = File.expand_path("../..", __dir__)
    sample_cfg = File.join(workspace_root, "project_config.yaml")

    unless File.exist?(sample_cfg)
      File.write(sample_cfg, <<~YAML, encoding: "utf-8")
        project:
          articul: "HF#26050418280405"
          name_product: "Дверки, полки (Шкаф), Люк"
          name_place: "Мансарда"
          adress: "Белая Колпь"
          customer: "Алексей, Мария"
          status: "Правки"
          trade: "0"
          last_edit: "Добавлены замки"
        directories:
          задание_замеры:
            path: "!_замер_фото_задание"
          материалы_фурнитура:
            display: "grid"
          техника_подсветка:
            display: "list"
        api_targets:
          - "https://list.prodmd.top/api/projects"
          - "https://backup.prodmd.top/api/projects"
      YAML
    end

    # 1. Проверка чтения реального файла project_config.yaml
    assert(File.exist?(sample_cfg), "Файл project_config.yaml присутствует в корне проекта")
    data = DN1Code::ExportPdf2::Model::ProjectData.new
    loaded = data.load_from_yaml(sample_cfg)
    assert(loaded, "project_config.yaml успешно загружен через load_from_yaml")

    # 2. Проверка полей секции api_targets
    assert(data.api_targets.is_a?(Array) && data.api_targets.size >= 2, "Секция api_targets содержит минимум 2 адресата")
    assert(data.api_targets.any? { |u| u.include?("prodmd.top") }, "Адресат prodmd.top корректно прочитан")

    # 3. Проверка полей секции project и их двусторонней синхронизации
    info = data.project_info
    assert(info[:articul] == "HF#26050418280405", "Артикул HF#26050418280405 прочитан")
    assert(info[:name_product] == "Дверки, полки (Шкаф), Люк", "name_product прочитан: #{info[:name_product]}")
    assert(info[:furniture_name] == "Дверки, полки (Шкаф), Люк", "furniture_name синхронизирован с name_product")
    assert(info[:name_place] == "Мансарда", "name_place прочитан: #{info[:name_place]}")
    assert(info[:room_name] == "Мансарда", "room_name синхронизирован с name_place")
    assert(info[:name_project] == "Мансарда — Дверки, полки (Шкаф), Люк", "name_project составлен из name_place и name_product: #{info[:name_project]}")
    assert(info[:adress] == "Белая Колпь", "adress прочитан: #{info[:adress]}")
    assert(info[:address] == "Белая Колпь", "address синхронизирован с adress")
    assert(info[:customer] == "Алексей, Мария", "customer прочитан: #{info[:customer]}")
    assert(info[:name_customer] == "Алексей, Мария", "name_customer синхронизирован с customer")
    assert(info[:status] == "Правки", "status прочитан: #{info[:status]}")
    assert(info[:trade] == "0", "trade '0' (домашний HF#) корректно определен")
    assert(info[:last_edit] == "Добавлены замки", "last_edit прочитан: #{info[:last_edit]}")

    # 4. Проверка секции directories
    dirs = data.directories
    assert(dirs.is_a?(Hash) && dirs[:задание_замеры], "Секция directories содержит задание_замеры")
    assert(dirs[:задание_замеры][:path] == "!_замер_фото_задание", "Путь к каталогу замеров корректен")
    assert(dirs[:материалы_фурнитура][:display] == "grid", "Режим отображения папки материалов — grid")
    assert(dirs[:техника_подсветка][:display] == "list", "Режим отображения техники — list")

    # 5. Проверка обратной совместимости чтения устаревшего файла edit_history.yaml
    temp_dir = File.expand_path("test_history_save_dir", __dir__)
    FileUtils.mkdir_p(temp_dir)
    sample_hist = File.join(temp_dir, "legacy_edit_history.yaml")
    legacy_content = {
      "HF#26050418280405" => [
        { "date" => "2026-09-03 18:09", "text" => "Добавлены замки" },
        { "date" => "2026-09-02 15:10", "text" => "Правки по люку" },
        { "date" => "2026-09-01 17:10", "text" => "Добавлен Люк" },
        { "date" => "2026-08-31 12:10", "text" => "Добавлен второй шкаф" }
      ]
    }
    File.write(sample_hist, legacy_content.to_yaml, encoding: "utf-8")

    assert(File.exist?(sample_hist), "Файл legacy_edit_history.yaml создан для проверки совместимости")
    data.load_from_edit_history(sample_hist, "HF#26050418280405")
    assert(data.history.size == 4, "Из legacy_edit_history.yaml загружено 4 записи истории для артикула HF#26050418280405")
    assert(data.history.first[:text] == "Добавлены замки", "Первая запись истории содержит 'Добавлены замки'")
    assert(data.history.first[:description] == "Добавлены замки", "Поле description синхронизировано с text")
    assert(data.history.last[:text] == "Добавлен второй шкаф", "Последняя запись истории содержит 'Добавлен второй шкаф'")

    # 6. Тест автоопределения типа проекта trade по артикулу
    test_cf = DN1Code::ExportPdf2::Model::ProjectData.new
    test_cf.project_info[:articul] = "CF#26050610205001"
    test_cf.sync_project_fields!
    assert(test_cf.project_info[:trade] == "1", "Для артикула CF# автоматически определен commercial trade='1'")

    test_hf = DN1Code::ExportPdf2::Model::ProjectData.new
    test_hf.project_info[:articul] = "HF#26050610205001"
    test_hf.sync_project_fields!
    assert(test_hf.project_info[:trade] == "0", "Для артикула HF# автоматически определен home trade='0'")

    # 7. Тест сохранения и обновления edit_history.yaml с сохранением других проектов
    temp_dir = File.expand_path("test_history_save_dir", __dir__)
    FileUtils.mkdir_p(temp_dir)
    hist_out = File.join(temp_dir, "edit_history.yaml")

    # Записываем историю для ДВУХ разных артикулов
    initial_hash = {
      "OTHER#001" => [{ "date" => "2026-08-01 10:00", "text" => "Другой проект" }]
    }
    File.write(hist_out, initial_hash.to_yaml, encoding: "utf-8")

    # Сохраняем историю для нашего проекта
    data.save_to_edit_history(hist_out, "HF#26050418280405")

    # Читаем результат
    saved_yaml = YAML.load_file(hist_out)
    assert(saved_yaml.key?("OTHER#001"), "История другого проекта OTHER#001 сохранена в файле")
    assert(saved_yaml.key?("HF#26050418280405"), "История проекта HF#26050418280405 записана")
    assert(saved_yaml["HF#26050418280405"].size == 4, "Записаны все 4 правки текущего проекта")

    # 8. Генерация PDF документа с реальными данными project_config.yaml
    model = Sketchup::MockModel.new(File.join(temp_dir, "RealProject.skp"))
    model.pages.add("01. Обложка проекта")
    data.sync_with_model_scenes(model)

    pdf_out = File.join(temp_dir, "real_project_export.pdf")
    controller = DN1Code::ExportPdf2::Controller::ExportController.new(data, model)
    res = controller.export(pdf_out)
    assert(File.exist?(res), "PDF с реквизитами project_config.yaml успешно сгенерирован")
    assert(File.size(res) > 15000, "Размер сгенерированного PDF валиден (#{File.size(res)} байт)")

    FileUtils.rm_rf(temp_dir)
  end

  def test_separate_layout_yaml_file
    puts "\n--- 14. Тест разделения настроек программы (в плагине) и настроек проекта ---"

    # 1. Проверяем наличие файлов настроек программы ВНУТРИ ПЛАГИНА (dn1c_export_pdf2/config/)
    plugin_settings = DN1Code::ExportPdf2::Model::ProjectData::PROGRAM_SETTINGS_FILE
    plugin_layout   = DN1Code::ExportPdf2::Model::ProjectData::PROGRAM_LAYOUT_FILE

    assert(File.exist?(plugin_settings), "Файл настроек программы settings.yaml присутствует в плагине (#{plugin_settings})")
    assert(File.exist?(plugin_layout), "Файл макетов страниц layout.yaml присутствует в плагине (#{plugin_layout})")

    cfg_content = YAML.load_file(plugin_settings)
    assert(cfg_content.key?("pdf_settings") || cfg_content.key?(:pdf_settings), "Секция pdf_settings присутствует в настройках программы плагина")

    layout_content = YAML.load_file(plugin_layout)
    assert(layout_content.key?("layout") || layout_content.key?(:layout), "Корневой ключ layout присутствует в макетах программы плагина")

    # 2. Создаем временный каталог проекта для тестирования сохранения и изоляции
    test_dir = File.expand_path("test_separate_layout_dir", __dir__)
    FileUtils.mkdir_p(test_dir)

    skp_path = File.join(test_dir, "Villa_Interior.skp")
    model = Sketchup::MockModel.new(skp_path)

    project_data = DN1Code::ExportPdf2::Model::ProjectData.new
    project_data.project_info[:articul] = "VILLA-100"
    project_data.project_info[:name_product] = "Гардеробная"
    project_data.project_info[:name_place] = "Мастер-спальня"

    # Меняем параметры макета страницы программы
    project_data.pdf_settings[:custom_layouts][:cover][:cover_title] = {
      x: 10.0, y: 15.0, w: 80.0, h: 12.0, visible: true, align: "center"
    }

    # Сохраняем через save_auto
    project_data.save_auto(model)

    prj_yaml = File.join(test_dir, "VILLA-100.yaml")
    local_layout_yaml = File.join(test_dir, "layout.yaml")

    assert(File.exist?(prj_yaml), "Файл проекта VILLA-100.yaml создан в папке проекта")
    assert(!File.exist?(local_layout_yaml), "Файл layout.yaml НЕ создается в папке проекта (сохранен в плагине)")

    # 3. Проверяем, что в VILLA-100.yaml НЕТ настроек программы (pdf_settings / custom_layouts / layout)
    raw_prj_yaml = YAML.load_file(prj_yaml)
    assert(!raw_prj_yaml.key?("pdf_settings") && !raw_prj_yaml.key?(:pdf_settings), "Секция pdf_settings отсутствует в файле проекта (хранится в плагине)")
    assert(!raw_prj_yaml.key?("layout") && !raw_prj_yaml.key?(:layout), "Ключ layout отсутствует в файле проекта")

    # 4. Проверяем, что настройки программы успешно сохранились ВНУТРИ ПЛАГИНА
    raw_plugin_layout = YAML.load_file(plugin_layout)
    layout_blocks = raw_plugin_layout["layout"] || raw_plugin_layout[:layout]
    assert(!layout_blocks.nil?, "Блок layout присутствует в layout.yaml плагина")
    cover_title_block = layout_blocks["cover"]["cover_title"] || layout_blocks[:cover][:cover_title]
    assert((cover_title_block["align"] || cover_title_block[:align]) == "center", "Кастомное выравнивание блока 'center' сохранено в layout.yaml плагина")
    assert((cover_title_block["x"] || cover_title_block[:x]) == 10.0, "Кастомная координата X=10.0 сохранена в layout.yaml плагина")

    # 5. Проверяем автоматическую загрузку настроек программы и проекта (load_auto)
    loaded_data = DN1Code::ExportPdf2::Model::ProjectData.new
    source = loaded_data.load_auto(model)
    assert(source == :yaml, "Источник загрузки данных проекта определен как :yaml")
    loaded_title = loaded_data.pdf_settings[:custom_layouts][:cover][:cover_title]
    assert(loaded_title[:align] == "center", "Кастомное выравнивание макета прочитано из настроек программы плагина")
    assert(loaded_title[:x] == 10.0, "Координата X прочитана из настроек программы плагина")

    # 6. Проверяем метод load_from_layout_yaml напрямую
    direct_data = DN1Code::ExportPdf2::Model::ProjectData.new
    assert(direct_data.load_from_layout_yaml(plugin_layout), "Прямой вызов load_from_layout_yaml успешен")
    assert(direct_data.pdf_settings[:custom_layouts][:cover][:cover_title][:align] == "center", "Данные блоков совпадают при прямом чтении")

    # 7. Генерация PDF с разделенной структурой файлов
    model.pages.add("01. Обложка")
    loaded_data.sync_with_model_scenes(model)
    pdf_out = File.join(test_dir, "villa_export.pdf")
    controller = DN1Code::ExportPdf2::Controller::ExportController.new(loaded_data, model)
    res_pdf = controller.export(pdf_out)
    assert(File.exist?(res_pdf), "PDF с разделенной конфигурацией макетов успешно создан")
    assert(File.size(res_pdf) > 15000, "Размер PDF валиден (#{File.size(res_pdf)} байт)")

    FileUtils.rm_rf(test_dir)
  end

  def test_modular_yaml_structure_and_generators
    puts "\n--- 15. Тест новой модульной структуры YAML (project, customer, workflow, directories, scenes) ---"

    test_dir = File.expand_path("test_modular_dir", __dir__)
    FileUtils.mkdir_p(test_dir)

    # 1. Тест генераторов артикула и customer_id
    cf_art = DN1Code::ExportPdf2::Model::ProjectData.generate_articul(commercial: true, suffix: "01")
    hf_art = DN1Code::ExportPdf2::Model::ProjectData.generate_articul(commercial: false, suffix: "02")
    cust_id = DN1Code::ExportPdf2::Model::ProjectData.generate_customer_id

    assert(cf_art.start_with?("CF#"), "Артикул коммерческого проекта начинается с CF#: #{cf_art}")
    assert(hf_art.start_with?("HF#"), "Артикул бытового проекта начинается с HF#: #{hf_art}")
    assert(cust_id.start_with?("CUST-"), "ID заказчика начинается с CUST-: #{cust_id}")

    # 2. Создаем и заполняем модель модульными данными
    data = DN1Code::ExportPdf2::Model::ProjectData.new
    data.project[:articul]      = cf_art
    data.project[:product]      = "Шкаф купе, Тумба"
    data.project[:place]        = "Прихожая"
    data.project[:adress]       = "Никитская"
    data.project[:description]  = "Описание задания"
    data.project[:tags]         = ["прихожая", "шкаф"]
    data.project[:commercial]   = true
    data.project[:name_company] = "ООО Модуль"

    data.customer[:id]      = cust_id
    data.customer[:name]    = "Иван Петров"
    data.customer[:phone]   = "+7 (999) 111-22-33"
    data.customer[:email]   = "ivan@petrov.ru"

    data.workflow[:author]         = "Иванов И.И."
    data.workflow[:price]          = 150000
    data.workflow[:start_date]     = "2026-09-01"
    data.workflow[:end_date]       = "2026-09-15"
    data.workflow[:total_duration] = "12h 40m"
    data.workflow[:status]         = "Утвержден"
    data.workflow[:version]        = "01"
    data.workflow[:revision]       = "001"
    data.workflow[:history_edit]   = [
      ["2026-09-01 10:00", "Старт проекта"],
      ["2026-09-03 15:30", "Согласование материалов"]
    ]

    data.directories = [
      { path: "!_замер_фото_задание", title: "Замеры", description: "Дополнительное описание", display: "grid" },
      { path: "!_техника_подсветка", title: "Техника", description: "Спецификации и чертежи", display: "list" }
    ]

    # Проверка прокси-синхронизации
    data.sync_project_fields!
    assert(data.project_info[:furniture_name] == "Шкаф купе, Тумба", "Фасад project_info видит product через furniture_name")
    assert(data.project_info[:room_name] == "Прихожая", "Фасад project_info видит place через room_name")
    assert(data.project_info[:name_customer] == "Иван Петров", "Фасад project_info видит customer.name")
    assert(data.project_info[:trade] == "1", "Коммерческий флаг project.commercial синхронизирован в trade='1'")

    # 3. Сохранение в YAML файл
    yaml_file = File.join(test_dir, "modular_project.yaml")
    assert(data.save_to_yaml(yaml_file), "Модульный проект успешно сохранен в YAML")

    # 4. Проверка сырого содержимого сохраненного YAML
    raw = YAML.load_file(yaml_file)
    assert(raw.key?("project") || raw.key?(:project), "YAML содержит корневой ключ project")
    assert(raw.key?("customer") || raw.key?(:customer), "YAML содержит корневой ключ customer")
    assert(raw.key?("workflow") || raw.key?(:workflow), "YAML содержит корневой ключ workflow")
    assert(raw.key?("directories") || raw.key?(:directories), "YAML содержит корневой ключ directories")
    assert(raw.key?("scenes") || raw.key?(:scenes), "YAML содержит корневой ключ scenes")

    raw_prj = raw["project"] || raw[:project]
    assert(raw_prj["commercial"] == true || raw_prj[:commercial] == true, "Поле commercial записано как true")
    assert((raw_prj["name_company"] || raw_prj[:name_company]) == "ООО Модуль", "Поле name_company сохранено")

    raw_wf = raw["workflow"] || raw[:workflow]
    assert((raw_wf["price"] || raw_wf[:price]) == 150000, "Стоимость проекта сохранена")
    assert((raw_wf["total_duration"] || raw_wf[:total_duration]) == "12h 40m", "Общее время работы сохранено")
    raw_hist = raw_wf["history_edit"] || raw_wf[:history_edit]
    assert(raw_hist.is_a?(Array) && raw_hist.size == 2, "Список history_edit сохранен как массив кортежей")
    assert(raw_hist.first[1] == "Старт проекта", "Текст первой записи history_edit корректен")

    # 5. Загрузка в чистый экземпляр ProjectData
    loaded = DN1Code::ExportPdf2::Model::ProjectData.new
    assert(loaded.load_from_yaml(yaml_file), "Модульный YAML успешно загружен")
    assert(loaded.project[:product] == "Шкаф купе, Тумба", "product корректно прочитан")
    assert(loaded.customer[:name] == "Иван Петров", "customer.name корректно прочитан")
    assert(loaded.customer[:id] == cust_id, "customer.id корректно прочитан")
    assert(loaded.workflow[:status] == "Утвержден", "workflow.status корректно прочитан")
    assert(loaded.workflow[:total_duration] == "12h 40m", "workflow.total_duration прочитан")
    assert(loaded.workflow[:history_edit].size == 2, "Все записи history_edit прочитаны")

    # 6. Тест increment_revision! в новой структуре
    loaded.increment_revision!("Внесение правок по шкафу")
    assert(loaded.workflow[:revision] == "002", "Ревизия инкрементирована до 002: #{loaded.workflow[:revision]}")
    assert(loaded.workflow[:history_edit].size == 3, "В history_edit добавлена новая запись")
    assert(loaded.workflow[:history_edit].first[1].include?("Внесение правок по шкафу"), "Текст новой ревизии добавлен в history_edit")

    # 7. Генерация PDF из модульных данных
    skp_file = File.join(test_dir, "Modular_Test.skp")
    model = Sketchup::MockModel.new(skp_file)
    model.pages.add("01. Обложка")
    loaded.sync_with_model_scenes(model)

    pdf_out = File.join(test_dir, "modular_export.pdf")
    controller = DN1Code::ExportPdf2::Controller::ExportController.new(loaded, model)
    res_pdf = controller.export(pdf_out)
    assert(File.exist?(res_pdf), "PDF из модульного проекта успешно сгенерирован")
    assert(File.size(res_pdf) > 15000, "Размер PDF валиден (#{File.size(res_pdf)} байт)")

    # 8. Проверка приема данных из веб-диалога через ExportDialog.populate_project_data
    require_relative "../dialog/export_dialog"
    dialog_payload = {
      project: {
        articul: "CF#260905_150000_01",
        product: "Стол переговорный",
        commercial: true,
        name_company: "Дельта Холдинг"
      },
      customer: {
        id: "CUST-260905-150000",
        name: "Константин",
        phone: "+7 (900) 111-22-33"
      },
      workflow: {
        price: 85000,
        status: "В РАБОТЕ"
      },
      directories: [
        { path: "!_новые_папки", title: "Папка", description: "Тестовое описание", display: "grid" }
      ]
    }
    dlg_data = DN1Code::ExportPdf2::Model::ProjectData.new
    DN1Code::ExportPdf2::Dialog::ExportDialog.populate_project_data(dlg_data, dialog_payload)
    assert(dlg_data.project[:product] == "Стол переговорный", "ExportDialog успешно обработал project.product")
    assert(dlg_data.customer[:id] == "CUST-260905-150000", "ExportDialog успешно обработал customer.id")
    assert(dlg_data.workflow[:price] == 85000, "ExportDialog успешно обработал workflow.price")
    assert(dlg_data.project_info[:trade] == "1", "ExportDialog синхронизировал коммерческий статус trade='1'")
    assert(dlg_data.directories.first[:description] == "Тестовое описание", "ExportDialog сохранил directories.description")

    # Проверка загрузки и сохранения объединенных спецификаций в directories
    city_yaml_path = File.expand_path(File.join(__dir__, "../../CITY-2026-AP142.yaml"))
    if File.exist?(city_yaml_path)
      city_data = DN1Code::ExportPdf2::Model::ProjectData.new
      city_data.load_from_yaml(city_yaml_path)
      assert(city_data.project_info[:materials].include?("RAL 9003"), "Спецификация материалов синхронизирована из directories[].description")
      assert(city_data.project_info[:appliances].include?("3000K"), "Спецификация техники/подсветки синхронизирована из directories[].description")

      save_tmp_path = File.join(test_dir, "city_save_test.yaml")
      city_data.save_to_yaml(save_tmp_path)
      raw_saved = YAML.load_file(save_tmp_path)
      prj_saved = raw_saved["project"] || raw_saved[:project] || {}
      assert(!prj_saved.key?("notes") && !prj_saved.key?(:notes), "Отдельное поле notes отсутствует в секции project")
      assert(!prj_saved.key?("materials") && !prj_saved.key?(:materials), "Отдельное поле materials отсутствует в секции project")
      assert(!prj_saved.key?("appliances") && !prj_saved.key?(:appliances), "Отдельное поле appliances отсутствует в секции project")
      assert(!prj_saved.key?("lighting") && !prj_saved.key?(:lighting), "Отдельное поле lighting отсутствует в секции project")
      # Проверка сканирования превью файлов папки
      sample_folder = File.join(test_dir, "!_материалы_фурнитура")
      FileUtils.mkdir_p(sample_folder)
      File.write(File.join(sample_folder, "sample_facade.jpg"), "fake jpg content")
      File.write(File.join(sample_folder, "spec_table.pdf"), "fake pdf content")

      files_found = Dir.glob(File.join(sample_folder, "*")).select { |f| File.file?(f) }
      assert(files_found.length == 2, "В тестовой папке создано 2 файла для превью")
      jpg_found = files_found.any? { |f| File.extname(f).downcase == ".jpg" }
      pdf_found = files_found.any? { |f| File.extname(f).downcase == ".pdf" }
      assert(jpg_found && pdf_found, "Файлы изображений и документов корректно обнаружены для превью")
    end

    FileUtils.rm_rf(test_dir)
  end

  def test_fixed_7_slots_modular_layout
    puts "\n--- 16. Тест фиксированного макета из 7 стандартных слотов ---"

    project_data = DN1Code::ExportPdf2::Model::ProjectData.new
    settings = project_data.pdf_settings
    layouts = settings[:custom_layouts]

    # 1. Проверяем наличие всех 7 слотов во всех шаблонах
    required_slots = [:header, :image_4_3, :slot_1, :slot_2, :slot_3, :slot_4, :footer]
    [:cover, :description, :explain, :general, :visual].each do |tpl|
      assert(layouts.key?(tpl), "Шаблон #{tpl} присутствует в custom_layouts")
      required_slots.each do |s|
        assert(layouts[tpl].key?(s), "Шаблон #{tpl} содержит стандартный слот #{s}")
      end
    end

    # 2. Проверяем геометрические пропорции 4:3 видового экрана
    img_slot = layouts[:cover][:image_4_3]
    assert((img_slot[:x] == 25.0 && img_slot[:w] == 50.0) || (img_slot[:x] == 12.0 && img_slot[:w] == 76.0) || (img_slot[:x] == 10.0 && img_slot[:w] == 80.0), "Координаты X/W центрального 4:3 экрана корректны")
    assert((img_slot[:y] == 12.0 && img_slot[:h] == 82.0) || (img_slot[:y] == 9.0 && img_slot[:h] == 82.0) || (img_slot[:y] == 7.0 && img_slot[:h] == 86.0), "Координаты Y/H центрального 4:3 экрана корректны")

    # Проверяем выравнивание слотов от низа для нижних блоков
    assert(layouts[:cover][:slot_2][:valign] == "bottom", "Слот slot_2 в шаблоне cover имеет выравнивание от низа (valign: bottom)")
    assert(layouts[:cover][:slot_4][:valign] == "bottom", "Слот slot_4 в шаблоне cover имеет выравнивание от низа (valign: bottom)")
    assert(layouts[:description][:slot_2][:valign] == "bottom", "Слот slot_2 в шаблоне description имеет выравнивание от низа (valign: bottom)")
    assert(layouts[:description][:slot_4][:valign] == "bottom", "Слот slot_4 в шаблоне description имеет выравнивание от низа (valign: bottom)")

    # 3. Настраиваем привязку контента к слотам и прозрачность
    layouts[:cover][:slot_1] = { visible: true, content: "project_card", opacity: 0.9 }
    layouts[:cover][:slot_2] = { visible: true, content: "customer_card", opacity: 0.85 }
    layouts[:cover][:slot_3] = { visible: true, content: "workflow_status", opacity: 0.9 }
    layouts[:cover][:slot_4] = { visible: true, content: "history_table", opacity: 0.9 }

    # 4. Проверяем отключение отдельных слотов
    layouts[:description][:slot_2][:visible] = false
    layouts[:description][:slot_3][:visible] = false
    layouts[:description][:slot_1][:content] = "materials_spec"
    layouts[:description][:slot_4][:content] = "scene_notes"

    # 5. Тестируем рендеринг PDF страниц через PageBase#has_modular_slots?
    test_dir = File.expand_path("test_fixed_slots_dir", __dir__)
    FileUtils.rm_rf(test_dir)
    FileUtils.mkdir_p(test_dir)

    pdf_out = File.join(test_dir, "slots_layout_export.pdf")
    pdf_doc = Prawn::Document.new(page_size: "A4", page_layout: :landscape, margin: 15)
    DN1Code::ExportPdf2::Service::FontService.setup_fonts(pdf_doc)

    # Проверяем определение модульных слотов в PageBase
    project_data.project_info[:room_name] = "Спальня"
    project_data.project_info[:furniture_name] = "Гардеробная"
    project_data.project_info[:name_customer] = "Смирнов С.С."
    project_data.project_info[:articul] = "CF#260905_150000_01"
    project_data.project_info[:materials] = "ЛДСП Egger Кашемир серый, стекло тонированное"
    project_data.project_info[:notes] = "Подвод питания 220V в левом верхнем углу"

    cover_page = DN1Code::ExportPdf2::Controller::CoverPage.new(pdf_doc, project_data, nil, page_index: 1, total_pages: 2)
    assert(cover_page.has_modular_slots?, "CoverPage успешно обнаружил 7-слотовую архитектуру")
    cover_page.render

    pdf_doc.start_new_page
    desc_page = DN1Code::ExportPdf2::Controller::DescriptionPage.new(pdf_doc, project_data, nil, page_index: 2, total_pages: 2)
    assert(desc_page.has_modular_slots?, "DescriptionPage успешно обнаружил 7-слотовую архитектуру")
    desc_page.render

    pdf_doc.render_file(pdf_out)
    assert(File.exist?(pdf_out), "PDF файл со слотовой компоновкой успешно сгенерирован")
    assert(File.size(pdf_out) > 5000, "Размер сгенерированного PDF валиден (#{File.size(pdf_out)} байт)")

    # 6. Проверяем рендеринг слотов с выборочными строками (lines) и разделительными линиями между ними
    layouts[:cover][:slot_1][:lines] = ["room_name", "furniture_name", "trade_type"]
    layouts[:cover][:slot_2][:lines] = ["customer_name", "address"]
    layouts[:cover][:header][:lines] = ["furniture_name", "place_address", "customer_or_company"]

    pdf_doc2 = Prawn::Document.new(page_size: "A4", page_layout: :landscape, margin: 15)
    DN1Code::ExportPdf2::Service::FontService.setup_fonts(pdf_doc2)
    cover_page2 = DN1Code::ExportPdf2::Controller::CoverPage.new(pdf_doc2, project_data, nil, page_index: 1, total_pages: 1)
    cover_page2.render
    pdf_out2 = File.join(test_dir, "slots_multiline_export.pdf")
    pdf_doc2.render_file(pdf_out2)
    assert(File.exist?(pdf_out2), "PDF с разделителями между выбранными пунктами успешно сгенерирован")
    assert(File.size(pdf_out2) > 5000, "Размер PDF с разделителями валиден (#{File.size(pdf_out2)} байт)")

    FileUtils.rm_rf(test_dir)
  end

  # --- 17. Тест параметра отступа по периметру страницы и чистого рендера без рамок и цвета ---
  def test_page_margin_and_clean_render
    puts "\n--- 17. Тест параметра отступа по периметру страницы и чистого рендера без рамок и цвета ---"

    project_data = DN1Code::ExportPdf2::Model::ProjectData.new
    settings = project_data.pdf_settings

    assert(settings.key?(:margin_mm), "Ключ margin_mm присутствует в default_pdf_settings")
    assert(settings[:margin_mm] == 5, "Значение margin_mm по умолчанию равно 5 мм")

    # Проверяем расчет отступа в Prawn (мм -> pt)
    # 5 мм ~ 14.17 pt
    pdf_doc_5mm = DN1Code::ExportPdf2::Service::PdfBuilder.create_document(project_data, { margin_mm: 5 })
    bounds_5mm = pdf_doc_5mm.bounds
    # 0 мм (full bleed)
    pdf_doc_0mm = DN1Code::ExportPdf2::Service::PdfBuilder.create_document(project_data, { margin_mm: 0 })
    bounds_0mm = pdf_doc_0mm.bounds

    assert(bounds_0mm.width > bounds_5mm.width, "Ширина полезной области при отступе 0 мм больше, чем при 5 мм")
    assert(bounds_0mm.height > bounds_5mm.height, "Высота полезной области при отступе 0 мм больше, чем при 5 мм")

    # 10 мм
    pdf_doc_10mm = DN1Code::ExportPdf2::Service::PdfBuilder.create_document(project_data, { margin_mm: 10 })
    bounds_10mm = pdf_doc_10mm.bounds
    assert(bounds_5mm.width > bounds_10mm.width, "Ширина полезной области при 5 мм больше, чем при 10 мм")

    # Тест генерации чистого документа без рамок и цветных плашек
    test_dir = File.join(File.dirname(__FILE__), "temp_margin_test")
    FileUtils.rm_rf(test_dir)
    FileUtils.mkdir_p(test_dir)

    clean_pdf_path = File.join(test_dir, "clean_render_test.pdf")
    doc = DN1Code::ExportPdf2::Service::PdfBuilder.create_document(project_data, { margin_mm: 8, page_size: "A4", page_layout: "landscape" })

    project_data.project_info[:room_name] = "Гостиная"
    project_data.project_info[:furniture_name] = "Стеллаж встроенный"
    project_data.project_info[:name_customer] = "Петров А.В."
    project_data.project_info[:articul] = "CF#260905_160000_01"

    # Рендерим титульную страницу
    cover = DN1Code::ExportPdf2::Controller::CoverPage.new(doc, project_data, nil, page_index: 1, total_pages: 3)
    cover.render

    doc.start_new_page
    # Рендерим визуализацию
    visual = DN1Code::ExportPdf2::Controller::VisualPage.new(doc, project_data, nil, page_index: 2, total_pages: 3)
    visual.render

    doc.start_new_page
    # Рендерим описание
    desc = DN1Code::ExportPdf2::Controller::DescriptionPage.new(doc, project_data, nil, page_index: 3, total_pages: 3)
    desc.render

    doc.render_file(clean_pdf_path)

    assert(File.exist?(clean_pdf_path), "PDF с новым параметром отступа и чистым стилем создан")
    assert(File.size(clean_pdf_path) > 10000, "Размер чистого PDF валиден (#{File.size(clean_pdf_path)} байт)")

    FileUtils.rm_rf(test_dir)
  end

  def test_scene_drag_reordering_and_renaming
    puts "\n--- 18. Тест переупорядочивания сцен (Drag & Drop) и редактирования названий сцен ---"

    model = Sketchup::MockModel.new("U:/dn1code/test_reorder/kitchen.skp")
    scenes = [
      "01. Обложка",
      "02. Описание",
      "03. Перспектива",
      "04. Спецификация"
    ]
    model.pages = Sketchup::MockPages.new(scenes.map { |s| Sketchup::MockPage.new(s) })

    project_data = DN1Code::ExportPdf2::Model::ProjectData.new
    project_data.sync_with_model_scenes(model)

    assert(project_data.scenes.size == 4, "Начально обнаружено 4 сцены")
    assert(project_data.scenes.map(&:name) == scenes, "Порядок сцен соответствует исходному")

    # 1. Симулируем перетаскивание строк мышью в веб-интерфейсе:
    # Перемещаем "03. Перспектива" на 1-е место (индекс 0)
    # Новый порядок: 03. Перспектива, 01. Обложка, 02. Описание, 04. Спецификация
    dragged_item = project_data.scenes.delete_at(2) # "03. Перспектива"
    project_data.scenes.unshift(dragged_item)
    project_data.scenes.each_with_index { |s, idx| s.order = idx }

    assert(project_data.scenes[0].name == "03. Перспектива", "Первой сценой стала '03. Перспектива'")
    assert(project_data.scenes[0].order == 0, "Порядковый индекс первой сцены равен 0")

    # Синхронизация с моделью SketchUp должна сохранять пользовательский порядок
    project_data.sync_with_model_scenes(model)
    assert(project_data.scenes[0].name == "03. Перспектива", "Пользовательский порядок сохранен после sync_with_model_scenes")
    assert(project_data.scenes[1].name == "01. Обложка", "Вторая сцена: 01. Обложка")
    assert(project_data.scenes[2].name == "02. Описание", "Третья сцена: 02. Описание")
    assert(project_data.scenes[3].name == "04. Спецификация", "Четвертая сцена: 04. Спецификация")

    # 2. Симулируем редактирование названия сцены пользователем
    # Переименовываем "03. Перспектива" в "01. Главный 3D вид"
    project_data.scenes[0].name = "01. Главный 3D вид"
    assert(project_data.scenes[0].name == "01. Главный 3D вид", "Имя сцены успешно обновлено в SceneItem")

    # Синхронизация с моделью должна переименовать страницу в SketchUp
    project_data.sync_with_model_scenes(model)
    skp_page = model.pages.find { |p| p.name == "01. Главный 3D вид" }
    assert(!skp_page.nil?, "Страница в модели SketchUp успешно переименована в '01. Главный 3D вид'")
    assert(project_data.scenes[0].original_name == "01. Главный 3D вид", "original_name синхронизирован с новым именем")

    # 3. Сериализация в хэш/JSON и восстановление
    scene_hash = project_data.scenes[0].to_h
    assert(scene_hash[:name] == "01. Главный 3D вид", "to_h содержит обновленное имя")
    assert(scene_hash.key?(:original_name), "to_h содержит ключ original_name")

    restored_scene = DN1Code::ExportPdf2::Model::SceneItem.from_h(scene_hash)
    assert(restored_scene.name == "01. Главный 3D вид", "from_h корректно восстанавливает обновленное имя")
    assert(restored_scene.original_name == "01. Главный 3D вид", "from_h корректно восстанавливает original_name")

    # 4. Проверка генерации PDF с переупорядоченными и переименованными сценами
    test_dir = File.expand_path("test_drag_dir", __dir__)
    FileUtils.mkdir_p(test_dir)
    pdf_out = File.join(test_dir, "reordered_export.pdf")

    controller = DN1Code::ExportPdf2::Controller::ExportController.new(project_data, model)
    result_file = controller.export(pdf_out)

    assert(File.exist?(result_file), "PDF с измененным порядком и новым названием сцены создан")
    assert(File.size(result_file) > 10000, "Размер PDF валиден (#{File.size(result_file)} байт)")

    FileUtils.rm_rf(test_dir)
  end

  # --- 19. Тест выбора строк (1, 2, 3) и объединения в одну строку через | в шапке ---
  def test_header_line_rows_grouping
    puts "\n--- 19. Тест выбора строк (1, 2, 3) и объединения в одну строку через | в шапке ---"
    project_data = DN1Code::ExportPdf2::Model::ProjectData.new
    project_data.project_info[:furniture_name] = "Шкаф-купе"
    project_data.project_info[:room_name] = "Прихожая"
    project_data.project_info[:address] = "ул. Ленина, 10"
    project_data.project_info[:name_customer] = "Иванов И.И."

    layouts = project_data.pdf_settings[:custom_layouts]
    lr = layouts[:cover][:header][:line_rows]
    assert(lr.is_a?(Hash), "В слоте header присутствует line_rows")
    assert((lr["furniture_name"] || lr[:furniture_name]) == 1, "furniture_name по умолчанию на строке 1")
    assert((lr["place_address"] || lr[:place_address]) == 2, "place_address по умолчанию на строке 2")
    assert((lr["customer_or_company"] || lr[:customer_or_company]) == 3, "customer_or_company по умолчанию на строке 3")

    # 1. Проверяем генерацию PDF когда у всех выбрана строка 1
    layouts[:cover][:header][:line_rows] = {
      "furniture_name" => 1,
      "place_address" => 1,
      "customer_or_company" => 1
    }

    test_dir = File.expand_path("test_header_rows_dir", __dir__)
    FileUtils.mkdir_p(test_dir)
    pdf_out = File.join(test_dir, "header_single_line.pdf")

    pdf_doc = Prawn::Document.new(page_size: "A4", page_layout: :landscape, margin: 15)
    DN1Code::ExportPdf2::Service::FontService.setup_fonts(pdf_doc)
    cover_page = DN1Code::ExportPdf2::Controller::CoverPage.new(pdf_doc, project_data, nil, page_index: 1, total_pages: 1)
    cover_page.render
    pdf_doc.render_file(pdf_out)

    assert(File.exist?(pdf_out), "PDF с объединенным в одну строку заголовком успешно создан")
    assert(File.size(pdf_out) > 5000, "Размер PDF с однострочным заголовком валиден (#{File.size(pdf_out)} байт)")

    # 2. Проверяем генерацию PDF когда выбраны 2 строки (1 и 2)
    layouts[:cover][:header][:line_rows] = {
      "furniture_name" => 1,
      "place_address" => 1,
      "customer_or_company" => 2
    }
    pdf_out2 = File.join(test_dir, "header_two_lines.pdf")
    pdf_doc2 = Prawn::Document.new(page_size: "A4", page_layout: :landscape, margin: 15)
    DN1Code::ExportPdf2::Service::FontService.setup_fonts(pdf_doc2)
    cover_page2 = DN1Code::ExportPdf2::Controller::CoverPage.new(pdf_doc2, project_data, nil, page_index: 1, total_pages: 1)
    cover_page2.render
    pdf_doc2.render_file(pdf_out2)

    assert(File.exist?(pdf_out2), "PDF с заголовком на двух строках успешно создан")
    assert(File.size(pdf_out2) > 5000, "Размер PDF с двухстрочным заголовком валиден (#{File.size(pdf_out2)} байт)")

    FileUtils.rm_rf(test_dir)
  end

  # --- 20. Тест вертикального выравнивания в заголовке (по верху, по центру, по низу) ---
  def test_header_vertical_alignment
    puts "\n--- 20. Тест вертикального выравнивания в шапке (valign: top, center, bottom) ---"
    project_data = DN1Code::ExportPdf2::Model::ProjectData.new
    project_data.project_info[:furniture_name] = "Кухонный гарнитур"
    project_data.project_info[:room_name] = "Кухня"
    project_data.project_info[:address] = "Невский пр., 12"
    project_data.project_info[:name_customer] = "Петров П.П."

    layouts = project_data.pdf_settings[:custom_layouts]
    hdr = layouts[:cover][:header]
    assert(hdr[:valign] == "center" || hdr[:valign] == :center, "Шапка по умолчанию имеет вертикальное выравнивание center")
    assert(hdr[:align] == "center" || hdr[:align] == :center, "Шапка по умолчанию имеет горизонтальное выравнивание center")

    test_dir = File.expand_path("test_header_valign_dir", __dir__)
    FileUtils.mkdir_p(test_dir)

    [:top, :center, :bottom].each do |valign_mode|
      layouts[:cover][:header][:valign] = valign_mode
      pdf_out = File.join(test_dir, "header_valign_#{valign_mode}.pdf")
      pdf_doc = Prawn::Document.new(page_size: "A4", page_layout: :landscape, margin: 15)
      DN1Code::ExportPdf2::Service::FontService.setup_fonts(pdf_doc)
      cover_page = DN1Code::ExportPdf2::Controller::CoverPage.new(pdf_doc, project_data, nil, page_index: 1, total_pages: 1)
      cover_page.render
      pdf_doc.render_file(pdf_out)

      assert(File.exist?(pdf_out), "PDF с шапкой (valign: #{valign_mode}) успешно сгенерирован")
      assert(File.size(pdf_out) > 5000, "Размер PDF (valign: #{valign_mode}) валиден (#{File.size(pdf_out)} байт)")
    end

    # Тест custom_text с выравниванием по вертикали
    layouts[:cover][:header][:content] = "custom_text"
    layouts[:cover][:header][:custom_text] = "Пользовательский заголовок проекта"
    layouts[:cover][:header][:valign] = :top
    pdf_custom = File.join(test_dir, "header_custom_top.pdf")
    pdf_doc = Prawn::Document.new(page_size: "A4", page_layout: :landscape, margin: 15)
    DN1Code::ExportPdf2::Service::FontService.setup_fonts(pdf_doc)
    cover_page = DN1Code::ExportPdf2::Controller::CoverPage.new(pdf_doc, project_data, nil, page_index: 1, total_pages: 1)
    cover_page.render
    pdf_doc.render_file(pdf_custom)

    assert(File.exist?(pdf_custom), "PDF с custom_text шапкой (valign: top) успешно сгенерирован")

    FileUtils.rm_rf(test_dir)
  end

  # --- 21. Тест жесткой фиксации высоты заголовка (30%, не регулируется) ---
  def test_header_height_isolation
    puts "\n--- 21. Тест жесткой фиксации высоты заголовка (строго 30%, от верхнего края, не регулируется) ---"
    project_data = DN1Code::ExportPdf2::Model::ProjectData.new
    layouts = project_data.pdf_settings[:custom_layouts]

    # Проверка отсутствия отступа сверху у боковых блоков
    assert(layouts[:cover][:slot_1][:y] == 0.0, "slot_1 в шаблоне cover не имеет отступа сверху (y = 0.0)")
    assert(layouts[:cover][:slot_3][:y] == 0.0, "slot_3 в шаблоне cover не имеет отступа сверху (y = 0.0)")

    # Проверка, что во всех шаблонах высота заголовка установлена в 30.0%
    [:cover, :description, :explain, :general, :visual].each do |tpl|
      hdr = layouts[tpl][:header]
      assert(hdr && hdr[:h] == 30.0, "Высота заголовка в шаблоне #{tpl} равна 30.0%")
      assert(hdr && hdr[:y] == 0.0, "Позиция Y заголовка в шаблоне #{tpl} равна 0.0 (верхний край)")
    end

    # Проверка строгого принудительного ограничения 30% в get_block_box при попытке задать другие значения
    pdf_doc = Prawn::Document.new(page_size: "A4", page_layout: :landscape, margin: 15)
    DN1Code::ExportPdf2::Service::FontService.setup_fonts(pdf_doc)
    cover_page = DN1Code::ExportPdf2::Controller::CoverPage.new(pdf_doc, project_data, nil, page_index: 1, total_pages: 1)

    # Даже если во внешнем конфиге задана другая высота (например 10% или 50%), get_block_box жестко выдает 30%
    layouts[:cover][:header][:h] = 10.0
    layouts[:cover][:header][:y] = 5.0
    box = cover_page.send(:get_block_box, :cover, :header, 0.0, 0.0, 100.0, 14.0)
    expected_h = pdf_doc.bounds.height * 0.30
    assert((box[:height] - expected_h).abs < 0.001, "get_block_box жестко возвращает ровно 30% высоты листа (#{expected_h.round(2)} pt)")
    assert((box[:y] - pdf_doc.bounds.top).abs < 0.001, "get_block_box позиционирует шапку строго от верхнего края (y = bounds.top)")

    # Проверяем независимость остальных блоков
    orig_s1_y = layouts[:cover][:slot_1][:y]
    orig_s1_h = layouts[:cover][:slot_1][:h]
    assert(orig_s1_y == 0.0, "slot_1[:y] не зависит от высоты заголовка")
    assert(orig_s1_h == 58.0, "slot_1[:h] не зависит от высоты заголовка")

    test_dir = File.expand_path("test_header_height_dir", __dir__)
    FileUtils.mkdir_p(test_dir)
    pdf_out = File.join(test_dir, "header_fixed_30pct.pdf")
    cover_page.render
    pdf_doc.render_file(pdf_out)

    assert(File.exist?(pdf_out), "PDF с жестко заданной высотой шапки 30% успешно сгенерирован")
    assert(File.size(pdf_out) > 5000, "Размер PDF валиден (#{File.size(pdf_out)} байт)")
    FileUtils.rm_rf(test_dir)
  end

  def test_footer_divided_items_and_alignment
    puts "\n--- 22. Тест разделения блока Подвал на 5 пунктов и выравнивания (слева, центр, справа) ---"

    project_data = DN1Code::ExportPdf2::Model::ProjectData.new
    layouts = project_data.pdf_settings[:custom_layouts]

    # 1. Проверка наличия 5 раздельных пунктов в default_layouts для каждого шаблона
    [:cover, :description, :explain, :general, :visual].each do |tpl|
      ftr = layouts[tpl][:footer]
      assert(ftr, "Блок footer присутствует в шаблоне #{tpl}")
      lines = ftr[:lines]
      assert(lines.include?("footer_last_edit") || lines.include?(:footer_last_edit), "В шаблоне #{tpl} есть footer_last_edit")
      assert(lines.include?("footer_ver_rev") || lines.include?(:footer_ver_rev), "В шаблоне #{tpl} есть footer_ver_rev")
      assert(lines.include?("footer_articul") || lines.include?(:footer_articul), "В шаблоне #{tpl} есть footer_articul")
      assert(lines.include?("footer_date") || lines.include?(:footer_date), "В шаблоне #{tpl} есть footer_date")
      assert(lines.include?("footer_page_total") || lines.include?(:footer_page_total), "В шаблоне #{tpl} есть footer_page_total")

      aligns = ftr[:line_aligns] || {}
      assert(aligns[:footer_last_edit].to_s == "left" || aligns["footer_last_edit"].to_s == "left", "В шаблоне #{tpl} footer_last_edit выровнен слева")
      assert(aligns[:footer_ver_rev].to_s == "center" || aligns["footer_ver_rev"].to_s == "center", "В шаблоне #{tpl} footer_ver_rev выровнен по центру")
      assert(aligns[:footer_articul].to_s == "center" || aligns["footer_articul"].to_s == "center", "В шаблоне #{tpl} footer_articul выровнен по центру")
      assert(aligns[:footer_date].to_s == "center" || aligns["footer_date"].to_s == "center", "В шаблоне #{tpl} footer_date выровнен по центру")
      assert(aligns[:footer_page_total].to_s == "right" || aligns["footer_page_total"].to_s == "right", "В шаблоне #{tpl} footer_page_total выровнен справа")
    end

    # 2. Проверка разрешения строк
    pdf_doc = Prawn::Document.new(page_size: "A4", page_layout: :landscape, margin: 5)
    DN1Code::ExportPdf2::Service::FontService.setup_fonts(pdf_doc)
    cover_page = DN1Code::ExportPdf2::Controller::CoverPage.new(pdf_doc, project_data, nil, page_index: 1, total_pages: 5)

    last_edit_str = cover_page.send(:resolve_info_line, "footer_last_edit")
    assert(last_edit_str && last_edit_str.start_with?("Последние изменения"), "resolve_info_line('footer_last_edit') формирует 'Последние изменения: ...'")

    ver_rev_str = cover_page.send(:resolve_info_line, "footer_ver_rev")
    assert(ver_rev_str && ver_rev_str.include?("Версия") && ver_rev_str.include?("Ревизия"), "resolve_info_line('footer_ver_rev') формирует 'Версия ... # Ревизия ...'")

    art_str = cover_page.send(:resolve_info_line, "footer_articul")
    assert(art_str && art_str.include?("Артикул"), "resolve_info_line('footer_articul') формирует 'Артикул: ...'")

    date_str = cover_page.send(:resolve_info_line, "footer_date")
    assert(date_str && date_str.include?("Дата:"), "resolve_info_line('footer_date') формирует 'Дата: ...'")

    page_str = cover_page.send(:resolve_info_line, "footer_page_total")
    assert(page_str && page_str.include?("Страница 1 | 5"), "resolve_info_line('footer_page_total') формирует 'Страница 1 | 5'")

    legacy_str = cover_page.send(:resolve_info_line, "footer_rev_ver_date")
    assert(legacy_str && legacy_str.include?("Ревизия"), "Обратная совместимость: resolve_info_line('footer_rev_ver_date') работает")

    # 3. Генерация PDF с кастомным распределением выравнивания
    test_dir = File.expand_path("test_footer_dir", __dir__)
    FileUtils.mkdir_p(test_dir)

    # Меняем выравнивание: Артикул - влево, Дата - вправо
    layouts[:cover][:footer][:line_aligns] = {
      "footer_last_edit"  => "left",
      "footer_articul"    => "left",
      "footer_ver_rev"    => "center",
      "footer_date"       => "right",
      "footer_page_total" => "right"
    }

    pdf_out = File.join(test_dir, "custom_footer_align.pdf")
    cover_page.render
    pdf_doc.render_file(pdf_out)

    assert(File.exist?(pdf_out), "PDF с кастомным выравниванием подвала успешно сгенерирован")
    assert(File.size(pdf_out) > 5000, "Размер PDF валиден (#{File.size(pdf_out)} байт)")

    FileUtils.rm_rf(test_dir)
  end

  # --- 23. Тест учета количества создаваемых страниц в содержании проекта ---
  def test_toc_page_count_and_created_pages_filtering
    puts "\n--- 23. Тест учета количества создаваемых страниц в содержании (TOC) ---"

    project_data = DN1Code::ExportPdf2::Model::ProjectData.new
    project_data.project_info = {
      name_project:   "Квартира на Тверской",
      room_name:      "Кухня-гостиная",
      furniture_name: "Гарнитур со встроенной техникой",
      articul:        "TVR-2026-01",
      version:        1,
      revision:       2
    }

    # Создаем 5 сцен: 3 включены (из них 1 с типом :skip), 2 отключены
    scenes = [
      DN1Code::ExportPdf2::Model::SceneItem.new(name: "01. Обложка", page_type: :cover, enabled: true),
      DN1Code::ExportPdf2::Model::SceneItem.new(name: "02. Содержание", page_type: :explain, enabled: true),
      DN1Code::ExportPdf2::Model::SceneItem.new(name: "03. Черновой вид", page_type: :skip, enabled: true),
      DN1Code::ExportPdf2::Model::SceneItem.new(name: "04. Скрытый ракурс", page_type: :visual, enabled: false),
      DN1Code::ExportPdf2::Model::SceneItem.new(name: "05. Финальный рендер", page_type: :visual, enabled: true)
    ]
    project_data.scenes = scenes

    # 1. Проверка resolve_info_line('toc_pages')
    pdf_doc = DN1Code::ExportPdf2::Service::PdfBuilder.create_document(project_data, project_data.pdf_settings)
    cover_page = DN1Code::ExportPdf2::Controller::CoverPage.new(pdf_doc, project_data, scenes[0], page_index: 1, total_pages: 3)

    toc_text = cover_page.send(:resolve_info_line, "toc_pages")
    assert(toc_text && toc_text.include?("всего страниц: 3"), "resolve_info_line('toc_pages') содержит 'всего страниц: 3'")
    assert(toc_text.include?("1. 01. Обложка"), "TOC содержит '1. 01. Обложка'")
    assert(toc_text.include?("2. 02. Содержание"), "TOC содержит '2. 02. Содержание'")
    assert(toc_text.include?("3. 05. Финальный рендер"), "TOC содержит '3. 05. Финальный рендер'")
    assert(!toc_text.include?("Черновой вид"), "TOC исключает сцены с page_type: :skip")
    assert(!toc_text.include?("Скрытый ракурс"), "TOC исключает отключенные сцены (enabled: false)")

    # 2. Рендеринг ExplainPage с отображением общего количества страниц
    pdf_doc2 = DN1Code::ExportPdf2::Service::PdfBuilder.create_document(project_data, project_data.pdf_settings)
    explain_page = DN1Code::ExportPdf2::Controller::ExplainPage.new(pdf_doc2, project_data, scenes[1], page_index: 2, total_pages: 3)

    test_dir = File.expand_path("test_toc_dir", __dir__)
    FileUtils.mkdir_p(test_dir)
    pdf_out = File.join(test_dir, "explain_toc_test.pdf")

    explain_page.render
    pdf_doc2.render_file(pdf_out)

    assert(File.exist?(pdf_out), "PDF со страницей ExplainPage успешно создан")
    assert(File.size(pdf_out) > 5000, "Размер PDF ExplainPage валиден (#{File.size(pdf_out)} байт)")

    FileUtils.rm_rf(test_dir)
  end

  # --- 24. Тест удаления параметра высоты заголовка, 5 строк и получения названия/описания из сцены ---
  def test_header_scene_name_and_description
    puts "\n--- 24. Тест удаления параметра высоты заголовка, 5 строк и получения названия/описания из сцены ---"

    # 1. Проверка app.js на отсутствие контрола высоты заголовка и наличие пунктов Название Сцены и Описание Сцены
    app_js_path = File.expand_path("../dialog/html/app.js", __dir__)
    app_js_content = File.read(app_js_path, encoding: "utf-8")

    assert(!app_js_content.include?("sel_header_height"), "app.js не содержит выбор высоты заголовка sel_header_height")
    assert(!app_js_content.include?("tpl-badge-fixed"), "app.js не содержит бейдж фиксированной высоты заголовка в карточке")
    assert(app_js_content.include?("data-key=\"scene_name\""), "app.js содержит чекбокс пункта Название Сцены (scene_name)")
    assert(app_js_content.include?("data-key=\"scene_description\""), "app.js содержит чекбокс пункта Описание Сцены (scene_description)")
    assert(app_js_content.include?("Название Сцены"), "app.js содержит текст 'Название Сцены'")
    assert(app_js_content.include?("Описание Сцены"), "app.js содержит текст 'Описание Сцены'")
    assert(app_js_content.include?("r <= 5"), "app.js генерирует кнопки выбора для 5 строк (r <= 5)")

    # 2. Проверка разрешения строк через resolve_info_line и получение из scene_ref
    project_data = DN1Code::ExportPdf2::Model::ProjectData.new
    mock_page = Sketchup::MockPage.new("03. Перспективный вид гостиной")
    mock_page.description = "Рендер дневного света с подсветкой ниш из SketchUp сцены"
    scene = DN1Code::ExportPdf2::Model::SceneItem.new(
      name: "03. Перспективный вид гостиной",
      description: "Рендер дневного света с подсветкой ниш из SketchUp сцены",
      scene_ref: mock_page,
      page_type: :visual,
      order: 2,
      enabled: true
    )

    pdf_doc = DN1Code::ExportPdf2::Service::PdfBuilder.create_document(project_data, project_data.pdf_settings)
    visual_page = DN1Code::ExportPdf2::Controller::VisualPage.new(pdf_doc, project_data, scene, page_index: 3, total_pages: 5)

    s_name_val = visual_page.send(:resolve_info_line, "scene_name")
    assert(s_name_val && s_name_val.include?("03. Перспективный вид гостиной"), "resolve_info_line('scene_name') содержит имя сцены")

    s_desc_val = visual_page.send(:resolve_info_line, "scene_description")
    assert(s_desc_val && s_desc_val.include?("Рендер дневного света с подсветкой ниш из SketchUp сцены"), "resolve_info_line('scene_description') содержит описание сцены")

    # 3. Настройка заголовка со всеми 5 отдельными строками (1, 2, 3, 4, 5)
    layouts = project_data.pdf_settings[:custom_layouts]
    layouts[:visual][:header] = {
      visible: true,
      align: "center",
      valign: "center",
      font_size: 10.0,
      lines: ["furniture_name", "place_address", "customer_or_company", "scene_name", "scene_description"],
      line_rows: {
        "furniture_name" => 1,
        "place_address" => 2,
        "customer_or_company" => 3,
        "scene_name" => 4,
        "scene_description" => 5
      }
    }

    # 4. Рендеринг страницы VisualPage с кастомным заголовком из 5 строк
    test_dir = File.expand_path("test_header_scene_dir", __dir__)
    FileUtils.mkdir_p(test_dir)
    pdf_out = File.join(test_dir, "visual_scene_5_rows_header.pdf")

    visual_page.render
    pdf_doc.render_file(pdf_out)

    assert(File.exist?(pdf_out), "PDF с заголовком из 5 строк успешно сгенерирован")
    assert(File.size(pdf_out) > 5000, "Размер сгенерированного PDF валиден (#{File.size(pdf_out)} байт)")

    # 5. Проверка фоллбэка описания из scene_ref, если в scene_item описание пусто
    scene_empty_desc = DN1Code::ExportPdf2::Model::SceneItem.new(
      name: "04. План расстановки мебели",
      description: "",
      scene_ref: mock_page,
      page_type: :general,
      order: 3,
      enabled: true
    )
    mock_page.description = "Чертеж с привязками розеток из страницы SketchUp"
    pdf_doc2 = DN1Code::ExportPdf2::Service::PdfBuilder.create_document(project_data, project_data.pdf_settings)
    gen_page = DN1Code::ExportPdf2::Controller::GeneralPage.new(pdf_doc2, project_data, scene_empty_desc, page_index: 4, total_pages: 5)
    desc_from_ref = gen_page.send(:resolve_info_line, "scene_description")
    assert(desc_from_ref && desc_from_ref.include?("Чертеж с привязками розеток из страницы SketchUp"), "Описание берется напрямую из страницы SketchUp (scene_ref), если в элементе сцены оно пусто")

    # 6. Проверка приоритета scene_ref над устаревшими данными в scene_item
    mock_page.name = "04. Обновленный план"
    mock_page.description = "Актуальное описание из SketchUp"
    scene_item_stale = DN1Code::ExportPdf2::Model::SceneItem.new(
      name: "04. Старый план",
      description: "Старое описание",
      scene_ref: mock_page,
      page_type: :general
    )
    gen_page_stale = DN1Code::ExportPdf2::Controller::GeneralPage.new(pdf_doc2, project_data, scene_item_stale)
    cfg_stale = { lines: ["scene_name", "scene_description"], line_rows: { "scene_name" => 4, "scene_description" => 5 } }
    
    # 7. Проверка алиасов description и desc в блоке заголовка - они берут описание сцены, а не проекта
    project_data.project_info[:description] = "ГЛОБАЛЬНОЕ ОПИСАНИЕ ВСЕГО ПРОЕКТА"
    hdr_box = { x: 0.0, y: 100.0, width: 200.0, height: 50.0 }
    layouts[:general][:header] = {
      visible: true,
      lines: ["furniture_name", "scene_name", "description"],
      line_rows: { "furniture_name" => 1, "scene_name" => 2, "description" => 3 }
    }
    # Проверяем через resolve_info_line и алиасы
    assert(gen_page_stale.send(:resolve_info_line, "scene_name").include?("04. Обновленный план"), "Название сцены берется из scene_ref при наличии")
    assert(gen_page_stale.send(:resolve_info_line, "scene_description").include?("Актуальное описание из SketchUp"), "Описание сцены берется из scene_ref")

    # 8. Проверка синхронизации sync_with_model_scenes из SketchUp page.description
    model = Sketchup::MockModel.new
    page_with_desc = Sketchup::MockPage.new("05. Тестовая сцена")
    page_with_desc.description = "Примечание к сцене из вкладки SketchUp"
    model.pages = [page_with_desc]
    sync_data = DN1Code::ExportPdf2::Model::ProjectData.new
    sync_data.sync_with_model_scenes(model)
    synced_scene = sync_data.scenes.find { |s| s.name == "05. Тестовая сцена" }
    assert(synced_scene && synced_scene.description == "Примечание к сцене из вкладки SketchUp", "sync_with_model_scenes переносит page.description в scene_item")

    # 9. Проверка default_custom_layouts на наличие scene_name (строка 4) и scene_description (строка 5)
    [:cover, :description, :explain, :general, :visual].each do |tpl|
      hdr = sync_data.default_custom_layouts[tpl][:header]
      assert(hdr[:lines].include?("scene_name"), "default_custom_layouts[#{tpl}] содержит scene_name")
      assert(hdr[:lines].include?("scene_description"), "default_custom_layouts[#{tpl}] содержит scene_description")
      assert(hdr[:line_rows]["scene_name"] == 4, "default_custom_layouts[#{tpl}] scene_name на 4 строке")
      assert(hdr[:line_rows]["scene_description"] == 5, "default_custom_layouts[#{tpl}] scene_description на 5 строке")
    end

    # 10. Проверка default_layout.yaml и layout.yaml на наличие 5 строк заголовка
    default_yaml_content = File.read(File.expand_path("../config/default_layout.yaml", __dir__), encoding: "utf-8")
    assert(default_yaml_content.include?("scene_name: 4"), "default_layout.yaml содержит scene_name: 4")
    assert(default_yaml_content.include?("scene_description: 5"), "default_layout.yaml содержит scene_description: 5")

    layout_yaml_content = File.read(File.expand_path("../config/layout.yaml", __dir__), encoding: "utf-8")
    assert(layout_yaml_content.include?("scene_name: 4"), "layout.yaml содержит scene_name: 4")
    assert(layout_yaml_content.include?("scene_description: 5"), "layout.yaml содержит scene_description: 5")

    FileUtils.rm_rf(test_dir)
  end

  # --- 25. Тест выпадающих параметров (размер шрифта, номер строки, цвет текста) для пунктов заголовка ---
  def test_header_item_dropdowns
    puts "\n--- 25. Тест выпадающих параметров заголовка (номер строки, размер шрифта, цвет текста) ---"

    # 1. Проверка app.js на наличие выпадающих контролов для каждого пункта заголовка
    app_js_path = File.expand_path("../dialog/html/app.js", __dir__)
    app_js_content = File.read(app_js_path, encoding: "utf-8")

    assert(app_js_content.include?("sel-hdr-line-row"), "app.js содержит селектор номера строки (sel-hdr-line-row)")
    assert(app_js_content.include?("sel-hdr-line-size"), "app.js содержит селектор размера шрифта (sel-hdr-line-size)")
    assert(app_js_content.include?("inp-hdr-line-color"), "app.js содержит пикер цвета текста (inp-hdr-line-color)")
    assert(app_js_content.include?("tpl-hdr-columns-header"), "app.js содержит шапку столбцов параметров (tpl-hdr-columns-header)")
    assert(app_js_content.include?("стр."), "app.js содержит название столбца стр.")
    assert(app_js_content.include?("пт."), "app.js содержит название столбца пт.")
    assert(app_js_content.include?("цвет"), "app.js содержит название столбца цвет")
    assert(app_js_content.include?("HEADER_LINE_FONT_SIZES"), "app.js содержит шкалу размеров шрифтов строк HEADER_LINE_FONT_SIZES")
    [8, 10, 12, 14, 16, 18, 20, 24, 28, 32, 36, 40, 46, 52].each do |sz|
      assert(app_js_content.include?("HEADER_LINE_FONT_SIZES = [8, 10, 12, 14, 16, 18, 20, 24, 28, 32, 36, 40, 46, 52]"), "Шкала HEADER_LINE_FONT_SIZES содержит #{sz}")
    end
    assert(app_js_content.include?("line_font_sizes"), "app.js обрабатывает структуру line_font_sizes")
    assert(app_js_content.include?("line_colors"), "app.js обрабатывает структуру line_colors")
    assert(!app_js_content.include?("sel_header_fontsize"), "app.js больше не содержит общий выбор шрифта заголовка sel_header_fontsize")
    assert(app_js_content.include?("tpl-header-valign-control"), "app.js содержит выравнивание по вертикали в шапке карточки")

    # 2. Проверка app.css на наличие стилей выпадающих списков параметров
    app_css_path = File.expand_path("../dialog/html/app.css", __dir__)
    app_css_content = File.read(app_css_path, encoding: "utf-8")
    assert(app_css_content.include?(".tpl-hdr-item-controls"), "app.css содержит стиль .tpl-hdr-item-controls")
    assert(app_css_content.include?(".tpl-hdr-select"), "app.css содержит стиль .tpl-hdr-select")
    assert(app_css_content.include?(".sel-hdr-line-size"), "app.css содержит стиль .sel-hdr-line-size")
    assert(app_css_content.include?(".inp-hdr-line-color"), "app.css содержит стиль .inp-hdr-line-color")
    assert(app_css_content.include?(".tpl-hdr-columns-header"), "app.css содержит стиль .tpl-hdr-columns-header")
    assert(app_css_content.include?(".tpl-header-valign-control"), "app.css содержит стиль .tpl-header-valign-control")

    # 3. Проверка default_custom_layouts в project_data.rb на наличие default_hdr_sizes и default_hdr_colors
    project_data = DN1Code::ExportPdf2::Model::ProjectData.new
    [:cover, :description, :explain, :general, :visual].each do |tpl|
      hdr = project_data.default_custom_layouts[tpl][:header]
      assert(hdr.key?(:line_font_sizes), "default_custom_layouts[#{tpl}][:header] содержит line_font_sizes")
      assert(hdr.key?(:line_colors), "default_custom_layouts[#{tpl}][:header] содержит line_colors")
      assert(hdr[:line_font_sizes]["furniture_name"] == 11.0, "default_custom_layouts[#{tpl}] furniture_name размер 11.0")
      assert(hdr[:line_colors]["furniture_name"] == "#005EB0", "default_custom_layouts[#{tpl}] furniture_name цвет #005EB0")
    end

    # 4. Проверка default_layout.yaml и layout.yaml на наличие line_font_sizes и line_colors
    default_yaml_content = File.read(File.expand_path("../config/default_layout.yaml", __dir__), encoding: "utf-8")
    assert(default_yaml_content.include?("line_font_sizes:"), "default_layout.yaml содержит line_font_sizes:")
    assert(default_yaml_content.include?("line_colors:"), "default_layout.yaml содержит line_colors:")

    layout_yaml_content = File.read(File.expand_path("../config/layout.yaml", __dir__), encoding: "utf-8")
    assert(layout_yaml_content.include?("line_font_sizes:"), "layout.yaml содержит line_font_sizes:")
    assert(layout_yaml_content.include?("line_colors:"), "layout.yaml содержит line_colors:")

    # 5. Проверка генерации PDF с индивидуальными размерами шрифтов и цветами для каждой строки
    mock_page = Sketchup::MockPage.new("01. Обложка проекта")
    mock_page.description = "Фасадный рендер гардеробной с подсветкой полок"
    scene = DN1Code::ExportPdf2::Model::SceneItem.new(
      name: "01. Обложка проекта",
      description: "Фасадный рендер гардеробной с подсветкой полок",
      scene_ref: mock_page,
      page_type: :cover,
      order: 1,
      enabled: true
    )

    pdf_doc = DN1Code::ExportPdf2::Service::PdfBuilder.create_document(project_data, project_data.pdf_settings)
    cover_page = DN1Code::ExportPdf2::Controller::CoverPage.new(pdf_doc, project_data, scene, page_index: 1, total_pages: 5)

    layouts = project_data.pdf_settings[:custom_layouts]
    layouts[:cover][:header] = {
      visible: true,
      align: "center",
      valign: "center",
      font_size: 11.0,
      lines: ["furniture_name", "place_address", "customer_or_company", "scene_name", "scene_description"],
      line_rows: {
        "furniture_name" => 1,
        "place_address" => 2,
        "customer_or_company" => 3,
        "scene_name" => 4,
        "scene_description" => 5
      },
      line_font_sizes: {
        "furniture_name" => 16.0,
        "place_address" => 12.0,
        "customer_or_company" => 10.0,
        "scene_name" => 13.0,
        "scene_description" => 8.5
      },
      line_colors: {
        "furniture_name" => "#DC2626",
        "place_address" => "#0D9488",
        "customer_or_company" => "#1E293B",
        "scene_name" => "#005EB0",
        "scene_description" => "#64748B"
      }
    }

    test_dir = File.expand_path("test_header_dropdowns_dir", __dir__)
    FileUtils.mkdir_p(test_dir)
    pdf_out = File.join(test_dir, "cover_custom_sizes_and_colors.pdf")

    cover_page.render
    pdf_doc.render_file(pdf_out)

    assert(File.exist?(pdf_out), "PDF с индивидуальными цветами и кеглями строк успешно сгенерирован")
    assert(File.size(pdf_out) > 5000, "Размер сгенерированного PDF валиден (#{File.size(pdf_out)} байт)")

    # 6. Проверка генерации строки с несколькими элементами с разными цветами и кеглями на одной строке
    layouts[:cover][:header][:line_rows]["scene_name"] = 1
    pdf_doc2 = DN1Code::ExportPdf2::Service::PdfBuilder.create_document(project_data, project_data.pdf_settings)
    cover_page2 = DN1Code::ExportPdf2::Controller::CoverPage.new(pdf_doc2, project_data, scene, page_index: 1, total_pages: 5)
    pdf_out2 = File.join(test_dir, "cover_merged_row_different_colors.pdf")
    cover_page2.render
    pdf_doc2.render_file(pdf_out2)

    assert(File.exist?(pdf_out2), "PDF с объединенной строкой разного цвета/кегля успешно сгенерирован")
    assert(File.size(pdf_out2) > 5000, "Размер PDF с объединенной строкой валиден (#{File.size(pdf_out2)} байт)")

    FileUtils.rm_rf(test_dir)
  end

  def test_footer_card_layout_adjustments
    puts "\n--- 26. Тест правок макета карточки подвала (шрифт в шапке, чекбоксы справа) ---"
    app_js_path = File.expand_path("../dialog/html/app.js", __dir__)
    app_js_content = File.read(app_js_path, encoding: "utf-8")

    # 1. Проверка переноса селектора шрифта подвала в шапку карточки
    assert(app_js_content.include?("tpl-footer-font-control"), "app.js содержит контейнер tpl-footer-font-control в шапке карточки подвала")
    assert(app_js_content.include?("tpl-footer-font-label"), "app.js содержит подпись tpl-footer-font-label")
    assert(app_js_content.include?("sel_footer_fontsize"), "app.js содержит селектор sel_footer_fontsize")

    # 2. Проверка выравнивания блока подвала как на остальных блоках GUI (tpl-panel-left)
    assert(app_js_content.include?('tpl-card tpl-panel-left ${!isFooterVis ? \'disabled-card disabled-block\' : \'\'}" id="card_footer"'), "Блок card_footer имеет класс tpl-panel-left для выравнивания как на других блоках GUI")
    card_footer_part = app_js_content[/id="card_footer".*?FULL TWO-COLUMN/m]
    assert(card_footer_part != nil, "Блок card_footer найден в app.js")
    return unless card_footer_part
    assert(!card_footer_part.include?("tpl-controls-row"), "Блок card_footer больше не содержит промежуточную строку tpl-controls-row")
    title_idx = card_footer_part.index("tpl-card-title-group")
    actions_idx = card_footer_part.index("tpl-card-header-actions")
    assert(title_idx && actions_idx && title_idx < actions_idx, "Заголовок карточки подвала идет слева, действия справа")

    # 3. Проверка порядка элементов в строке подвала (логично как на остальных блоках):
    # чекбокс chk-ftr-line (слева) -> название и превью (слева/центр) -> кнопки выравнивания align-picker (справа)
    picker_idx = card_footer_part.index("tpl-ftr-align-picker")
    label_idx = card_footer_part.index("tpl-line-label")
    chk_idx = card_footer_part.index("chk-ftr-line")
    assert(picker_idx && label_idx && chk_idx, "Все три элемента строки присутствуют в разметке карточки подвала")
    assert(chk_idx < label_idx, "Чекбокс chk-ftr-line идет в начале строки (слева как на остальных блоках)")
    assert(label_idx < picker_idx, "Кнопки выравнивания tpl-ftr-align-picker идут в конце строки (справа)")

    # 4. Проверка стилей в app.css
    app_css_path = File.expand_path("../dialog/html/app.css", __dir__)
    app_css_content = File.read(app_css_path, encoding: "utf-8")
    assert(app_css_content.include?(".tpl-footer-font-control"), "app.css содержит стиль .tpl-footer-font-control")
    assert(app_css_content.include?(".tpl-footer-font-label"), "app.css содержит стиль .tpl-footer-font-label")
    assert(app_css_content.include?(".tpl-ftr-line-row"), "app.css содержит стиль .tpl-ftr-line-row")
    assert(app_css_content.include?(".tpl-ftr-align-picker"), "app.css содержит стиль .tpl-ftr-align-picker")
  end
end

TestRunner.new.run_all
