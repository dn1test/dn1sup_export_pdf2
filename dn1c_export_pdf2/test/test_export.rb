# frozen_string_literal: true

# -------------------------------------------------------------------------------
# Standalone Automated Test for DN1C Export PDF 2
# -------------------------------------------------------------------------------

require_relative "mock_sketchup"
require_relative "../main"

puts "=========================================================="
puts "  Запуск теста DN1C Export PDF 2"
puts "=========================================================="

# 1. Инициализация модели и сцен для теста
if defined?(Sketchup) && Sketchup.respond_to?(:version) && Sketchup.active_model
  # Внутри реального SketchUp используем текущую активную модель
  test_model = Sketchup.active_model
else
  # Вне SketchUp используем мок-модель во ВРЕМЕННОЙ папке: экспорт вызывает save_auto,
  # который пишет YAML рядом с .skp — путь в корне репозитория загрязнял бы рабочую копию
  require "tmpdir"
  require "fileutils"
  test_work_dir = File.join(Dir.tmpdir, "dn1c_test_export_#{Time.now.strftime('%Y%m%d_%H%M%S')}")
  FileUtils.mkdir_p(test_work_dir)
  test_model = Sketchup::MockModel.new(File.join(test_work_dir, "sample_model.skp"))
  scenes = [
    Sketchup::MockPage.new("01. Обложка", "Титульный лист проекта"),
    Sketchup::MockPage.new("02. Содержание и материалы", "Пояснительная записка и перечень спецификаций"),
    Sketchup::MockPage.new("03. Перспективный вид гостиной", "Визуализация интерьера в дневном освещении"),
    Sketchup::MockPage.new("04. План расстановки мебели", "Техническая схема с габаритными размерами")
  ]
  test_model.pages = Sketchup::MockPages.new(scenes)
end

# 2. Инициализация данных проекта
project_data = DN1Code::ExportPdf2::Model::ProjectData.new
project_data.project_info = {
  name_project:  "Дизайн-проект Апартаментов в Сити",
  description:   "Комплексный дизайн-проект интерьера с технической документацией",
  name_customer: "Петров Александр Сергеевич",
  phone:         "+7 (916) 123-45-67",
  email:         "petrov.alex@example.com",
  address:       "г. Москва, Пресненская наб., д. 8, башня 'Город Столиц', кв. 142",
  articul:       "CITY-2026-AP142",
  version:       1,
  revision:      3,
  status:        "НА СОГЛАСОВАНИИ",
  designer:      "DESTUDIONS Architecture",
  notes:         "Материалы:\n• Фасады: МДФ эмаль матовая RAL 9003\n• Столешница: Кварцевый агломерат Technistone 20мм\n• Фурнитура: Blum Legrabox soft-close\n• Подсветка: Светодиодная лента 3000K CRI>95"
}

project_data.pdf_settings = {
  page_size:       "A4",
  page_layout:     "landscape",
  margin:          15,
  scale_factor:    2.0,
  antialias:       true,
  stamp_type:      "draft",
  stamp_custom:    "НЕ УТВЕРЖДЕН",
  auto_open_pdf:   false,
  save_skp_backup: false,
  primary_color:   "005EB0",
  secondary_color: "64748B",
  stamp_color:     "D32F2F"
}

project_data.history = [
  { date: "2026.08.01", description: "Инициализация эскизного проекта" },
  { date: "2026.08.05", description: "Согласование планировочных решений" },
  { date: "2026.08.11", description: "Корректировка фасадов кухни и спецификаций" }
]

# Синхронизируем со сценами
project_data.sync_with_model_scenes(test_model)

# 3. Запуск контроллера экспорта
output_pdf = File.expand_path("test_output.pdf", __dir__)
File.delete(output_pdf) if File.exist?(output_pdf)

controller = DN1Code::ExportPdf2::Controller::ExportController.new(project_data, test_model)

puts "\nЗапуск генерации многостраничного PDF..."
result_path = controller.export(output_pdf) do |curr, total, msg|
  puts "  -> [#{curr}/#{total}] #{msg}"
end

# 4. Проверка результатов
if File.exist?(result_path) && File.size(result_path) > 1000
  file_size_kb = (File.size(result_path) / 1024.0).round(2)
  puts "\n[УСПЕХ] Тестовый PDF успешно сгенерирован!"
  puts "  Путь к файлу: #{result_path}"
  puts "  Размер файла: #{file_size_kb} KB"
  puts "=========================================================="
else
  abort "\n[ОШИБКА] PDF файл не был создан или имеет нулевой размер!"
end
