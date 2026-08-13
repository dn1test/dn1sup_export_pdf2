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

    # Модифицируем координаты блоков для обложки и описания
    settings[:custom_layouts][:cover][:cover_title] = { x: 5.0, y: 8.0, w: 90.0, h: 10.0, visible: true, align: "center" }
    settings[:custom_layouts][:cover][:cover_subtitle] = { x: 5.0, y: 19.0, w: 90.0, h: 5.0, visible: false, align: "center" }
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
    assert(loaded_layouts[:cover][:cover_title][:align] == "center" || loaded_layouts[:cover]["cover_title"]["align"] == "center", "Выравнивание заголовка обложки сохранено")

    # Тестируем экспорт PDF с кастомным макетом
    model = Sketchup::MockModel.new("U:/Projects/CustomLayout/LivingRoom.skp")
    model.pages.add("01. Титул")
    model.pages.add("02. Спецификации")
    loaded_data.project_info[:room_name] = "Гостиная"
    loaded_data.project_info[:furniture_name] = "Стенка ТВ"
    loaded_data.project_info[:materials] = "Шпон дуба, стекло матовое, ручки профиль"
    loaded_data.sync_with_model_scenes(model)

    pdf_out = File.expand_path("test_custom_layout_export.pdf", __dir__)
    File.delete(pdf_out) if File.exist?(pdf_out)

    controller = DN1Code::ExportPdf2::Controller::ExportController.new(loaded_data, model)
    result_pdf = controller.export(pdf_out)

    assert(File.exist?(result_pdf), "PDF с кастомной компоновкой блоков успешно сгенерирован")
    assert(File.size(result_pdf) > 20000, "Размер PDF с кастомным макетом валиден (#{File.size(result_pdf)} байт)")

    File.delete(yaml_temp) if File.exist?(yaml_temp)
    File.delete(pdf_out) if File.exist?(pdf_out)
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
    project_data.project_info[:name_project] = "Пентхаус на Мосфильмовской"
    project_data.project_info[:name_customer] = "Ковалев Дмитрий"
    project_data.project_info[:notes] = "Мрамор Calacatta, дубовый паркет Coswick, техника Miele."
    project_data.history << { date: "2026.08.10", description: "Утверждение планировки" }

    yaml_path = File.expand_path("test_project_config.yaml", __dir__)
    project_data.save_to_yaml(yaml_path)
    assert(File.exist?(yaml_path), "YAML файл конфигурации успешно создан на диске")

    loaded_yaml_data = DN1Code::ExportPdf2::Model::ProjectData.new
    loaded_yaml_data.load_from_yaml(yaml_path)
    assert(loaded_yaml_data.project_info[:name_project] == "Пентхаус на Мосфильмовской", "Имя проекта корректно загружено из YAML")
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
    project_data.project_info[:name_project] = "Кухня Модерн"
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
    project_data.project_info[:name_project] = "Кухня Без Артикула"
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
    model_data.project_info[:name_project] = "Имя из библиотеки модели"
    model_data.save_to_model(model)

    # 2. Создаем рядом файл BED-01.yaml с другим значением (внешнее редактирование)
    yaml_file = File.join(test_dir, "BED-01.yaml")
    yaml_data = DN1Code::ExportPdf2::Model::ProjectData.new
    yaml_data.project_info[:articul] = "BED-01"
    yaml_data.project_info[:name_project] = "Имя из файла YAML (Первично)"
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
end

TestRunner.new.run_all
