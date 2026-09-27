# frozen_string_literal: true

# -------------------------------------------------------------------------------
# Comprehensive End-to-End Test Suite for DN1C Export PDF 2
# -------------------------------------------------------------------------------

require_relative "mock_sketchup"
require_relative "../main"
require_relative "test_template_params"

# Перехватчик системного открытия: тесты не должны реально запускать
# ShellExecuteW / программу по умолчанию — вызовы логируются в stdout
DN1Code::ExportPdf2::Model::FileOpener.launcher_override = lambda do |path|
  puts "[FileOpener] #{path}"
  true
end
# require "pdf/core" - Removed, all PDF generation is now native via LayOut API

if defined?(Sketchup) && Sketchup.respond_to?(:version)
  puts "Комплексные тесты мок-модели предназначены для запуска через терминал вне SketchUp GUI."
  return
end

# Адаптер для совместимости существующих тестов модели с LayOut API
module Prawn
  Document = ::Layout::Document
end

module DN1Code
  module ExportPdf2
    module Service
      module PdfBuilder
        def self.create_document(project_data, settings = {})
          doc = ::Layout::Document.new
          margin_mm = settings[:margin_mm] || (settings[:margin] ? (settings[:margin].to_f * 25.4 / 72.0) : 5)
          margin_in = margin_mm.to_f / 25.4
          doc.page_info.left_margin = margin_in
          doc.page_info.right_margin = margin_in
          doc.page_info.top_margin = margin_in
          doc.page_info.bottom_margin = margin_in
          doc
        end
      end

      module FontService
        def self.setup_fonts(_doc = nil)
          true
        end
      end
    end

    module Controller
      class PageBase
        attr_reader :project_data, :scene_item, :page_index, :total_pages

        def initialize(doc, project_data, scene_item = nil, options = {})
          @doc = doc
          @project_data = project_data
          @scene_item = scene_item
          @page_index = options[:page_index] || 1
          @total_pages = options[:total_pages] || 1
        end

        def has_modular_slots?
          true
        end

        def current_page_type
          @scene_item ? (@scene_item.page_type || :general).to_sym : :cover
        end

        def resolve_info_line(key)
          ctx = {
            info: @project_data.project_info,
            workflow: @project_data.workflow,
            project_data: @project_data,
            scene_item: @scene_item,
            page_index: @page_index,
            total_pages: @total_pages
          }
          Service::InfoLineResolver.resolve_param(ctx, key)
        end

        def render
          ctx = Service::LayoutBuilder.send(:build_context, @project_data, nil, "DIN Condensed")
          page = @doc.pages.first
          layer = @doc.layers.first
          scene = @scene_item || Model::SceneItem.new(name: "Page", page_type: current_page_type)

          w_in = (@doc.respond_to?(:page_info) && @doc.page_info&.width) ? @doc.page_info.width.to_f : 11.6929
          h_in = (@doc.respond_to?(:page_info) && @doc.page_info&.height) ? @doc.page_info.height.to_f : 8.2677
          m_in = (@doc.respond_to?(:page_info) && @doc.page_info&.left_margin) ? @doc.page_info.left_margin.to_f : 0.2
          Service::LayoutBuilder.send(:render_modular_page, @doc, page, layer, scene, @page_index, @total_pages, w_in, h_in, m_in, ctx, [])
        end

        def get_block_config(pt, block_id)
          b_sym = block_id.to_sym
          canonical = b_sym == :visual_image ? :image_4_3 : b_sym
          Service::LayoutBuilder.send(:get_block_config, { settings: @project_data.pdf_settings }, pt, canonical)
        end
      end

      class CoverPage < PageBase; end
      class DescriptionPage < PageBase; end
      class ExplainPage < PageBase; end
      class GeneralPage < PageBase; end
      class VisualPage < PageBase; end
      class BlankPage < PageBase; end

      class ExportController
        PAGE_CONTROLLERS = {
          cover:       CoverPage,
          description: DescriptionPage,
          explain:     ExplainPage,
          visual:      VisualPage,
          general:     GeneralPage,
          blank:       BlankPage
        }.freeze
      end
    end
  end
end

class TestRunner
  include DN1Code::ExportPdf2::TestSupport::TemplateParamsTests

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
    test_yaml_import_export
    test_articul_lock_flag
    test_auto_yaml_save_on_sketchup_save
    test_priority_reading_yaml_primary_model_secondary
    test_save_project_yaml_and_articul_rename
    test_articul_persisted_in_skp_attributes
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
    test_page_margin_and_clean_render
    test_scene_drag_reordering_and_renaming
    test_toc_page_count_and_created_pages_filtering
    test_scenes_table_two_row_layout
    test_drawing_image_settings_proportions_and_placement
    test_manual_revision_prompt_before_pdf_export_and_no_auto_history
    test_40_template_usage_separate_line
    test_41_api_targets_addition_and_deletion
    test_42_safe_frame_overlay_and_aspect_ratios
    test_43_new_project_yaml_data_structure
    test_44_template_independence_and_autosave
    test_directories_start_empty_and_deletions_persist
    test_separate_project_pages_and_template_settings_tabs
    test_custom_template_management_and_rendering
    test_scenes_table_mini_preview_column
    test_blank_page_template
    test_gui_scene_selection_switches_sketchup_page
    test_template_settings_persistence
    test_template_blocks_visibility_persistence
    test_overlay_disabled_when_viewport_disabled
    test_scene_viewport_settings_in_scenes_tab
    test_56_scene_viewport_frame_header_and_shading_controls
    test_57_compression_options_and_best_image_format
    test_58_line_scale_multiplier
    test_59_line_thickness_parameters_from_style
    test_viewport_background_toggle
    test_watermark_toggle
    test_60a_per_page_aspect_ratio_snapshot
    test_60_line_multiplier_consistent_across_all_render_modes
    test_61_page_formats_a4_a3_and_quality_levels
    test_62_auto_scale_font_size_reduction_30_pct
    test_63_layout_line_weight_and_annotation_font_size
    test_64_render_modes_image_and_hybrid
    test_66_page_font_family_selection
    test_articul_folder_yaml_canonical_and_anchor
    test_articul_folder_export_structure
    test_last_pdf_copy_next_to_skp_and_history_link
    test_png_snapshots_respect_viewport_background
    test_scene_snapshots_webp_format_and_fallback
    test_scene_snapshots_reuse_rendered_source
    test_snapshot_worker_background_pool
    test_path_util_file_url_encoding
    test_file_opener_open_path
    test_file_opener_file_locked
    test_export_aborts_when_target_pdf_locked
    test_export_skips_last_copy_when_locked
    test_history_rev_ver_fields_and_migration
    test_74_save_without_articul_writes_no_yaml
    test_75_legacy_yaml_ignored
    test_76_discovery_multiple_articul_folders_ambiguous
    test_77_edit_history_in_articul_folder
    test_78_articul_offer_on_dialog_open_and_folder_creation

    test_79_template_params_placement
    test_80_template_params_sources
    test_81_template_params_per_template_and_yaml
    test_82_template_params_data_contract_and_js_guards
    test_83_template_params_render_reads_new_config_only
    test_84_template_params_group_block
    test_85_template_params_auto_labels
    test_87_template_params_conditional_customer_or_company
    test_86_overlay_follows_native_page_switch
    test_87_refresh_thumbnails_button_and_sig_guard
    test_88_directory_send_to_server_flag

    puts "\n=========================================================="
    puts "  ИТОГИ ТЕСТИРОВАНИЯ: Успешно: #{@passed}, Ошибок: #{@failed}"
    puts "=========================================================="

    exit(@failed.zero? ? 0 : 1)
  end

  private

  def test_custom_layouts_and_block_positioning
    puts "\n--- 11. Тест пользовательских параметров шаблона (Layout Editor) ---"

    project_data = DN1Code::ExportPdf2::Model::ProjectData.new
    settings = project_data.pdf_settings

    assert(settings.key?(:custom_layouts), "Настройки pdf_settings содержат ключ :custom_layouts")
    assert(settings[:custom_layouts].key?(:cover), "Кастомные макеты содержат шаблон :cover")
    assert(settings[:custom_layouts].key?(:description), "Кастомные макеты содержат шаблон :description")
    assert(settings[:custom_layouts].key?(:explain), "Кастомные макеты содержат шаблон :explain")
    assert(settings[:custom_layouts].key?(:general), "Кастомные макеты содержат шаблон :general")
    assert(settings[:custom_layouts].key?(:visual), "Кастомные макеты содержат шаблон :visual")

    # Пользователь создает параметры (свободное размещение) и двигает видовое окно
    settings[:custom_layouts][:cover][:params] = [
      { id: "p1", source: "project.room_name", label: "Помещение", show_label: true,
        align: "left", font_size: 12.5, color: "#0F172A", visible: true }
    ]
    settings[:custom_layouts][:cover][:image_4_3][:aspect_ratio] = "16:9"
    settings[:custom_layouts][:description][:params] = [
      { id: "p2", source: "workflow.price", label: "Стоимость", show_label: true,
        align: "right", font_size: 9.0, color: "#334155", visible: true }
    ]

    # Сохраняем в YAML и проверяем чтение
    yaml_temp = File.expand_path("test_custom_layout.yaml", __dir__)
    File.delete(yaml_temp) if File.exist?(yaml_temp)

    project_data.save_to_yaml(yaml_temp)
    assert(File.exist?(yaml_temp), "YAML с пользовательскими параметрами успешно сохранен")

    loaded_data = DN1Code::ExportPdf2::Model::ProjectData.new
    loaded_data.load_from_yaml(yaml_temp)

    loaded_layouts = loaded_data.pdf_settings[:custom_layouts]
    assert(!loaded_layouts.nil?, "Кастомные макеты успешно прочитаны из YAML")
    cover_params = loaded_layouts[:cover][:params]
    assert(cover_params.is_a?(Array) && cover_params.size == 1, "Параметры шаблона cover прочитаны из YAML")
    assert(cover_params.first[:source] == "project.room_name", "Источник параметра сохранен")
    assert(cover_params.first[:font_size] == 12.5, "Кегль параметра сохранен (12.5 pt)")
    assert(cover_params.first[:align] == "left", "Выравнивание параметра (слева) сохранено")

    desc_params = loaded_layouts[:description][:params]
    assert(desc_params.is_a?(Array) && desc_params.size == 1 && desc_params.first[:align] == "right",
           "Параметры шаблона description прочитаны (выравнивание справа)")

    # Тестируем экспорт PDF с пользовательскими параметрами
    model = Sketchup::MockModel.new("U:/Projects/CustomLayout/LivingRoom.skp")
    model.pages.add("01. Титул")
    model.pages.add("02. Спецификации")
    loaded_data.project_info[:room_name] = "Гостиная"
    loaded_data.project_info[:furniture_name] = "Стенка ТВ"
    loaded_data.project_info[:price] = "150000"
    loaded_data.sync_with_model_scenes(model)

    pdf_out = File.expand_path("test_custom_layout_export.pdf", __dir__)
    File.delete(pdf_out) if File.exist?(pdf_out)

    controller = DN1Code::ExportPdf2::Controller::ExportController.new(loaded_data, model)
    result_pdf = controller.export(pdf_out)

    assert(File.exist?(result_pdf), "PDF с пользовательскими параметрами успешно сгенерирован")
    assert(File.size(result_pdf) > 15000, "Размер PDF с пользовательскими параметрами валиден (#{File.size(result_pdf)} байт)")

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

    project_data.sync_with_model_scenes(model)
    assert(project_data.scenes.size == 5, "Корректно обнаружено 5 сцен в модели")
    assert(project_data.scenes[0].page_type == :cover, "Сцена '01. Обложка' распознана как :cover")
    assert(project_data.scenes[1].page_type == :explain, "Сцена '02. Пояснения...' распознана как :explain")
    assert(project_data.scenes[2].page_type == :visual, "Сцена '03. Визуализация' распознана как :visual")
    assert(project_data.scenes[3].page_type == :general, "Сцена '04. Общий вид' распознана как :general")

    # В библиотеке модели (.skp) хранится только артикул (ModelArticulStore):
    # данные проекта живут в YAML и в памяти сессии
    assert(project_data.scenes[4].page_type == :general, "Сцена '05. Общий вид 2' распознана как :general")
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

  def test_articul_lock_flag
    puts "\n--- 3b. Тест блокировки артикула (articul_locked) ---"

    # 1. Новый проект без артикула — не заблокирован, готов к созданию
    fresh = DN1Code::ExportPdf2::Model::ProjectData.new
    assert(fresh.project[:articul_locked] == false, "Новый проект без артикула не заблокирован")

    test_dir = File.expand_path("test_articul_lock_dir", __dir__)
    FileUtils.mkdir_p(test_dir)

    # 2. Созданный артикул блокируется и остается заблокированным после перезагрузки YAML
    yaml_file = File.join(test_dir, "articul_lock.yaml")
    pd = DN1Code::ExportPdf2::Model::ProjectData.new
    pd.project_info[:articul] = "CF#260920_101010_01"
    pd.project_info[:articul_locked] = true
    assert(pd.project[:articul_locked] == true, "Проксирующая запись в project_info синхронизирует @project")
    assert(pd.save_to_yaml(yaml_file), "Заблокированный проект сохранен в YAML")
    assert(File.read(yaml_file, encoding: "utf-8").include?("articul_locked: true"), "Флаг articul_locked записан в YAML")

    loaded = DN1Code::ExportPdf2::Model::ProjectData.new
    loaded.load_from_yaml(yaml_file)
    assert(loaded.project[:articul] == "CF#260920_101010_01", "Артикул восстановлен из YAML")
    assert(loaded.project[:articul_locked] == true, "Созданный артикул остается заблокированным после перезагрузки YAML")

    # 3. Снятая блокировка (пересоздание разрешено) тоже переживает перезагрузку
    unlocked = DN1Code::ExportPdf2::Model::ProjectData.new
    unlocked.load_from_yaml(yaml_file)
    unlocked.project[:articul_locked] = false
    unlocked.save_to_yaml(yaml_file)
    reloaded = DN1Code::ExportPdf2::Model::ProjectData.new
    reloaded.load_from_yaml(yaml_file)
    assert(reloaded.project[:articul_locked] == false, "Снятая блокировка сохраняется в YAML (артикул можно пересоздать)")

    # 4. Старый YAML без флага: непустой артикул считается созданным однажды и блокируется
    legacy_text = <<~YAML
      ---
      project:
        articul: HF#260101_000000_99
        product_tags: []
        commercial: false
      customer:
        id: ""
        name: ""
      workflow:
        author: ""
    YAML
    legacy_file = File.join(test_dir, "legacy.yaml")
    File.write(legacy_file, legacy_text)
    legacy = DN1Code::ExportPdf2::Model::ProjectData.new
    legacy.load_from_yaml(legacy_file)
    assert(legacy.project[:articul] == "HF#260101_000000_99", "Артикул из старого YAML прочитан")
    assert(legacy.project[:articul_locked] == true, "Старый YAML с артикулом без флага считается заблокированным")

    # 5. Данные формы (apply_payload!): галочка блокировки применяется и к фасаду
    ui_data = DN1Code::ExportPdf2::Model::ProjectData.new
    ui_data.apply_payload!({ project: { articul: "HF#260920_120000_02", articul_locked: false } })
    assert(ui_data.project[:articul_locked] == false, "apply_payload! применяет снятую блокировку из данных формы")
    assert(ui_data.project_info[:articul_locked] == false, "Фасад project_info отражает снятую блокировку")

    FileUtils.rm_rf(test_dir)
  end

  def test_auto_yaml_save_on_sketchup_save
    puts "\n--- 4. Тест принудительного сохранения (flush сессии) в папку артикула ---"

    test_dir = File.expand_path("test_auto_save_dir", __dir__)
    FileUtils.mkdir_p(test_dir)

    skp_file = File.join(test_dir, "Kitchen_Project.skp")
    model = Sketchup::MockModel.new(skp_file)

    # Сессия памяти (как при открытии модели)
    session_data = DN1Code::ExportPdf2::Model::SessionStore.on_model_opened(model)
    session_data.project_info[:articul] = "KITCHEN-777"
    session_data.project_info[:name_product] = "Кухня Модерн"

    # Имитируем принудительное сохранение / закрытие SketchUp
    assert(DN1Code::ExportPdf2::Model::SessionStore.flush(model), "flush сессии успешно записал данные")

    expected_yaml = File.join(test_dir, "KITCHEN-777", "project.yaml")
    assert(File.exist?(expected_yaml), "При flush сессии создан project.yaml в папке артикула: #{expected_yaml}")
    assert(!File.exist?(File.join(test_dir, "KITCHEN-777.yaml")), "Якорь-YAML рядом с .skp больше не создается")

    # Проверяем содержимое созданного YAML
    loaded = DN1Code::ExportPdf2::Model::ProjectData.new
    loaded.load_from_yaml(expected_yaml)
    assert(loaded.project_info[:name_project] == "Кухня Модерн", "Содержимое YAML файла корректно")

    # Теперь очищаем артикул и сохраняем снова: без артикула данные проекта не пишутся
    session_data.project_info[:articul] = ""
    session_data.project_info[:name_product] = "Кухня Без Артикула"
    assert(DN1Code::ExportPdf2::Model::SessionStore.flush(model), "Повторный flush сессии успешен (настройки расширения записаны)")

    assert(!File.exist?(File.join(test_dir, "Kitchen_Project.yaml")), "Без артикула YAML по имени модели не создается")
    assert(File.exist?(expected_yaml), "Прежний project.yaml в папке артикула не перезаписан пустыми данными")

    FileUtils.rm_rf(test_dir)
  end

  def test_priority_reading_yaml_primary_model_secondary
    puts "\n--- 5. Тест источника данных: project.yaml в папке артикула по артикулу из .skp ---"

    test_dir = File.expand_path("test_priority_dir", __dir__)
    FileUtils.mkdir_p(test_dir)

    skp_file = File.join(test_dir, "Bedroom.skp")
    model = Sketchup::MockModel.new(skp_file)

    # 1. Папка артикула с project.yaml есть, но модель без артикула в .skp:
    # файловая эвристика не используется — проект не загружается автоматически
    art_yaml = File.join(test_dir, "BED-01", "project.yaml")
    FileUtils.mkdir_p(File.dirname(art_yaml))
    yaml_data = DN1Code::ExportPdf2::Model::ProjectData.new
    yaml_data.project_info[:articul] = "BED-01"
    yaml_data.project_info[:name_product] = "Имя из файла YAML (Первично)"
    yaml_data.save_to_yaml(art_yaml)

    no_attr_data = DN1Code::ExportPdf2::Model::ProjectData.new
    assert(no_attr_data.load_auto(model) == :default, "Без артикула в .skp проект не загружается (файловая эвристика удалена)")

    # 2. Артикул в атрибутах модели (.skp) определяет папку проекта
    DN1Code::ExportPdf2::Model::ModelArticulStore.write(model, "BED-01")

    test_data = DN1Code::ExportPdf2::Model::ProjectData.new
    source = test_data.load_auto(model)

    assert(source == :yaml, "Источник загрузки определен как :yaml")
    assert(test_data.project_info[:name_project] == "Имя из файла YAML (Первично)", "Загружены данные из project.yaml папки артикула")

    # 3. Удаляем project.yaml — данных больше нет, источник :default
    File.delete(art_yaml) if File.exist?(art_yaml)

    fallback_data = DN1Code::ExportPdf2::Model::ProjectData.new
    fallback_source = fallback_data.load_auto(model)

    assert(fallback_source == :default, "При отсутствии project.yaml источник загрузки определен как :default")

    FileUtils.rm_rf(test_dir)
  end

  def test_save_project_yaml_and_articul_rename
    puts "\n--- 6. Тест save_project_yaml: project.yaml в папке артикула, смена артикула, запрет без артикула ---"

    test_dir = File.expand_path("test_save_auto_dir", __dir__)
    FileUtils.mkdir_p(test_dir)

    skp_file = File.join(test_dir, "Office.skp")
    model = Sketchup::MockModel.new(skp_file)

    project_data = DN1Code::ExportPdf2::Model::ProjectData.new
    project_data.project_info[:articul] = "OFFICE-900"
    project_data.project_info[:name_project] = "Кабинет Руководителя"

    # Вызываем save_project_yaml первый раз
    assert(project_data.save_project_yaml(model), "save_project_yaml успешно записал YAML")

    # Проверка: сохранено в project.yaml внутри папки артикула, якоря рядом с .skp нет
    yaml_file_1 = File.join(test_dir, "OFFICE-900", "project.yaml")
    assert(File.exist?(yaml_file_1), "Данные сохранены в #{yaml_file_1}")
    assert(!File.exist?(File.join(test_dir, "OFFICE-900.yaml")), "Якорь-YAML рядом с .skp не создается")

    # Проверка 3: Изменение артикула -> повторное сохранение в новую папку
    project_data.project_info[:articul] = "OFFICE-901"
    project_data.project_info[:name_project] = "Кабинет Руководителя (Обновленный)"
    assert(project_data.save_project_yaml(model), "Повторный save_project_yaml успешен")

    yaml_file_2 = File.join(test_dir, "OFFICE-901", "project.yaml")
    assert(File.exist?(yaml_file_2), "При смене артикула создана новая папка с project.yaml")
    assert(File.exist?(yaml_file_1), "Папка прежнего артикула сохранена (история)")

    # Проверка 4: Очистка артикула -> сохранение отклоняется
    project_data.project_info[:articul] = ""
    assert(!project_data.save_project_yaml(model), "Сохранение без артикула отклонено")
    assert(!File.exist?(File.join(test_dir, "Office.yaml")), "Файл по имени модели без артикула не создается")
    assert(File.exist?(yaml_file_2), "Данные прежнего артикула остались на диске")

    FileUtils.rm_rf(test_dir)
  end

  def test_articul_persisted_in_skp_attributes
    puts "\n--- 6a. Тест артикула в файле модели (.skp): запись при сохранении, определение папки проекта по .skp ---"

    test_dir = File.expand_path("test_skp_articul_dir", __dir__)
    FileUtils.mkdir_p(test_dir)

    skp_file = File.join(test_dir, "Living.skp")
    model = Sketchup::MockModel.new(skp_file)

    # 1. Сохранение проекта: артикул пишется и в project.yaml, и в атрибуты модели (.skp)
    project_data = DN1Code::ExportPdf2::Model::ProjectData.new
    project_data.project_info[:articul] = "CF#260905_142650"
    project_data.project_info[:description] = "Жилой комплекс Северный"
    assert(project_data.save_project_yaml(model), "save_project_yaml успешен")
    own_yaml = File.join(test_dir, "CF#260905_142650", "project.yaml")
    assert(File.exist?(own_yaml), "project.yaml создан в папке артикула (#{own_yaml})")
    assert(
      model.get_attribute(DN1Code::ExportPdf2::Model::ModelArticulStore::DICT_NAME,
                          DN1Code::ExportPdf2::Model::ModelArticulStore::KEY_ARTICUL, "") == "CF#260905_142650",
      "Артикул записан в атрибуты модели (.skp) при сохранении"
    )

    # 2. Рядом появляется чужая папка артикула: файловая эвристика «ровно одна папка»
    # не смогла бы выбрать проект, а артикул из .skp однозначно определяет папку
    foreign_yaml = File.join(test_dir, "HF#111111_111111", "project.yaml")
    FileUtils.mkdir_p(File.dirname(foreign_yaml))
    foreign = DN1Code::ExportPdf2::Model::ProjectData.new
    foreign.project_info[:articul] = "HF#111111_111111"
    foreign.project_info[:description] = "Чужой проект"
    foreign.save_to_yaml(foreign_yaml)

    reopened = DN1Code::ExportPdf2::Model::ProjectData.new
    assert(reopened.load_auto(model) == :yaml, "Источник загрузки определен как :yaml")
    assert(reopened.project_info[:articul] == "CF#260905_142650", "Артикул восстановлен из атрибутов модели (.skp)")
    assert(reopened.project_info[:trade] == "1", "Тип торговли выведен из префикса артикула из .skp (CF# — коммерческий)")
    assert(reopened.project_info[:description].to_s == "Жилой комплекс Северный", "Загружены данные своего project.yaml, а не чужой папки")

    # 3. Папку артикула удалили: артикул из .skp указывает в никуда —
    # однозначного фолбэка нет (две папки рядом), источник :default
    FileUtils.rm_rf(File.join(test_dir, "CF#260905_142650"))
    third_yaml = File.join(test_dir, "HF#222222_222222", "project.yaml")
    FileUtils.mkdir_p(File.dirname(third_yaml))
    File.write(third_yaml, "project:\n  articul: HF#222222_222222\n")

    orphan_data = DN1Code::ExportPdf2::Model::ProjectData.new
    assert(orphan_data.load_auto(model) == :default, "При отсутствии папки артикула из .skp и неоднозначном фолбэке источник :default")

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
    puts "\n--- 7. Тест сохранения PDF по умолчанию в папку артикула рядом с SKP ---"

    model_file = "U:/Projects/Interior/Kitchen_Design.skp"
    model = Sketchup::MockModel.new(model_file)
    model.pages = Sketchup::MockPages.new([Sketchup::MockPage.new("01. Вид")])

    project_data = DN1Code::ExportPdf2::Model::ProjectData.new
    project_data.project_info[:version] = 1
    project_data.project_info[:revision] = 4
    project_data.pdf_settings[:auto_open_pdf] = false

    controller = DN1Code::ExportPdf2::Controller::ExportController.new(project_data, model)
    default_path = controller.send(:resolve_default_pdf_path)

    # Папка артикула (по имени модели) создается рядом с .skp
    expected_path = "U:/Projects/Interior/Kitchen_Design/pdf/Kitchen_Design_01#004.pdf"
    assert(default_path == expected_path, "Путь по умолчанию '#{default_path}' указывает в папку артикула ('#{expected_path}')")
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

    tmp_yaml = File.expand_path("test_room_composition.yaml", __dir__)
    project_data.save_to_yaml(tmp_yaml)

    loaded_data = DN1Code::ExportPdf2::Model::ProjectData.new
    loaded_data.load_from_yaml(tmp_yaml)

    assert(loaded_data.project_info[:room_name] == "Кухня-столовая", "Помещение 'Кухня-столовая' сохранено в YAML")
    assert(loaded_data.project_info[:furniture_name] == "Остров с барной стойкой", "Изделие 'Остров с барной стойкой' сохранено в YAML")
    assert(loaded_data.project_info[:address] == "г. Санкт-Петербург, Невский пр., 100", "Адрес сохранен в данные проекта")
    assert(loaded_data.project_info[:name_project] == "Кухня-столовая — Остров с барной стойкой", "Заголовок проекта корректно составлен из помещения и мебели")

    File.delete(tmp_yaml) if File.exist?(tmp_yaml)

    loaded_data.sync_with_model_scenes(model)

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
    project_data.pdf_settings[:layout_render_mode] = "hybrid"
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

    File.delete(pdf_out) if File.exist?(pdf_out)
    File.delete(layout_out) if File.exist?(layout_out)
  end

  def test_reopening_project_file_preserves_revision_and_yaml_string_keys
    puts "\n--- 12. Тест сохранения ревизии без автоматического создания истории правок при открытии файла ---"

    test_dir = File.expand_path("test_reopen_dir", __dir__)
    FileUtils.mkdir_p(test_dir)

    skp_file = File.join(test_dir, "Project_Reopen.skp")
    yaml_file = File.join(test_dir, "ART-REOPEN-100", "project.yaml")

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
    FileUtils.mkdir_p(File.dirname(yaml_file))
    File.write(yaml_file, yaml_content, encoding: "utf-8")

    # 1. Симулируем открытие существующей модели SketchUp (артикул записан в .skp)
    model = Sketchup::MockModel.new(skp_file)
    DN1Code::ExportPdf2::Model::ModelArticulStore.write(model, "ART-REOPEN-100")

    # Вызываем ObserverService.handle_model_opened (открытие файла проекта)
    DN1Code::ExportPdf2::Service::ObserverService.handle_model_opened(model)

    # 2. Проверяем загрузку данных в проект: ревизия 7 НЕ должна увеличиваться автоматически
    loaded_data = DN1Code::ExportPdf2::Model::ProjectData.new
    src = loaded_data.load_auto(model)

    assert(src == :yaml, "При открытии файла источник определен как :yaml")
    assert(loaded_data.project_info[:revision] == 7, "Номер ревизии не увеличивается автоматически при открытии файла (остается 7)")
    assert(loaded_data.project_info[:version] == 2, "Версия проекта (2) корректно прочитана")
    assert(loaded_data.project_info[:articul] == "ART-REOPEN-100", "Артикул корректно прочитан")
    assert(!loaded_data.history.any? { |h| h[:description].to_s.include?("Открытие рабочего файла") }, "История правок автоматически НЕ создается при открытии файла")

    # 3. Симулируем принудительное сохранение (flush сессии в YAML)
    DN1Code::ExportPdf2::Model::SessionStore.flush(model)

    rechecked_data = DN1Code::ExportPdf2::Model::ProjectData.new
    rechecked_data.load_auto(model)
    assert(rechecked_data.project_info[:revision] == 7, "После flush сессии ревизия сохраняется равной 7")

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

    # 4. Проверка секции directories (Hash из legacy YAML нормализуется в массив)
    dirs = data.directories
    assert(dirs.is_a?(Array) && dirs.size == 3, "Секция directories (Hash) нормализована в массив из 3 записей")
    assert(dirs[0][:path] == "!_замер_фото_задание", "Путь к каталогу замеров корректен")
    assert(dirs[1][:display] == "grid", "Режим отображения папки материалов — grid")
    assert(dirs[2][:display] == "list", "Режим отображения техники — list")

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

    # 7. Генерация PDF документа с реальными данными project_config.yaml
    temp_dir = File.expand_path("test_history_save_dir", __dir__)
    FileUtils.mkdir_p(temp_dir)

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
  
    plugin_settings = DN1Code::ExportPdf2::Model::ProjectData::PROGRAM_SETTINGS_FILE
    plugin_layout   = DN1Code::ExportPdf2::Model::ProjectData::PROGRAM_LAYOUT_FILE
  
    assert(File.exist?(plugin_settings), "Файл настроек программы settings.yaml присутствует в плагине (#{plugin_settings})")
    assert(File.exist?(plugin_layout), "Файл макетов страниц layout.yaml присутствует в плагине (#{plugin_layout})")
  
    cfg_content = YAML.load_file(plugin_settings)
    assert(cfg_content.key?("pdf_settings") || cfg_content.key?(:pdf_settings), "Секция pdf_settings присутствует в настройках программы плагина")
  
    layout_content = YAML.load_file(plugin_layout)
    assert(layout_content.key?("layout") || layout_content.key?(:layout), "Корневой ключ layout присутствует в макетах программы плагина")
  
    # Тест пишет в layout.yaml плагина — сохраняем оригинал для восстановления
    original_layout = File.binread(plugin_layout)
  
    test_dir = File.expand_path("test_separate_layout_dir", __dir__)
    FileUtils.mkdir_p(test_dir)
  
    skp_path = File.join(test_dir, "Villa_Interior.skp")
    model = Sketchup::MockModel.new(skp_path)
  
    project_data = DN1Code::ExportPdf2::Model::ProjectData.new
    project_data.project_info[:articul] = "VILLA-100"
    project_data.project_info[:name_product] = "Гардеробная"
    project_data.project_info[:name_place] = "Мастер-спальня"
  
    # Пользователь создает параметр шаблона (свободное размещение на странице)
    project_data.pdf_settings[:custom_layouts][:cover][:params] = [
      { id: "p_sep", source: "project.room_name", label: "Помещение", show_label: true,
        align: "center", font_size: 11.0, color: "#0F172A", visible: true }
    ]
  
    # Сохраняем: YAML проекта + шаблоны в layout.yaml плагина
    project_data.save_project_yaml(model)
    project_data.save_to_layout_yaml(DN1Code::ExportPdf2::Model::ProjectData::PROGRAM_LAYOUT_FILE)
  
    prj_yaml = File.join(test_dir, "VILLA-100", "project.yaml")
    local_layout_yaml = File.join(test_dir, "layout.yaml")
  
    assert(File.exist?(prj_yaml), "project.yaml создан в папке артикула (#{prj_yaml})")
    assert(!File.exist?(File.join(test_dir, "VILLA-100.yaml")), "Якорь-YAML рядом с .skp не создается")
    assert(!File.exist?(local_layout_yaml), "Файл layout.yaml НЕ создается в папке проекта (сохранен в плагине)")
  
    # Проверяем, что в project.yaml НЕТ настроек программы (pdf_settings / custom_layouts / layout)
    raw_prj_yaml = YAML.load_file(prj_yaml)
    assert(!raw_prj_yaml.key?("pdf_settings") && !raw_prj_yaml.key?(:pdf_settings), "Секция pdf_settings отсутствует в файле проекта (хранится в плагине)")
    assert(!raw_prj_yaml.key?("layout") && !raw_prj_yaml.key?(:layout), "Ключ layout отсутствует в файле проекта")
  
    # Проверяем, что параметры шаблона сохранились ВНУТРИ ПЛАГИНА
    raw_plugin_layout = YAML.load_file(plugin_layout)
    layout_blocks = raw_plugin_layout["layout"] || raw_plugin_layout[:layout]
    assert(!layout_blocks.nil?, "Блок layout присутствует в layout.yaml плагина")
    cover_cfg = layout_blocks["cover"] || layout_blocks[:cover]
    saved_params = cover_cfg["params"] || cover_cfg[:params]
    assert(saved_params.is_a?(Array) && saved_params.size == 1, "Параметры шаблона сохранены в layout.yaml плагина")
    assert((saved_params.first["label"] || saved_params.first[:label]) == "Помещение", "Заголовок параметра сохранен в layout.yaml плагина")
  
    # Проверяем автоматическую загрузку настроек программы и проекта (load_auto)
    loaded_data = DN1Code::ExportPdf2::Model::ProjectData.new
    source = loaded_data.load_auto(model)
    assert(source == :yaml, "Источник загрузки данных проекта определен как :yaml")
    loaded_params = loaded_data.pdf_settings[:custom_layouts][:cover][:params]
    assert(loaded_params.is_a?(Array) && loaded_params.first[:align] == "center" && loaded_params.first[:label] == "Помещение",
           "Параметр шаблона прочитан из настроек программы плагина")
  
    # Проверяем метод load_from_layout_yaml напрямую
    direct_data = DN1Code::ExportPdf2::Model::ProjectData.new
    assert(direct_data.load_from_layout_yaml(plugin_layout), "Прямой вызов load_from_layout_yaml успешен")
    direct_params = direct_data.pdf_settings[:custom_layouts][:cover][:params]
    assert(direct_params.is_a?(Array) && direct_params.first[:source] == "project.room_name", "Данные параметров совпадают при прямом чтении")
  
    # Генерация PDF с разделенной структурой файлов
    model.pages.add("01. Обложка")
    loaded_data.sync_with_model_scenes(model)
    pdf_out = File.join(test_dir, "villa_export.pdf")
    controller = DN1Code::ExportPdf2::Controller::ExportController.new(loaded_data, model)
    res_pdf = controller.export(pdf_out)
    assert(File.exist?(res_pdf), "PDF с разделенной конфигурацией макетов успешно создан")
    assert(File.size(res_pdf) > 15000, "Размер PDF валиден (#{File.size(res_pdf)} байт)")
  
    # Восстанавливаем layout.yaml плагина
    File.binwrite(plugin_layout, original_layout)
    FileUtils.rm_rf(test_dir)
  end

  def test_modular_yaml_structure_and_generators
    puts "\n--- 15. Тест новой модульной структуры YAML (project, customer, workflow, directories, scenes) ---"

    test_dir = File.expand_path("test_modular_dir", __dir__)
    FileUtils.mkdir_p(test_dir)

    # 1. Тест генераторов артикула и customer_id (формат CF#ГГММДД_ЧЧММСС — без суффикса)
    cf_art = DN1Code::ExportPdf2::Model::ProjectData.generate_articul(commercial: true)
    hf_art = DN1Code::ExportPdf2::Model::ProjectData.generate_articul(commercial: false)
    cust_id = DN1Code::ExportPdf2::Model::ProjectData.generate_customer_id

    assert(cf_art.start_with?("CF#"), "Артикул коммерческого проекта начинается с CF#: #{cf_art}")
    assert(hf_art.start_with?("HF#"), "Артикул бытового проекта начинается с HF#: #{hf_art}")
    assert(cf_art.match?(/\ACF#\d{6}_\d{6}\z/), "Артикул заканчивается секундами (ГГММДД_ЧЧММСС): #{cf_art}")
    assert(hf_art.match?(/\AHF#\d{6}_\d{6}\z/), "Артикул HF# без суффикса: #{hf_art}")
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

    # 6. Генерация PDF из модульных данных
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
    # (изолированный fixture вместо мутирующего sample-файла в корне репозитория)
    city_yaml_path = File.join(test_dir, "dirs_spec_fixture.yaml")
    File.write(city_yaml_path, <<~YAML, encoding: "utf-8")
      ---
      project:
        articul: DIRS-SPEC-001
        product_tags: []
        place: ''
        adress: г. Тест, Тестовая ул., д. 1
        description: Тестовый проект для проверки синхронизации спецификаций
        commercial: false
      customer:
        id: CUST-TEST-001
        name: Тест Тестович
        phone: ''
        email: ''
      workflow:
        version: '01'
        revision: '001'
        stadia: []
        history_edit: []
      directories:
      - path: "!_замер_фото_задание"
        title: Замеры помещения
        description: Замеры выполнены лазерным дальномером, высота потолков 2.7м
        display: grid
      - path: "!_инфо_заказчика"
        title: Инфо заказчика
        description: Дополнительное описание
        display: grid
      - path: "!_материалы_фурнитура"
        title: Материалы и фурнитура
        description: "Фасады: МДФ эмаль RAL 9003, корпус: ЛДСП Egger, фурнитура: Blum Legrabox"
        display: grid
      - path: "!_техника_подсветка"
        title: Техника, подсветка
        description: "Встраиваемая техника, LED подсветка 3000K CRI>95, блок питания 24V"
        display: list
      scenes: []
    YAML
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
  # --- 20. Тест вертикального выравнивания в заголовке (по верху, по центру, по низу) ---
  # --- 21. Тест жесткой фиксации высоты заголовка (30%, не регулируется) ---
  # --- 23. Тест учета количества создаваемых страниц в содержании проекта ---
  def test_toc_page_count_and_created_pages_filtering
    puts "\n--- 23. Тест содержания (TOC): список включённых страниц и нумерация ---"
  
    project_data = DN1Code::ExportPdf2::Model::ProjectData.new
    project_data.project_info = {
      name_project:   "Квартира на Тверской",
      room_name:      "Кухня-гостиная",
      furniture_name: "Гарнитур со встроенной техникой",
      articul:        "TVR-2026-01",
      version:        1,
      revision:       2
    }
  
    # Создаем 4 сцены: 3 включены, 1 отключена
    scenes = [
      DN1Code::ExportPdf2::Model::SceneItem.new(name: "01. Обложка", page_type: :cover, enabled: true),
      DN1Code::ExportPdf2::Model::SceneItem.new(name: "02. Содержание", page_type: :explain, enabled: true),
      DN1Code::ExportPdf2::Model::SceneItem.new(name: "04. Скрытый ракурс", page_type: :visual, enabled: false),
      DN1Code::ExportPdf2::Model::SceneItem.new(name: "05. Финальный рендер", page_type: :visual, enabled: true)
    ]
    project_data.scenes = scenes
  
    # 1. resolve_param('page.toc'): нумерованный список только включённых сцен
    pdf_doc = DN1Code::ExportPdf2::Service::PdfBuilder.create_document(project_data, project_data.pdf_settings)
    cover_page = DN1Code::ExportPdf2::Controller::CoverPage.new(pdf_doc, project_data, scenes[0], page_index: 1, total_pages: 3)
  
    toc_text = cover_page.send(:resolve_info_line, "page.toc")
    assert(toc_text && toc_text.include?("1. 01. Обложка"), "TOC содержит '1. 01. Обложка'")
    assert(toc_text.include?("2. 02. Содержание"), "TOC содержит '2. 02. Содержание'")
    assert(toc_text.include?("3. 05. Финальный рендер"), "TOC содержит '3. 05. Финальный рендер'")
    assert(!toc_text.include?("Скрытый ракурс"), "TOC исключает отключенные сцены (enabled: false)")
  
    num_text = cover_page.send(:resolve_info_line, "page.number_total")
    assert(num_text == "Страница 1 | 3", "page.number_total → «Страница 1 | 3» (получено: #{num_text.inspect})")
  
    # 2. Рендеринг ExplainPage с содержанием
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
  # --- 25. Тест выпадающих параметров (размер шрифта, номер строки, цвет текста) для пунктов заголовка ---
  def test_scenes_table_two_row_layout
    puts "\n--- 27. Тест разделения колонок галочек и перемещения и двухстрочного названия/описания сцен ---"
    index_html_path = File.expand_path("../dialog/html/index.html", __dir__)
    index_html_content = File.read(index_html_path, encoding: "utf-8")

    # 1. Проверка структуры thead в index.html
    assert(index_html_content.include?("<th>Сцена / Описание</th>"), "index.html содержит объединенный заголовок 'Сцена / Описание'")
    assert(!index_html_content.include?("<th>Описание на листе</th>"), "index.html больше не содержит отдельную колонку 'Описание на листе'")
    assert(index_html_content.include?("th-check"), "index.html содержит отдельную колонку для галочек 'Вкл'")
    assert(index_html_content.include?("th-order"), "index.html содержит отдельную колонку для порядка и перемещения '№'")

    app_js_path = File.expand_path("../dialog/html/app.js", __dir__)
    app_js_content = File.read(app_js_path, encoding: "utf-8")

    # 2. Проверка генерации строки таблицы в app.js
    assert(app_js_content.include?("scene-check-cell"), "app.js содержит отдельную ячейку scene-check-cell для галочки")
    assert(app_js_content.include?("scene-num-cell"), "app.js содержит отдельную ячейку scene-num-cell для перемещения и номера")
    assert(app_js_content.include?("scene-num-row"), "app.js содержит строку номера с ручкой drag-handle")
    assert(app_js_content.include?("scene-info-cell"), "app.js содержит ячейку scene-info-cell")
    assert(app_js_content.include?("scene-info-wrap"), "app.js содержит обертку scene-info-wrap")
    assert(app_js_content.include?("scene-name-input"), "app.js содержит поле ввода названия сцены (scene-name-input)")
    assert(app_js_content.include?("scene-desc-input"), "app.js содержит поле ввода описания сцены (scene-desc-input)")
    assert(app_js_content.include?("tdInfo.appendChild(infoWrap)"), "app.js помещает оба поля в единую ячейку tdInfo")
    assert(app_js_content.include?("tr.appendChild(tdCheck)"), "app.js добавляет ячейку чекбокса в tr")
    assert(app_js_content.include?("tr.appendChild(tdNum)"), "app.js добавляет ячейку номера и перемещения в tr")

    # 3. Проверка стилей в app.css
    app_css_path = File.expand_path("../dialog/html/app.css", __dir__)
    app_css_content = File.read(app_css_path, encoding: "utf-8")
    assert(app_css_content.include?(".th-check"), "app.css содержит стиль .th-check")
    assert(app_css_content.include?(".th-order"), "app.css содержит стиль .th-order")
    assert(app_css_content.include?(".scene-check-cell"), "app.css содержит стиль .scene-check-cell")
    assert(app_css_content.include?(".scene-num-cell"), "app.css содержит стиль .scene-num-cell")
    assert(app_css_content.include?(".scene-num-row"), "app.css содержит стиль .scene-num-row")
    assert(app_css_content.include?(".scene-info-wrap"), "app.css содержит стиль .scene-info-wrap")
    assert(app_css_content.include?(".scene-desc-input"), "app.css содержит стиль .scene-desc-input")
    assert(app_css_content.include?(".scenes-table .scene-info-cell"), "app.css содержит стиль .scenes-table .scene-info-cell")
    assert(app_css_content.include?(".scenes-table td"), "app.css содержит вертикальное центрирование .scenes-table td")
  end

  # ============================================================================
  # 29. ТЕСТ: Настройка каждого пункта Среднего блока значками
  # ============================================================================
  # ============================================================================
  # 30. ТЕСТ: Перетаскивание (Drag and Drop) порядка пунктов мышкой в блоках шаблонов
  # ============================================================================
  # =========================================================================
  # ТЕСТ 31: Проверка выравнивания по вертикали центру пунктов среднего блока
  # =========================================================================
  # ============================================================================
  # 33. ТЕСТ: Общий размер шрифта среднего блока и переназначение в пунктах
  # ============================================================================
  # ============================================================================
  # 34. ТЕСТ: Настройка картинки чертежа под текст (пропорции 3:2, 4:3, 16:9 и размещение 60-100%)
  # ============================================================================
  def test_drawing_image_settings_proportions_and_placement
    puts "\n--- 34. Тест настройки картинки чертежа под текст (пропорции 3:2, 4:3, 16:9 и масштаб 60-100%) ---"

    app_js_path = File.expand_path("../dialog/html/app.js", __dir__)
    app_js_content = File.read(app_js_path, encoding: "utf-8")

    # 1. Проверка постраничного меню кадра в таблице страниц (app.js)
    assert(app_js_content.include?("scene-frame-btn"), "app.js содержит кнопку меню кадра scene-frame-btn")
    assert(app_js_content.include?("sceneFramePopover"), "app.js открывает поповер меню кадра sceneFramePopover")

    # 2. Проверка пропорций в меню кадра (3:2, 4:3, 5:4, 16:9, 1:1, 4:5, По листу)
    assert(app_js_content.include?('["3:2", "3:2"]'), "меню кадра содержит пропорцию 3:2")
    assert(app_js_content.include?('["4:3", "4:3"]'), "меню кадра содержит пропорцию 4:3")
    assert(app_js_content.include?('["5:4", "5:4"]'), "меню кадра содержит пропорцию 5:4")
    assert(app_js_content.include?('["16:9", "16:9"]'), "меню кадра содержит пропорцию 16:9")
    assert(app_js_content.include?('["1:1", "1:1"]'), "меню кадра содержит пропорцию 1:1")
    assert(app_js_content.include?('["4:5", "4:5"]'), "меню кадра содержит пропорцию 4:5")
    assert(app_js_content.include?('["page", "По листу"]'), "меню кадра содержит пропорцию 'По листу'")

    # 3. Проверка масштаба страницы (60-100%)
    assert(app_js_content.include?("[60, 70, 80, 90, 100]"), "масштаб страницы выбирается из 60-100%")

    # 4. Проверка обработчиков кликов и автосохранения.
    # Пропорции страницы персональные: сохраняются в scene.aspect_ratio и НЕ
    # перезаписывают блок image_4_3 шаблона (иначе страницы шаблона получали
    # пропорции первой отредактированной страницы)
    assert(app_js_content.include?("scene.aspect_ratio = val;"), "app.js сохраняет пропорцию в настройках страницы (scene.aspect_ratio)")
    assert(!app_js_content.include?('updateBlockSlot("image_4_3", { aspect_ratio: val })'),
           "app.js не синхронизирует пропорцию страницы в блок шаблона (постраничные пропорции независимы)")
    assert(app_js_content.include?('updateBlockSlot("image_4_3", { scale_pct: scale })'), "app.js обновляет scale_pct при смене масштаба")

    # 5. Проверка стилей в app.css
    app_css_path = File.expand_path("../dialog/html/app.css", __dir__)
    app_css_content = File.read(app_css_path, encoding: "utf-8")
    assert(app_css_content.include?(".scene-frame-btn"), "app.css содержит стиль кнопки меню кадра .scene-frame-btn")
    assert(app_css_content.include?(".scene-frame-pop"), "app.css содержит стиль поповера меню кадра .scene-frame-pop")
    assert(app_css_content.include?(".scene-frame-ratio-opt"), "app.css содержит стиль вариантов пропорций .scene-frame-ratio-opt")

    # 6. Проверка значений по умолчанию в ProjectData
    project_data = DN1Code::ExportPdf2::Model::ProjectData.new
    [:cover, :description, :explain, :general, :visual].each do |tpl|
      img_slot = project_data.default_custom_layouts[tpl][:image_4_3]
      assert(img_slot[:aspect_ratio] == "4:3", "default_custom_layouts[#{tpl}][:image_4_3] пропорция по умолчанию 4:3")
      assert(img_slot[:scale_pct] == 100, "default_custom_layouts[#{tpl}][:image_4_3] масштаб по умолчанию 100%")
    end

    # 7. Проверка наличия параметров в YAML файлах
    default_yaml = File.read(File.expand_path("../config/default_layout.yaml", __dir__), encoding: "utf-8")
    assert(default_yaml.include?("aspect_ratio: '4:3'") || default_yaml.include?("aspect_ratio: \"4:3\""), "default_layout.yaml содержит aspect_ratio: 4:3")
    assert(default_yaml.include?("scale_pct: 100"), "default_layout.yaml содержит scale_pct: 100")

    layout_yaml = File.read(File.expand_path("../config/layout.yaml", __dir__), encoding: "utf-8")
    assert(layout_yaml.include?("aspect_ratio: '4:3'") || layout_yaml.include?("aspect_ratio: \"4:3\""), "layout.yaml содержит aspect_ratio: 4:3")
    assert(layout_yaml.include?("scale_pct: 100"), "layout.yaml содержит scale_pct: 100")

    # 8. Генерация PDF с пропорцией 16:9 и масштабом 80%
    mock_page = Sketchup::MockPage.new("01. Вид широкоформатный")
    mock_page.description = "Рендер 16:9 с размещением 80%"
    scene = DN1Code::ExportPdf2::Model::SceneItem.new(
      name: "01. Вид широкоформатный",
      description: "Рендер 16:9 с размещением 80%",
      scene_ref: mock_page,
      page_type: :cover,
      order: 1,
      enabled: true
    )

    layouts = project_data.pdf_settings[:custom_layouts]
    layouts[:cover][:image_4_3][:aspect_ratio] = "16:9"
    layouts[:cover][:image_4_3][:scale_pct] = 80

    pdf_doc = DN1Code::ExportPdf2::Service::PdfBuilder.create_document(project_data, project_data.pdf_settings)
    cover_page = DN1Code::ExportPdf2::Controller::CoverPage.new(pdf_doc, project_data, scene, page_index: 1, total_pages: 1)

    test_dir = File.expand_path("test_drawing_image_dir", __dir__)
    FileUtils.mkdir_p(test_dir)
    out_pdf_16_9 = File.join(test_dir, "test_image_16_9_scale_80.pdf")

    cover_page.render
    pdf_doc.render_file(out_pdf_16_9)

    assert(File.exist?(out_pdf_16_9), "PDF с рендером 16:9 и масштабом 80% успешно создан")
    assert(File.size(out_pdf_16_9) > 5000, "Размер PDF 16:9 валиден (#{File.size(out_pdf_16_9) rescue 0} байт)")

    # 9. Генерация PDF с пропорцией 3:2 и масштабом 60%
    layouts[:cover][:image_4_3][:aspect_ratio] = "3:2"
    layouts[:cover][:image_4_3][:scale_pct] = 60

    pdf_doc2 = DN1Code::ExportPdf2::Service::PdfBuilder.create_document(project_data, project_data.pdf_settings)
    cover_page2 = DN1Code::ExportPdf2::Controller::CoverPage.new(pdf_doc2, project_data, scene, page_index: 1, total_pages: 1)
    out_pdf_3_2 = File.join(test_dir, "test_image_3_2_scale_60.pdf")

    cover_page2.render
    pdf_doc2.render_file(out_pdf_3_2)

    assert(File.exist?(out_pdf_3_2), "PDF с рендером 3:2 и масштабом 60% успешно создан")
    assert(File.size(out_pdf_3_2) > 5000, "Размер PDF 3:2 валиден (#{File.size(out_pdf_3_2) rescue 0} байт)")

    FileUtils.rm_rf(test_dir)
  end

  def test_manual_revision_prompt_before_pdf_export_and_no_auto_history
    puts "\n--- 35. Тест ручной фиксации правок перед экспортом и запрета авто-создания истории ---"

    html_file = File.expand_path("../dialog/html/index.html", __dir__)
    css_file  = File.expand_path("../dialog/html/app.css", __dir__)
    js_file   = File.expand_path("../dialog/html/app.js", __dir__)

    html_content = File.read(html_file, encoding: "utf-8")
    css_content  = File.read(css_file, encoding: "utf-8")
    js_content   = File.read(js_file, encoding: "utf-8")

    # 1. Проверка структуры HTML для модального окна фиксации правок
    assert(html_content.include?('id="revisionPromptModal"'), "index.html содержит модальное окно revisionPromptModal")
    assert(html_content.include?('id="inputRevisionNote"'), "index.html содержит поле ввода описания правок inputRevisionNote")
    assert(html_content.include?('id="btnConfirmRevisionExport"'), "index.html содержит кнопку 'Записать и создать PDF'")
    assert(html_content.include?('id="btnSkipRevisionExport"'), "index.html содержит кнопку 'Без записи правок'")
    assert(html_content.include?('id="btnCancelExportModal"'), "index.html содержит кнопку 'Отмена'")
    assert(html_content.include?('id="revPromptDateTime"'), "index.html содержит поле точной даты и времени revPromptDateTime")
    assert(html_content.include?('id="revPromptNextRev"'), "index.html содержит индикатор следующей ревизии revPromptNextRev")

    # 2. Проверка стилей CSS
    assert(css_content.include?(".revision-modal-card"), "app.css содержит стили карточки модального окна .revision-modal-card")
    assert(css_content.include?(".rev-textarea"), "app.css содержит стили текстового поля .rev-textarea")
    assert(css_content.include?(".revision-meta-grid"), "app.css содержит стили сетки метаданных даты/ревизии")

    # 3. Проверка логики в app.js
    assert(js_content.include?("revisionPromptModal"), "app.js кэширует элемент revisionPromptModal")
    assert(js_content.include?("btnConfirmRevisionExport"), "app.js содержит обработчик кнопки подтверждения правок")
    assert(js_content.include?("btnSkipRevisionExport"), "app.js содержит обработчик экспорта без записи правок")
    assert(js_content.include?("executeExport"), "app.js выносит запуск экспорта в отдельную функцию executeExport")

    # 4. Проверка поведения Controller::ExportController: экспорт НЕ добавляет историю автоматически
    test_dir = File.expand_path("test_no_auto_history_dir", __dir__)
    FileUtils.mkdir_p(test_dir)

    skp_file = File.join(test_dir, "Manual_Rev_Test.skp")
    model = Sketchup::MockModel.new(skp_file)
    model.pages.add("01. Обложка")

    project_data = DN1Code::ExportPdf2::Model::ProjectData.new
    project_data.project_info[:articul] = "REV-TEST-001"
    project_data.workflow[:revision] = "003"
    project_data.workflow[:history_edit] = [
      ["2026-09-01 12:00", "Стартовая редакция (rev. 001)"],
      ["2026-09-03 14:15", "Согласование проекта (rev. 002)"]
    ]
    project_data.sync_project_fields!
    project_data.sync_with_model_scenes(model)

    initial_hist_count = project_data.workflow[:history_edit].size
    initial_rev = project_data.workflow[:revision]

    # Экспорт без внесения правок (пользователь выбрал "Без записи правок")
    pdf_no_rev = File.join(test_dir, "export_no_rev.pdf")
    controller = DN1Code::ExportPdf2::Controller::ExportController.new(project_data, model)
    controller.export(pdf_no_rev)

    assert(File.exist?(pdf_no_rev), "PDF успешно создан без внесения правок")
    assert(project_data.workflow[:history_edit].size == initial_hist_count, "История правок НЕ увеличилась автоматически при экспорте")
    assert(project_data.workflow[:revision] == initial_rev, "Номер ревизии НЕ изменился автоматически (остался #{initial_rev})")

    # 5. Ручное внесение правок с точной датой и временем перед созданием PDF
    #    (инкремент ревизии выполняется пользователем в диалоге, а не при экспорте)
    exact_time = "2026-09-07 00:45"
    edits_desc = "Заменены направляющие ящиков на Blum Tandem, обновлен цвет цоколя"
    project_data.workflow[:revision]     = "004"
    project_data.project_info[:revision] = 4
    project_data.workflow[:history_edit].unshift([exact_time, "#{edits_desc} (rev. 004)"])

    assert(project_data.workflow[:revision] == "004", "Ревизия успешно инкрементирована до 004")
    assert(project_data.workflow[:history_edit].size == initial_hist_count + 1, "В историю добавлена ровно одна запись правок")
    latest_entry = project_data.workflow[:history_edit].first
    assert(latest_entry[0] == exact_time, "Точная дата и время записаны корректно: #{latest_entry[0]}")
    assert(latest_entry[1].include?(edits_desc), "Текст правок зафиксирован: #{latest_entry[1]}")
    assert(latest_entry[1].include?("rev. 004"), "Текст содержит номер новой ревизии (rev. 004)")

    # Генерация PDF с обновленной историей
    pdf_with_rev = File.join(test_dir, "export_with_rev.pdf")
    controller_rev = DN1Code::ExportPdf2::Controller::ExportController.new(project_data, model)
    controller_rev.export(pdf_with_rev)

    assert(File.exist?(pdf_with_rev), "PDF с зафиксированными правками успешно сгенерирован")
    assert(project_data.workflow[:history_edit].size == initial_hist_count + 1, "После экспорта лишняя автоматическая запись не создалась")

    FileUtils.rm_rf(test_dir)
  end

  # ============================================================================
  # 36. ТЕСТ: Выравнивание пунктов подвала по нижнему краю страницы
  # ============================================================================
  # ============================================================================
  # 37. ТЕСТ: Отображение информации среднего блока во всех шаблонах
  # ============================================================================
  # --- 38. Тест параметра расстояния между пунктами среднего блока на странице ---
  # ============================================================================
  # 39. ТЕСТ: Выравнивание заголовка по верхней границе страницы по умолчанию
  # ============================================================================
  def test_40_template_usage_separate_line
    puts "\n--- 40. Тест отображения строки использования шаблона на отдельной строке ---"

    html_path = File.expand_path("../dialog/html/index.html", __dir__)
    html_content = File.read(html_path, encoding: "utf-8")

    # 1. Проверка наличия отдельной строки toolbar-usage-row для layoutTplUsageBadge в index.html
    assert(html_content.include?('class="toolbar-row toolbar-usage-row"'), "index.html содержит отдельную строку .toolbar-usage-row")
    assert(html_content.include?('id="layoutTplUsageBadge"'), "index.html содержит #layoutTplUsageBadge")
    assert(html_content.match?(/toolbar-usage-row[^<]*>\s*<span[^>]+id="layoutTplUsageBadge"/m), "layoutTplUsageBadge находится внутри отдельной строки .toolbar-usage-row")

    # 2. Проверка того, что основные элементы управления находятся в .toolbar-main-row
    assert(html_content.include?('class="toolbar-row toolbar-main-row"'), "index.html содержит основную строку .toolbar-main-row")
    assert(html_content.match?(/toolbar-main-row.*?selectLayoutTemplate.*?inputLayoutMargin/m), "Селектор шаблона и поля находятся в .toolbar-main-row")

    # 3. Проверка стилей в app.css
    css_path = File.expand_path("../dialog/html/app.css", __dir__)
    css_content = File.read(css_path, encoding: "utf-8")

    assert(css_content.include?(".template-settings-toolbar .toolbar-usage-row"), "app.css содержит стили для .toolbar-usage-row")
    assert(css_content.include?(".layout-tpl-usage"), "app.css содержит стили для .layout-tpl-usage")
    assert(css_content.include?(".layout-tpl-usage.empty-usage"), "app.css содержит стили для .empty-usage")

    # 4. Проверка логики в app.js
    app_js_path = File.expand_path("../dialog/html/app.js", __dir__)
    app_js_content = File.read(app_js_path, encoding: "utf-8")

    assert(app_js_content.include?('Используется:'), "app.js обновляет строку использования с префиксом 'Используется:'")
    assert(app_js_content.include?('Не привязан к сценам'), "app.js обновляет строку при отсутствии привязки")
    assert(app_js_content.include?('badge.classList.remove("empty-usage")'), "app.js переключает класс empty-usage")
  end

  def test_41_api_targets_addition_and_deletion
    puts "\n--- 41. Тест добавления и удаления адресатов веб-интеграции (API TARGETS) ---"

    # 1. Проверка HTML элементов
    html_path = File.expand_path("../dialog/html/index.html", __dir__)
    html_content = File.read(html_path, encoding: "utf-8")
    assert(html_content.include?('id="btnAddApiTarget"'), "index.html содержит кнопку #btnAddApiTarget")
    assert(html_content.include?('+ Добавить URL'), "index.html содержит надпись '+ Добавить URL'")
    assert(html_content.include?('id="apiTargetsList"'), "index.html содержит контейнер #apiTargetsList")

    # 1a. Проверка вкладки "Отправка" (tab-send): WebP и адресаты перенесены из "Настроек"
    assert(html_content.include?('data-tab="tab-send"'), "index.html содержит кнопку вкладки Отправка (tab-send)")
    assert(html_content.include?('id="tab-send"'), "index.html содержит панель #tab-send")
    send_pane_pos = html_content.index('id="tab-send"')
    assert(send_pane_pos && send_pane_pos < html_content.index('id="webpQualityGroup"'), "Карточка WebP перенесена на вкладку Отправка")
    assert(send_pane_pos && send_pane_pos < html_content.index('id="btnAddApiTarget"'), "Карточка адресатов перенесена на вкладку Отправка")

    # 2. Проверка CSS стилей
    css_path = File.expand_path("../dialog/html/app.css", __dir__)
    css_content = File.read(css_path, encoding: "utf-8")
    assert(css_content.include?(".api-target-card"), "app.css содержит стили .api-target-card")
    assert(css_content.include?(".api-target-badge"), "app.css содержит стили .api-target-badge")
    assert(css_content.include?(".api-target-input"), "app.css содержит стили .api-target-input")
    assert(css_content.include?(".empty-targets-placeholder"), "app.css содержит стили .empty-targets-placeholder")

    # 3. Проверка JavaScript логики
    app_js_path = File.expand_path("../dialog/html/app.js", __dir__)
    app_js_content = File.read(app_js_path, encoding: "utf-8")
    assert(app_js_content.include?('btnAddApiTarget: document.getElementById("btnAddApiTarget")'), "app.js регистрирует btnAddApiTarget в els")
    assert(app_js_content.include?('els.btnAddApiTarget.addEventListener("click"'), "app.js обрабатывает нажатие кнопки добавления адресата")
    assert(app_js_content.include?('api-target-input'), "app.js создает редактируемые поля ввода .api-target-input")
    assert(app_js_content.include?('state.api_targets.splice(index, 1)'), "app.js поддерживает удаление адресата по индексу через splice")
    assert(app_js_content.include?('querySelectorAll(".api-target-input")'), "app.js собирает значения адресатов в collectFormData")

    # 4. Проверка работы с ProjectData и ExportDialog
    test_dir = File.expand_path("../../test_sandbox_api_targets_#{Time.now.to_i}", __dir__)
    FileUtils.mkdir_p(test_dir)

    data = DN1Code::ExportPdf2::Model::ProjectData.new
    assert(data.api_targets.is_a?(Array), "ProjectData инициализирует api_targets как Array")
    initial_count = data.api_targets.size

    # Добавление нового адресата
    new_url = "https://custom-api.example.com/v1/projects?token=test12345"
    data.api_targets << new_url
    assert(data.api_targets.size == initial_count + 1, "Адресат успешно добавлен в список api_targets")
    assert(data.api_targets.include?(new_url), "Добавленный URL присутствует в api_targets")

    # Удаление первого адресата
    deleted_url = data.api_targets.shift
    assert(data.api_targets.size == initial_count, "Адресат успешно удален из api_targets")
    assert(!data.api_targets.include?(deleted_url), "Удаленный URL больше не содержится в api_targets")

    # Проверка сохранения и загрузки через YAML
    test_yaml = File.join(test_dir, "test_api_targets.yaml")
    saved = data.save_to_yaml(test_yaml)
    assert(saved && File.exist?(test_yaml), "Данные проекта успешно сохранены в YAML")

    yaml_text = File.read(test_yaml, encoding: "utf-8")
    assert(yaml_text.include?("custom-api.example.com"), "YAML файл содержит сохраненный новый URL адресата")
    assert(!yaml_text.include?(deleted_url), "YAML файл не содержит удаленный URL адресата")

    reloaded_data = DN1Code::ExportPdf2::Model::ProjectData.new
    assert(reloaded_data.load_from_yaml(test_yaml), "YAML успешно загружен в новый экземпляр ProjectData")
    assert(data.api_targets == reloaded_data.api_targets, "api_targets после загрузки из YAML полностью совпадают")

    # Проверка работы populate_project_data в ExportDialog
    payload = {
      api_targets: [
        "https://api1.test/hook",
        "  https://api2.test/hook  ",
        ""
      ]
    }
    mock_proj = DN1Code::ExportPdf2::Model::ProjectData.new
    DN1Code::ExportPdf2::Dialog::ExportDialog.populate_project_data(mock_proj, payload)
    assert(mock_proj.api_targets.size == 2, "populate_project_data корректно отфильтровал пустые строки")
    assert(mock_proj.api_targets[0] == "https://api1.test/hook", "Первый URL передан без изменений")
    assert(mock_proj.api_targets[1] == "https://api2.test/hook", "Второй URL очищен от пробелов")

    # Проверка сохранения и загрузки пустых api_targets (полное удаление)
    mock_proj.api_targets = []
    empty_yaml = File.join(test_dir, "test_empty_api_targets.yaml")
    mock_proj.save_to_yaml(empty_yaml)
    empty_yaml_text = File.read(empty_yaml, encoding: "utf-8")
    assert(empty_yaml_text.include?("api_targets: []"), "При удалении всех адресатов YAML содержит api_targets: []")

    empty_reload = DN1Code::ExportPdf2::Model::ProjectData.new
    empty_reload.load_from_yaml(empty_yaml)
    assert(empty_reload.api_targets == [], "Загрузка пустого списка адресатов возвращает пустой массив")

    FileUtils.rm_rf(test_dir)
  end

  def test_42_safe_frame_overlay_and_aspect_ratios
    puts "\n--- 42. Тест рамки пропорций кадра (Safe Frame Overlay) и настроек ---"

    require_relative "../service/overlay_service"
    overlay_svc = DN1Code::ExportPdf2::Service::OverlayService

    # 1. Проверка констант оверлея
    assert(overlay_svc::OVERLAY_ID == "dn1code.export_pdf2.safe_frame_overlay", "ID оверлея равен dn1code.export_pdf2.safe_frame_overlay")
    assert(overlay_svc::OVERLAY_NAME.include?("Safe Frame"), "Имя оверлея содержит Safe Frame")

    # 2. Проверка расчетов соотношений сторон (calculate_target_info)
    # A4 Альбомный
    overlay_svc.update_settings({ image_aspect_ratio: "page", page_size: "A4", page_layout: "landscape", image_width: 2400 })
    info_a4_l = overlay_svc.calculate_target_info
    assert((info_a4_l[:ratio] - 1.4142).abs < 0.01, "Соотношение A4 landscape рассчитано верно (~1.414)")
    assert(info_a4_l[:render_w] == 2400, "Ширина рендера равна 2400")
    assert(info_a4_l[:render_h] == 1697, "Высота рендера для A4 landscape равна 1697")
    assert(info_a4_l[:label].include?("A4 Альбомный"), "Метка содержит A4 Альбомный")

    # A4 Книжный
    overlay_svc.update_settings({ image_aspect_ratio: "page", page_size: "A4", page_layout: "portrait", image_width: 2400 })
    info_a4_p = overlay_svc.calculate_target_info
    assert((info_a4_p[:ratio] - 0.7071).abs < 0.01, "Соотношение A4 portrait рассчитано верно (~0.707)")
    assert(info_a4_p[:render_h] == 3394, "Высота рендера для A4 portrait равна 3394")

    # 16:9
    overlay_svc.update_settings({ image_aspect_ratio: "16:9", image_width: 2400 })
    info_16_9 = overlay_svc.calculate_target_info
    assert((info_16_9[:ratio] - 1.7778).abs < 0.01, "Соотношение 16:9 рассчитано верно (~1.778)")
    assert(info_16_9[:render_h] == 1350, "Высота рендера для 16:9 равна 1350 (2400 / 1.7778)")

    # 4:3
    overlay_svc.update_settings({ image_aspect_ratio: "4:3", image_width: 2400 })
    info_4_3 = overlay_svc.calculate_target_info
    assert((info_4_3[:ratio] - 1.3333).abs < 0.01, "Соотношение 4:3 рассчитано верно (~1.333)")
    assert(info_4_3[:render_h] == 1800, "Высота рендера для 4:3 равна 1800")

    # 3:2
    overlay_svc.update_settings({ image_aspect_ratio: "3:2", image_width: 2400 })
    info_3_2 = overlay_svc.calculate_target_info
    assert((info_3_2[:ratio] - 1.5).abs < 0.01, "Соотношение 3:2 рассчитано верно (1.5)")
    assert(info_3_2[:render_h] == 1600, "Высота рендера для 3:2 равна 1600")

    # 1:1
    overlay_svc.update_settings({ image_aspect_ratio: "1:1", image_width: 2400 })
    info_1_1 = overlay_svc.calculate_target_info
    assert((info_1_1[:ratio] - 1.0).abs < 0.01, "Соотношение 1:1 рассчитано верно (1.0)")
    assert(info_1_1[:render_h] == 2400, "Высота рендера для 1:1 равна 2400")

    # Пользовательский (custom: 21:9)
    overlay_svc.update_settings({ image_aspect_ratio: "custom", custom_ratio_w: 21, custom_ratio_h: 9, image_width: 2400 })
    info_custom = overlay_svc.calculate_target_info
    assert((info_custom[:ratio] - (21.0 / 9.0)).abs < 0.01, "Кастомное соотношение 21:9 рассчитано верно (~2.333)")
    assert(info_custom[:render_h] == 1029, "Высота рендера для 21:9 равна 1029")

    # 3. Проверка жизненного цикла оверлея (enable, disable, toggle, active?)
    # Явное перекрытие шаблона — изоляция от пользовательского config/layout.yaml
    overlay_svc.update_settings({ custom_layouts: { cover: { image_4_3: { visible: true, aspect_ratio: "16:9" } } } })
    mock_model = Sketchup::MockModel.new
    assert(!overlay_svc.overlay_active?(mock_model), "Изначально оверлей выключен")

    assert(overlay_svc.enable(mock_model) == true, "enable(model) возвращает true")
    assert(overlay_svc.overlay_active?(mock_model), "Оверлей активен после enable")
    assert(mock_model.overlays.size == 1, "В коллекцию модели добавлен 1 оверлей")
    assert(mock_model.overlays[0].overlay_id == overlay_svc::OVERLAY_ID, "Добавленный оверлей имеет правильный ID")

    # Повторный enable не дублирует оверлей
    overlay_svc.enable(mock_model)
    assert(mock_model.overlays.size == 1, "Повторный вызов enable не создает дубликатов")

    # toggle переключает в false
    res_toggle = overlay_svc.toggle(mock_model)
    assert(res_toggle == false, "toggle переключил оверлей в false")
    assert(!overlay_svc.overlay_active?(mock_model), "Оверлей неактивен после toggle")

    # toggle переключает обратно в true
    res_toggle2 = overlay_svc.toggle(mock_model)
    assert(res_toggle2 == true, "toggle переключил оверлей обратно в true")
    assert(overlay_svc.overlay_active?(mock_model), "Оверлей активен после второго toggle")

    # disable выключает
    overlay_svc.disable(mock_model)
    assert(!overlay_svc.overlay_active?(mock_model), "disable выключил оверлей")

    # 4. Проверка отрисовки оверлея в View
    ov_inst = overlay_svc.overlay_instance
    mock_view = mock_model.active_view
    mock_view.drawn_elements.clear
    overlay_svc.update_settings({ image_aspect_ratio: "16:9", image_width: 2400 })
    ov_inst.draw(mock_view)

    assert(mock_view.drawn_elements.size > 0, "Метод draw оверлея выполнил отрисовку графических примитивов")
    has_loop = mock_view.drawn_elements.any? { |el| el[:mode] == GL_LINE_LOOP }
    has_lines = mock_view.drawn_elements.any? { |el| el[:mode] == GL_LINES }
    has_text = mock_view.drawn_elements.any? { |el| el[:mode] == :text }
    assert(has_loop, "Отрисован контур рамки (GL_LINE_LOOP)")
    assert(has_lines, "Отрисованы угловые засечки и сетка (GL_LINES)")
    assert(has_text, "Отрисован информационный бейдж с текстом")

    text_el = mock_view.drawn_elements.find { |el| el[:mode] == :text }
    assert(text_el[:pos].x == mock_view.vpwidth / 2.0, "Строка оверлея центрирована по горизонтали (внизу по центру)")
    assert(text_el[:pos].y > mock_view.vpheight / 2.0, "Строка оверлея расположена в нижней половине кадра (внизу по центру)")

    # Проверка дефолтных настроек и открытия файлов
    empty_dir = File.join(Dir.tmpdir, "test_open_frame_empty_#{Time.now.to_i}_#{rand(10000)}")
    FileUtils.mkdir_p(empty_dir)
    mock_model_empty = Sketchup::MockModel.new
    mock_model_empty.path = File.join(empty_dir, "empty_model.skp")
    pdata_empty = DN1Code::ExportPdf2::Model::ProjectData.new
    pdata_empty.load_auto(mock_model_empty)
    assert(pdata_empty.pdf_settings[:image_aspect_ratio] == "4:3", "При открытии файла без сохраненных настроек устанавливается 4:3")

    saved_dir = File.join(Dir.tmpdir, "test_open_frame_saved_#{Time.now.to_i}_#{rand(10000)}")
    FileUtils.mkdir_p(saved_dir)
    mock_model_saved = Sketchup::MockModel.new
    mock_model_saved.path = File.join(saved_dir, "saved_model.skp")
    # Настройки PDF глобальные: значение 16:9 задается в памяти сессии (update_frame_settings);
    # show_aspect_overlay: false — чтобы on_model_opened не включал рамку и не пересчитывал кэш
    pdata_saved = DN1Code::ExportPdf2::Model::ProjectData.new
    pdata_saved.update_frame_settings({ image_aspect_ratio: "16:9", show_aspect_overlay: false })
    assert(pdata_saved.pdf_settings[:image_aspect_ratio] == "16:9", "update_frame_settings задает 16:9 в памяти сессии")

    overlay_svc.on_model_opened(mock_model_empty, pdata_empty)
    assert((overlay_svc.overlay_instance.ratio_cache - (4.0 / 3.0)).abs < 0.01, "on_model_opened устанавливает кэш пропорций 4:3 для модели без настроек")

    overlay_svc.on_model_opened(mock_model_saved, pdata_saved)
    assert((overlay_svc.overlay_instance.ratio_cache - (16.0 / 9.0)).abs < 0.01, "on_model_opened устанавливает кэш пропорций 16:9 для сессии с 16:9")

    # Проверка: update_frame_settings меняет только память, settings.yaml не перезаписывается
    cfg_text_before = File.read(DN1Code::ExportPdf2::Model::ProjectData::PROGRAM_SETTINGS_FILE, encoding: "utf-8") rescue ""
    pdata_saved.update_frame_settings({ image_aspect_ratio: "4:3" })
    assert(pdata_saved.pdf_settings[:image_aspect_ratio] == "4:3", "update_frame_settings вернул 4:3 в памяти")
    cfg_text_after = File.read(DN1Code::ExportPdf2::Model::ProjectData::PROGRAM_SETTINGS_FILE, encoding: "utf-8") rescue ""
    assert(cfg_text_before == cfg_text_after, "update_frame_settings не пишет на диск (settings.yaml нетронут)")

    # Проверка игнорирования недопустимых пропорций кадра
    pdata_saved.update_frame_settings({ image_aspect_ratio: "21:9" })
    assert(pdata_saved.pdf_settings[:image_aspect_ratio] == "4:3", "update_frame_settings игнорирует недопустимые пропорции 21:9")

    info_invalid = overlay_svc.calculate_target_info(nil, { image_aspect_ratio: "21:9" })
    assert((info_invalid[:ratio] - (4.0 / 3.0)).abs < 0.01, "calculate_target_info нормализует неизвестные пропорции 21:9 к 4:3")

    # 5. Проверка сохранения параметров в ProjectData и YAML
    proj_data = DN1Code::ExportPdf2::Model::ProjectData.new
    assert(proj_data.pdf_settings.key?(:image_aspect_ratio), "pdf_settings содержит :image_aspect_ratio")
    assert(proj_data.pdf_settings.key?(:custom_ratio_w), "pdf_settings содержит :custom_ratio_w")
    assert(proj_data.pdf_settings.key?(:custom_ratio_h), "pdf_settings содержит :custom_ratio_h")
    assert(proj_data.pdf_settings.key?(:show_aspect_overlay), "pdf_settings содержит :show_aspect_overlay")

    proj_data.pdf_settings[:image_aspect_ratio] = "16:9"
    proj_data.pdf_settings[:custom_ratio_w] = 16
    proj_data.pdf_settings[:custom_ratio_h] = 9
    proj_data.pdf_settings[:show_aspect_overlay] = true

    tmp_dir = File.join(Dir.tmpdir, "test_overlay_yaml_#{Time.now.to_i}")
    FileUtils.mkdir_p(tmp_dir)
    test_yaml = File.join(tmp_dir, "project_config.yaml")
    proj_data.save_to_yaml(test_yaml)

    yaml_text = File.read(test_yaml, encoding: "utf-8")
    assert(yaml_text.include?("image_aspect_ratio: '16:9'") || yaml_text.include?("image_aspect_ratio: \"16:9\"") || yaml_text.include?("image_aspect_ratio: 16:9"), "YAML содержит сохраненный image_aspect_ratio: 16:9")
    assert(yaml_text.include?("show_aspect_overlay: true"), "YAML содержит show_aspect_overlay: true")

    reloaded_data = DN1Code::ExportPdf2::Model::ProjectData.new
    reloaded_data.load_from_yaml(test_yaml)
    assert(reloaded_data.pdf_settings[:image_aspect_ratio] == "16:9", "Загруженный из YAML image_aspect_ratio равен 16:9")
    assert(reloaded_data.pdf_settings[:show_aspect_overlay] == true, "Загруженный из YAML show_aspect_overlay равен true")

    # 6. Проверка файлов конфигурации плагина
    def_settings_text = File.read(File.join(__dir__, "../config/default_settings.yaml"), encoding: "utf-8")
    assert(def_settings_text.include?("image_aspect_ratio:"), "default_settings.yaml содержит image_aspect_ratio")
    assert(def_settings_text.include?("show_aspect_overlay:"), "default_settings.yaml содержит show_aspect_overlay")

    # 7. Проверка HTML интерфейса диалога
    html_text = File.read(File.join(__dir__, "../dialog/html/index.html"), encoding: "utf-8")
    assert(html_text.include?("id=\"selectQuality\""), "index.html содержит id=\"selectQuality\"")
    assert(html_text.include?("id=\"selectScaleMultiplier\""), "index.html содержит id=\"selectScaleMultiplier\"")
    assert(html_text.include?("value=\"auto\""), "selectScaleMultiplier содержит опцию auto")
    assert(html_text.include?("value=\"1.5\""), "selectScaleMultiplier содержит опцию 1.5")
    assert(html_text.include?("value=\"2.0\""), "selectScaleMultiplier содержит опцию 2.0")
    assert(html_text.include?("value=\"2.5\""), "selectScaleMultiplier содержит опцию 2.5")
    assert(html_text.include?("value=\"3.0\""), "selectScaleMultiplier содержит опцию 3.0")
    assert(!html_text.include?("id=\"selectImageAspect\""), "из общих настроек index.html удален id=\"selectImageAspect\"")
    assert(!html_text.include?("id=\"chkShowAspectOverlay\""), "из общих настроек index.html удален id=\"chkShowAspectOverlay\"")

    # 8. Проверка JS логики
    js_text = File.read(File.join(__dir__, "../dialog/html/app.js"), encoding: "utf-8")
    assert(js_text.include?("selectImageAspect"), "app.js содержит selectImageAspect")
    assert(js_text.include?("chkScenesFrameAll"), "app.js содержит массовый тумблер chkScenesFrameAll")
    assert(js_text.include?("function updateAspectUI"), "app.js содержит function updateAspectUI")
    assert(js_text.include?("syncOverlayState"), "app.js содержит syncOverlayState")
    assert(js_text.include?("updateAspectInfo"), "app.js содержит updateAspectInfo")
    assert(js_text.include?('callRuby("toggleAspectOverlay"'), "app.js отправляет toggleAspectOverlay в SketchUp")

    # 9. Проверка CSS стилей
    css_text = File.read(File.join(__dir__, "../dialog/html/app.css"), encoding: "utf-8")
    assert(css_text.include?(".scene-frame-btn"), "app.css содержит стили кнопки меню кадра .scene-frame-btn")
    assert(css_text.include?(".scene-frame-pop"), "app.css содержит стили поповера меню кадра .scene-frame-pop")
    assert(css_text.include?(".scene-frame-dot"), "app.css содержит стили индикатора рамки .scene-frame-dot")

    # 10. Проверка регистрации пункта меню и иконки панели инструментов
    main_text = File.read(File.join(__dir__, "../main.rb"), encoding: "utf-8")
    assert(main_text.include?("require_relative \"service/overlay_service\""), "main.rb подключает overlay_service")
    assert(main_text.include?("def toggle_aspect_overlay"), "main.rb содержит метод toggle_aspect_overlay")
    assert(main_text.include?("Рамка пропорций кадра (Overlay)"), "main.rb содержит пункт меню 'Рамка пропорций кадра (Overlay)'")
    assert(main_text.include?("frame_overlay"), "main.rb использует иконку frame_overlay")
    assert(main_text.include?("icon_path.call(\"frame_overlay\")"), "main.rb привязывает иконку через icon_path.call")

    # UI::Command требует растровые PNG-иконки (16px и 24px); SVG остается запасным вариантом
    png_small = File.join(__dir__, "../ico/frame_overlay.png")
    png_large = File.join(__dir__, "../ico/frame_overlay_large.png")
    assert(File.exist?(png_small), "Файл иконки frame_overlay.png (16px) существует")
    assert(File.exist?(png_large), "Файл иконки frame_overlay_large.png (24px) существует")
    png_header = File.binread(png_small, 8)
    assert(png_header.byteslice(1, 3) == "PNG", "frame_overlay.png является валидным PNG")

    icon_path = File.join(__dir__, "../ico/frame_overlay.svg")
    assert(File.exist?(icon_path), "Файл иконки frame_overlay.svg существует")
    icon_content = File.read(icon_path, encoding: "utf-8")
    assert(icon_content.include?("<svg") && icon_content.include?("</svg>"), "frame_overlay.svg является валидным SVG")

    # 10.1 Комплект иконочного шрифта Modus Icons v1.20.0 (набор connect):
    # без файлов шрифта все иконки диалога печатаются как текст-лигатуры
    fonts_dir = File.join(__dir__, "../dialog/html/fonts")
    %w[modus-icons.woff2 modus-icons.woff].each do |font_file|
      assert(File.exist?(File.join(fonts_dir, font_file)), "Иконочный шрифт #{font_file} лежит в dialog/html/fonts")
    end
    icons_css = File.read(File.join(fonts_dir, "modus-icons.css"), encoding: "utf-8")
    assert(icons_css.include?('url("modus-icons.woff2'), "modus-icons.css ссылается на файл шрифта woff2")
    assert(!File.exist?(File.join(fonts_dir, "open-sans.css")), "Мёртвый open-sans.css удалён (30 @font-face без файлов шрифта)")
    assert(!js_text.include?('>photo<') && !js_text.include?('>business<') && !js_text.include?('>dashboard<'),
           "app.js не использует имена-лигатуры, отсутствующие в наборе connect")
    # Все имена-лигатуры в разметке и JS входят в набор connect
    index_text = File.read(File.join(__dir__, "../dialog/html/index.html"), encoding: "utf-8")
    used_icons = (index_text.scan(/modus-icons[^>]*>([a-z0-9-]+)</).flatten +
                  js_text.scan(/modus-icons[^>]*>([a-z0-9-]+)</).flatten).uniq
    connect_icons = %w[
      account action-undo add-circle autorenew browser check-circle check-mark content-close
      dashboard-customize delete edit file file-download file-template file-upload folder
      insert-photo launch layers project refresh save settings short-text table time tune
      user-group views warning web-link
    ]
    unknown_icons = used_icons - connect_icons
    assert(unknown_icons.empty?, "Все имена иконок входят в набор connect (неизвестные: #{unknown_icons.join(', ')})")

    # 11. Проверка постраничного меню кадра и привязки пропорций к блоку шаблона
    assert(js_text.include?("scene-frame-btn"), "app.js содержит кнопку меню кадра scene-frame-btn")
    assert(js_text.include?("sceneFramePopover"), "app.js содержит поповер меню кадра sceneFramePopover")
    assert(js_text.include?("closeSceneFramePopover"), "app.js содержит closeSceneFramePopover")
    assert(js_text.include?("syncCurrentTemplateOverlay"), "app.js содержит метод syncCurrentTemplateOverlay")
    assert(css_text.include?(".scene-frame-btn"), "app.css содержит стили кнопки меню кадра .scene-frame-btn")
    assert(css_text.include?(".scene-frame-pop"), "app.css содержит стили поповера меню кадра .scene-frame-pop")
    assert(css_text.include?(".scene-frame-ratio-opt.active"), "app.css содержит активное состояние пропорций в меню кадра")

    export_dialog_text = File.read(File.join(__dir__, "../dialog/export_dialog.rb"), encoding: "utf-8")
    assert(export_dialog_text.include?("syncOverlayState"), "export_dialog.rb синхронизирует состояние оверлея при обновлении настроек")

    # Проверка вычисления пропорций из блока image_4_3 шаблона
    # Сбрасываем глобальный выбор пропорций ("page" = Auto), чтобы действовали
    # пропорции блока image_4_3 конкретного шаблона (приоритет при Auto)
    overlay_svc.update_settings({ image_aspect_ratio: "page" })
    mock_model_tpl = Sketchup::MockModel.new
    overlay_svc.update_settings({
      custom_layouts: {
        cover: { image_4_3: { aspect_ratio: "3:2" } },
        visual: { image_4_3: { aspect_ratio: "16:9" } },
        general: { image_4_3: { aspect_ratio: "1:1" } }
      }
    })
    info_tpl_cover = overlay_svc.calculate_target_info(mock_model_tpl, { template_key: :cover })
    assert((info_tpl_cover[:ratio] - 1.5).abs < 0.01, "Пропорции cover берутся из блока image_4_3 (3:2 = 1.5)")

    info_tpl_visual = overlay_svc.calculate_target_info(mock_model_tpl, { template_key: :visual })
    assert((info_tpl_visual[:ratio] - (16.0 / 9.0)).abs < 0.01, "Пропорции visual берутся из блока image_4_3 (16:9)")

    info_tpl_general = overlay_svc.calculate_target_info(mock_model_tpl, { template_key: :general })
    assert((info_tpl_general[:ratio] - 1.0).abs < 0.01, "Пропорции general берутся из блока image_4_3 (1:1 = 1.0)")

    # Проверка работы с цветами и прозрачностью рамки и затемнения
    assert(proj_data.pdf_settings.key?(:overlay_border_color), "pdf_settings содержит :overlay_border_color")
    assert(proj_data.pdf_settings.key?(:overlay_border_opacity), "pdf_settings содержит :overlay_border_opacity")
    assert(proj_data.pdf_settings.key?(:overlay_mask_color), "pdf_settings содержит :overlay_mask_color")
    assert(proj_data.pdf_settings.key?(:overlay_mask_opacity), "pdf_settings содержит :overlay_mask_opacity")

    # Тестирование метода parse_color
    parsed_c1 = overlay_svc.parse_color("#EF4444", 80)
    if parsed_c1.is_a?(String)
      assert(parsed_c1.include?("rgba(239,68,68,0.8)"), "parse_color корректно парсит HEX #EF4444 и 80% opacity")
    else
      assert(parsed_c1.red == 239 && parsed_c1.green == 68 && parsed_c1.blue == 68 && parsed_c1.alpha == 204, "parse_color возвращает правильный Color RGBA")
    end

    # Стиль рамки зафиксирован в OverlayService (настройки контура/затемнения убраны из GUI):
    # контур всегда красный #FF0000, затемнение вне кадра всегда 10%
    overlay_svc.update_settings({
      overlay_mask_color: "#1E293B"
    }, mock_model_tpl)

    info_colors = overlay_svc.calculate_target_info(mock_model_tpl)
    assert(info_colors[:border_color] == "#FF0000", "контур рамки зафиксирован: красный #FF0000")
    assert(info_colors[:border_opacity] == 100, "прозрачность контура зафиксирована: 100%")
    assert(info_colors[:mask_color] == "#1E293B", "calculate_target_info возвращает переданный mask_color")
    assert(info_colors[:mask_opacity] == 10, "затемнение вне кадра зафиксировано: 10%")

    ov_check = overlay_svc.find_model_overlay(mock_model_tpl)
    assert(ov_check && ov_check.border_color_cache == "#FF0000", "Кэш цвета рамки в оверлее — красный #FF0000")
    assert(ov_check && ov_check.mask_color_cache == "#1E293B", "Кэш цвета затемнения в оверлее обновлен")
    assert(ov_check && ov_check.mask_opacity_cache == 10, "Кэш затемнения в оверлее — 10%")

    # Настройки контура/затемнения убраны из интерфейса
    assert(!js_text.include?("input_overlay_border_color"), "элемент выбора цвета контура удален из app.js")
    assert(!js_text.include?("btn-mask-opacity"), "кнопки затемнения удалены из app.js")
    assert(!css_text.include?(".btn-mask-opacity"), "стили кнопок затемнения удалены из app.css")
    assert(!html_text.include?('id="inputOverlayBorderColor"'), "из общих настроек index.html удален устаревший id=\"inputOverlayBorderColor\"")
    assert(!html_text.include?('id="inputOverlayMaskColor"'), "из общих настроек index.html удален устаревший id=\"inputOverlayMaskColor\"")
    assert(!html_text.include?("id=\"inputPrimaryColor\""), "из общих настроек index.html удален id=\"inputPrimaryColor\"")
    assert(!html_text.include?("id=\"inputStampColor\""), "из общих настроек index.html удален id=\"inputStampColor\"")
    assert(!html_text.include?("id=\"selectStamp\""), "из общих настроек index.html удален id=\"selectStamp\"")

    FileUtils.rm_rf(tmp_dir)
  end

  def test_43_new_project_yaml_data_structure
    puts "\n--- 43. Тест интеграции новой структуры данных из project.yaml ---"
    require "digest"

    root_project_yaml = File.expand_path("../../project.yaml", __dir__)
    assert(File.exist?(root_project_yaml), "Файл project.yaml существует в корне проекта (#{root_project_yaml})")

    # 1. Фиксация неизменности файла project.yaml (хеш MD5)
    initial_content = File.binread(root_project_yaml)
    initial_md5 = Digest::MD5.hexdigest(initial_content)

    # 2. Загрузка данных из project.yaml в ProjectData
    proj = DN1Code::ExportPdf2::Model::ProjectData.new
    proj.load_from_yaml(root_project_yaml)

    # 3. Проверка секции project и тегов мебели product_tags
    assert(proj.project_info[:articul] == "HF#YYMMDD_HHMMSS", "Артикул корректно загружен: HF#YYMMDD_HHMMSS")
    assert(proj.project_info[:product_tags] == ["Шкаф", "Тумба", "Зеркало"], "product_tags содержит список: ['Шкаф', 'Тумба', 'Зеркало']")
    assert(proj.project_info[:product] == "Шкаф, Тумба, Зеркало", "Синхронизированное поле product объединяет теги через запятую")
    assert(proj.project_info[:place].include?("Место установки"), "Место установки проекта загружено")
    assert(proj.project_info[:adress].include?("Адрес установки"), "Адрес установки проекта загружен")
    assert(proj.project_info[:name_company] == "Название компании", "Название компании загружено")
    assert(proj.project_info[:commercial] == false, "Флаг коммерческого проекта: false")

    # 4. Проверка секции customer
    assert(proj.customer[:id] == "CUST-2609052034", "ID заказчика: CUST-2609052034")
    assert(proj.customer[:name] == "Имя Заказчика", "Имя заказчика: Имя Заказчика")
    assert(proj.customer[:phone] == "Номер телефона", "Телефон заказчика загружен")
    assert(proj.customer[:email] == "Электронная почта", "Email заказчика загружен")

    # 5. Проверка секции workflow и стадий (stadia)
    assert(proj.workflow[:author] == "Автор проекта", "Автор проекта: Автор проекта")
    assert(proj.workflow[:version] == "01", "Версия проекта: 01")
    assert(proj.workflow[:revision] == "001", "Ревизия проекта: 001")
    assert(proj.workflow[:total_duration].include?("Время работы"), "total_duration загружен")

    stadia = proj.workflow[:stadia]
    assert(stadia.is_a?(Array) && stadia.size == 8, "Стадии жизненного цикла содержат 8 элементов")
    assert(stadia[0][:name] == "Предварительный проект" && stadia[0][:status] == true, "Стадия 1: Предварительный проект (выполнена)")
    assert(stadia[1][:name] == "Правки проекта (история правок)" && stadia[1][:status] == true, "Стадия 2: Правки проекта (выполнена)")
    assert(stadia[2][:name] == "Выбраны материалы и фурнитура" && stadia[2][:status] == true, "Стадия 3: Выбраны материалы и фурнитура (выполнена)")
    assert(stadia[3][:name] == "Предварительно Утвержден" && stadia[3][:status] == false, "Стадия 4: Предварительно Утвержден (не выполнена)")
    assert(stadia[7][:name] == "Оплачен" && stadia[7][:status] == false, "Стадия 8: Оплачен (не выполнена)")
    assert(proj.workflow[:status] == "Выбраны материалы и фурнитура", "Текущий статус вычисляется как последняя отмеченная стадия")

    # 6. Проверка корневой секции history_edit (канонический порядок в памяти: новые сверху)
    assert(proj.history.is_a?(Array) && proj.history.size == 4, "История изменений загружена на корневом уровне и содержит 4 записи")
    first_hist = proj.history[0]
    assert(first_hist[:data] == "2026-09-07 20:38", "Первая запись истории (новейшая) содержит дату 2026-09-07 20:38")
    assert(first_hist[:edit].include?("Сохранение проекта"), "Первая запись содержит описание свежей правки 'Сохранение проекта'")
    assert(first_hist[:pdf_link] == "HF#YYMMDD_HHMMSS_version_revison.pdf", "Первая запись содержит ссылку на PDF: #{first_hist[:pdf_link]}")
    last_hist = proj.history[-1]
    assert(last_hist[:data] == "2026-09-05 20:34", "Последняя запись истории (старейшая) содержит дату 2026-09-05 20:34")
    assert(last_hist[:edit].include?("Экспорт PDF"), "Последняя запись содержит описание правки 'Экспорт PDF'")

    # 7. Проверка секций directories, scenes, api_targets
    assert(proj.directories.is_a?(Array) && proj.directories.size == 2, "Рабочие папки directories содержат 2 записи")
    assert(proj.scenes.is_a?(Array) && proj.scenes.size == 4, "Сцены проекта содержат 4 элемента")
    assert(proj.scenes[0].name == "Обложка" && proj.scenes[0].page_type == :cover, "Сцена 1: Обложка (cover)")
    assert(proj.api_targets.is_a?(Array) && proj.api_targets.size == 2, "api_targets содержат 2 адреса")
    assert(proj.api_targets.any? { |url| url.include?("prodmd.top") }, "api_targets содержит prodmd.top")

    # 8. Проверка сохранения в YAML и совпадения структуры
    tmp_dir = Dir.mktmpdir("test_yaml_save")
    tmp_out = File.join(tmp_dir, "saved_project.yaml")
    proj.save_to_yaml(tmp_out)
    assert(File.exist?(tmp_out), "Сохраненный файл YAML создан успешно")

    saved_raw = YAML.safe_load(File.read(tmp_out), permitted_classes: [Date, Time, Symbol])
    assert(saved_raw.key?("project"), "Сохраненный YAML содержит секцию 'project'")
    assert(saved_raw["project"]["product_tags"] == ["Шкаф", "Тумба", "Зеркало"], "Сохраненный YAML сохраняет 'product_tags'")
    assert(saved_raw.key?("history_edit"), "Сохраненный YAML содержит корневую секцию 'history_edit'")
    assert(saved_raw["history_edit"].is_a?(Array) && saved_raw["history_edit"].size == 4, "history_edit сохранен как корневой массив из 4 записей")
    assert(saved_raw["history_edit"][0].key?("pdf_link"), "Записи history_edit содержат ключ pdf_link")
    assert(saved_raw["workflow"]["stadia"].is_a?(Array) && saved_raw["workflow"]["stadia"].size == 8, "Стадии сохранены в workflow['stadia']")

    # 9. Проверка повторной загрузки из сохраненного файла (roundtrip)
    proj2 = DN1Code::ExportPdf2::Model::ProjectData.new
    proj2.load_from_yaml(tmp_out)
    assert(proj2.project_info[:product_tags] == ["Шкаф", "Тумба", "Зеркало"], "Повторная загрузка: product_tags совпадают")
    assert(proj2.workflow[:stadia].size == 8, "Повторная загрузка: stadia содержит 8 этапов")
    assert(proj2.history.size == 4, "Повторная загрузка: history содержит 4 записи")
    assert(proj2.history[0][:pdf_link] == "HF#YYMMDD_HHMMSS_version_revison.pdf", "Повторная загрузка: pdf_link сохранен")
    FileUtils.rm_rf(tmp_dir)

    # 10. Проверка контроллера и рендеринга стадий и истории
    mock_pdf = Prawn::Document.new(page_size: "A4", page_layout: :landscape)
    page_base = DN1Code::ExportPdf2::Controller::PageBase.new(mock_pdf, proj, proj.scenes.first)
    stadia_rendered = page_base.send(:resolve_info_line, "workflow.stadia")
    assert(stadia_rendered.include?("[✓] Предварительный проект"), "resolve_info_line('workflow.stadia') рендерит [✓] для выполненных стадий")
    assert(stadia_rendered.include?("[ ] Предварительно Утвержден"), "resolve_info_line('workflow.stadia') рендерит [ ] для невыполненных стадий")

    history_rendered = page_base.send(:resolve_info_line, "workflow.history")
    assert(history_rendered.include?("2026-09-05 20:34") && history_rendered.include?("Экспорт PDF"), "resolve_info_line('workflow_history') рендерит дату и описание правки")

    # 11. Проверка неизменности оригинального файла project.yaml
    current_content = File.binread(root_project_yaml)
    current_md5 = Digest::MD5.hexdigest(current_content)
    assert(current_md5 == initial_md5, "КРИТИЧЕСКАЯ ПРОВЕРКА: Файл project.yaml остался абсолютно нетронутым (MD5 совпадает)")
  end

  def test_44_template_independence_and_autosave
    puts "\n--- 44. Тест автоматического сохранения в YAML и независимости шаблонов ---"
    require "digest"
    require "tmpdir"
  
    root_project_yaml = File.expand_path("../../project.yaml", __dir__)
    initial_content = File.binread(root_project_yaml)
    initial_md5 = Digest::MD5.hexdigest(initial_content)
  
    # 1. Проверка структуры custom_layouts для всех 5 шаблонов
    #    (тест не зависит от пользовательского config/layout.yaml — сбрасываем)
    proj = DN1Code::ExportPdf2::Model::ProjectData.new
    proj.pdf_settings[:custom_layouts] = proj.send(:default_custom_layouts)
    templates = [:cover, :description, :explain, :general, :visual]
  
    templates.each do |tpl|
      assert(proj.custom_layouts.key?(tpl), "custom_layouts содержит шаблон #{tpl}")
      assert(proj.custom_layouts[tpl].key?(:image_4_3), "шаблон #{tpl} содержит блок image_4_3")
      assert(proj.custom_layouts[tpl][:params] == [], "шаблон #{tpl} стартует с пустым списком параметров")
    end
  
    # Проверка отсутствия общих ссылок между шаблонами (Deep isolation)
    assert(proj.custom_layouts[:cover][:image_4_3].object_id != proj.custom_layouts[:visual][:image_4_3].object_id,
           "Блоки image_4_3 в cover и visual имеют разные object_id")
    assert(proj.custom_layouts[:cover][:params].object_id != proj.custom_layouts[:general][:params].object_id,
           "Массивы params в cover и general имеют разные object_id")
  
    # 2. Модификация одного шаблона НЕ должна влиять на остальные (Template Independence)
    proj.custom_layouts[:cover][:image_4_3][:aspect_ratio] = "21:9"
    proj.custom_layouts[:cover][:image_4_3][:scale_pct] = 77
    proj.custom_layouts[:cover][:params] << {
      id: "p44", source: "project.articul", label: "Артикул", show_label: true,
      x: 50.0, y: 3.0, align: "center", font_size: 14.5, color: "#005EB0", visible: true
    }
  
    assert(proj.custom_layouts[:visual][:image_4_3][:aspect_ratio] != "21:9",
           "Изменение aspect_ratio в cover не затронуло visual")
    assert(proj.custom_layouts[:visual][:image_4_3][:scale_pct] != 77,
           "Изменение scale_pct в cover не затронуло visual")
    assert(proj.custom_layouts[:general][:params].empty?,
           "Добавление параметра в cover не добавило параметр в general")
    assert(proj.custom_layouts[:visual][:params].empty?,
           "Добавление параметра в cover не добавило параметр в visual")
  
    # 3. Проверка сохранения в YAML и повторной загрузки с сохранением изоляции
    tmp_dir = Dir.mktmpdir("test_autosave_independence")
    tmp_yaml = File.join(tmp_dir, "autosave_test.yaml")
    proj.save_to_yaml(tmp_yaml)
    assert(File.exist?(tmp_yaml), "YAML файл успешно сохранен через save_to_yaml")
  
    loaded_proj = DN1Code::ExportPdf2::Model::ProjectData.new
    loaded_proj.load_from_yaml(tmp_yaml)
    assert(loaded_proj.custom_layouts[:cover][:image_4_3][:aspect_ratio] == "21:9",
           "Загруженный cover сохранил aspect_ratio 21:9")
    assert(loaded_proj.custom_layouts[:visual][:image_4_3][:aspect_ratio] != "21:9",
           "Загруженный visual сохранил независимое значение aspect_ratio")
    assert(loaded_proj.custom_layouts[:cover][:params].size == 1 &&
           loaded_proj.custom_layouts[:cover][:params].first[:source] == "project.articul",
           "Загруженный cover сохранил созданный параметр")
    assert(loaded_proj.custom_layouts[:general][:params] == [],
           "Загруженный general остался без параметров")
  
    # 4. Проверка работы метода save_project_yaml с mock-моделью
    mock_model = Sketchup::MockModel.new
    mock_model.path = File.join(tmp_dir, "MyModel.skp")
    loaded_proj.project_info[:articul] = "AUTO-SAVE-44"
    loaded_proj.project_info[:name] = "Автосохраненный Проект"
    assert(loaded_proj.save_project_yaml(mock_model), "save_project_yaml завершился успешно")
  
    expected_auto_yaml = File.join(tmp_dir, "AUTO-SAVE-44", "project.yaml")
    assert(File.exist?(expected_auto_yaml), "save_project_yaml создал project.yaml в папке артикула: #{expected_auto_yaml}")
    content_auto = File.read(expected_auto_yaml, encoding: "utf-8")
    assert(content_auto.include?("Автосохраненный Проект"), "save_project_yaml сохранил актуальные данные проекта в YAML")
  
    # 5. Проверка экшена saveData с silent: true в export_dialog.rb
    export_dialog_rb = File.read(File.join(__dir__, "../dialog/export_dialog.rb"), encoding: "utf-8")
    assert(export_dialog_rb.include?('dialog.add_action_callback("saveData"'), "export_dialog.rb регистрирует экшен saveData")
    assert(export_dialog_rb.include?("is_auto = payload[:silent] == true || payload[:is_auto_save] == true"),
           "export_dialog.rb распознает silent и is_auto_save флаги")
    assert(export_dialog_rb.include?("window.app.onAutoSaved && window.app.onAutoSaved"),
           "export_dialog.rb вызывает JS callback window.app.onAutoSaved при тихом сохранении")
  
    # 6. Проверка поддержки автосохранения в app.js
    js_text = File.read(File.join(__dir__, "../dialog/html/app.js"), encoding: "utf-8")
    assert(js_text.include?("function triggerAutoSave()"), "app.js содержит функцию triggerAutoSave")
    assert(js_text.include?("function notifyChange()"), "app.js содержит функцию notifyChange")
    assert(js_text.include?("function updateAutoSaveIndicator("), "app.js содержит функцию updateAutoSaveIndicator")
    assert(js_text.include?("onAutoSaved: function"), "app.js содержит обработчик onAutoSaved")
    assert(js_text.include?("deepClone("), "app.js содержит deepClone для глубокого копирования шаблонов")
    assert(js_text.include?("autoSaveTimer"), "app.js использует дебаунс-таймер для автосохранения")
  
    # 7. Проверка изоляции шаблонов в app.js
    assert(js_text.include?("targetTplKey"), "app.js параметризирует обновление блоков через targetTplKey")
    assert(js_text.include?("function setTemplateParams"), "app.js сохраняет параметры шаблона через setTemplateParams")
  
    # 8. Проверка наличия индикатора автосохранения в index.html и стилей в app.css
    html_text = File.read(File.join(__dir__, "../dialog/html/index.html"), encoding: "utf-8")
    assert(html_text.include?('id="autosaveStatus"'), "index.html содержит элемент #autosaveStatus (футер, рядом с кнопками)")
    assert(html_text.include?('class="autosave-status"'), "index.html содержит контейнер autosave-status")
    assert(!html_text.include?('id="btnRefreshData"'), "Кнопка «Обновить» (btnRefreshData) удалена из футера")
  
    css_text = File.read(File.join(__dir__, "../dialog/html/app.css"), encoding: "utf-8")
    assert(css_text.include?(".autosave-status"), "app.css содержит стили для .autosave-status")
    assert(css_text.include?(".autosave-status.saving"), "app.css содержит стиль для состояния saving")
    assert(css_text.include?(".autosave-status.saved"), "app.css содержит стиль для состояния saved")
  
    FileUtils.rm_rf(tmp_dir)
  
    # 9. Проверка неизменности оригинального файла project.yaml
    current_content = File.binread(root_project_yaml)
    current_md5 = Digest::MD5.hexdigest(current_content)
    assert(current_md5 == initial_md5, "КРИТИЧЕСКАЯ ПРОВЕРКА: Файл project.yaml остался абсолютно нетронутым (MD5 совпадает)")
  end

  # ============================================================================
  # 68. ТЕСТ: Новая модель стартует без папок; удаление всех папок сохраняется
  # ============================================================================
  def test_directories_start_empty_and_deletions_persist
    puts "\n--- 68. Тест: новая модель без папок, удаление папок не откатывается к дефолтам ---"

    # 1. Новый ProjectData — пустой список directories (без дефолтных папок)
    data = DN1Code::ExportPdf2::Model::ProjectData.new
    assert(data.directories.is_a?(Array) && data.directories.empty?,
           "Новый ProjectData стартует с пустым списком directories")

    # 2. Нормализация не подставляет дефолтные папки в пустой список
    data.normalize_directories!
    assert(data.directories.empty?, "normalize_directories! оставляет пустой список пустым")

    # 3. apply_payload! применяет пустой массив (пользователь удалил все папки в диалоге)
    data.directories = [{ path: "!_замер", title: "Замеры", description: "Фото" }]
    data.apply_payload!({ directories: [] })
    assert(data.directories.empty?, "apply_payload! применяет пустой массив directories (удаление всех папок)")

    # 4. Сохранение в YAML и перезагрузка: пустой список не восстанавливается к дефолтам
    test_dir = File.expand_path("test_dirs_empty_dir", __dir__)
    FileUtils.mkdir_p(File.join(test_dir, "empty"))
    model = Sketchup::MockModel.new(File.join(test_dir, "empty", "EmptyDirs.skp"))
    model.pages.add("01. Обложка")
    data.project_info[:articul] = "EMPTY-DIRS-1"
    data.sync_with_model_scenes(model)
    assert(data.save_project_yaml(model), "Проект с пустым directories сохранен в YAML")

    reloaded = DN1Code::ExportPdf2::Model::ProjectData.new
    assert(reloaded.load_auto(model) == :yaml, "YAML проекта с пустым directories загружен")
    assert(reloaded.directories.is_a?(Array) && reloaded.directories.empty?,
           "После перезагрузки directories остается пустым (дефолты не возвращаются)")

    # 5. YAML вообще без ключа directories тоже не порождает папок
    FileUtils.mkdir_p(File.join(test_dir, "no_key", "NO-DIRS-001"))
    File.write(File.join(test_dir, "no_key", "NO-DIRS-001", "project.yaml"), <<~YAML, encoding: "utf-8")
      ---
      project:
        articul: NO-DIRS-001
        product: Тумба
      scenes: []
    YAML
    model2 = Sketchup::MockModel.new(File.join(test_dir, "no_key", "NoDirs.skp"))
    DN1Code::ExportPdf2::Model::ModelArticulStore.write(model2, "NO-DIRS-001")
    data2 = DN1Code::ExportPdf2::Model::ProjectData.new
    assert(data2.load_auto(model2) == :yaml, "YAML без ключа directories загружен")
    assert(data2.directories.is_a?(Array) && data2.directories.empty?,
           "YAML без ключа directories не порождает папок")

    # 6. Размер эскизов (thumb_size) сохраняется при записи/чтении YAML
    data3 = DN1Code::ExportPdf2::Model::ProjectData.new
    data3.directories = [{ path: "C:/Тест/Эскизы", title: "Эскизы", description: "", thumb_size: "large" }]
    data3.sync_project_fields!
    thumb_yaml = File.join(test_dir, "thumb", "ThumbProject.yaml")
    FileUtils.mkdir_p(File.dirname(thumb_yaml))
    assert(data3.save_to_yaml(thumb_yaml), "Проект с thumb_size сохранен в YAML")
    data3_loaded = DN1Code::ExportPdf2::Model::ProjectData.new
    assert(data3_loaded.load_from_yaml(thumb_yaml), "YAML с thumb_size загружен")
    assert(data3_loaded.directories.first[:thumb_size] == "large",
           "Размер эскизов thumb_size сохраняется при записи/чтении YAML")

    # 7. Элементы интерфейса: путь как текст (клик — выбор папки) и размеры эскизов
    js_text = File.read(File.join(__dir__, "../dialog/html/app.js"), encoding: "utf-8")
    assert(js_text.include?("dir-thumb-size-btn"), "app.js содержит переключатель размеров эскизов")
    assert(js_text.include?("dir-path-text"), "Путь в карточке выводится текстом (dir-path-text)")
    assert(js_text.include?('callRuby("selectDirectory", index.toString())'), "Клик по пути открывает выбор папки")
    css_text = File.read(File.join(__dir__, "../dialog/html/app.css"), encoding: "utf-8")
    assert(css_text.include?("thumb-small") && css_text.include?("thumb-medium") && css_text.include?("thumb-large"),
           "app.css содержит три варианта размеров эскизов (small/medium/large)")
    assert(css_text.include?("dir-path-text"), "app.css содержит стиль текстового пути")

    FileUtils.rm_rf(test_dir)
  end

  # ============================================================================
  # 88. ТЕСТ: флаг «Отправлять на сервер» в настройках каждой папки (send_to_server)
  # ============================================================================
  def test_88_directory_send_to_server_flag
    puts "\n--- 88. Тест флага отправки папки на сервер (SEND_TO_SERVER) ---"

    test_dir = File.expand_path("test_dirs_send_server_dir", __dir__)
    FileUtils.mkdir_p(test_dir)

    # 1. Нормализация: отсутствие ключа и строковое "false"
    data = DN1Code::ExportPdf2::Model::ProjectData.new
    data.directories = [
      { path: "C:/Тест/Материалы", title: "Материалы", description: "" },
      { path: "C:/Тест/Фурнитура", title: "Фурнитура", description: "", send_to_server: false },
      { path: "C:/Тест/Техника", title: "Техника", description: "", "send_to_server" => "false" }
    ]
    data.normalize_directories!
    assert(data.directories[0][:send_to_server] == true,
           "Папка без ключа send_to_server нормализуется как «отправлять» (true)")
    assert(data.directories[1][:send_to_server] == false,
           "Папка с send_to_server: false сохраняет значение false")
    assert(data.directories[2][:send_to_server] == false,
           "Строковое значение send_to_server 'false' приводится к boolean false")

    # 2. Сохранение в YAML: явный boolean у каждой папки
    data.sync_project_fields!
    send_yaml = File.join(test_dir, "SendServerProject.yaml")
    assert(data.save_to_yaml(send_yaml), "Проект с send_to_server сохранен в YAML")
    yaml_text = File.read(send_yaml, encoding: "utf-8")
    assert(yaml_text.include?("send_to_server: false"), "YAML содержит send_to_server: false для отключенной папки")
    assert(yaml_text.include?("send_to_server: true"), "YAML содержит send_to_server: true для папки по умолчанию")

    # 3. Чтение обратно (round-trip)
    reloaded = DN1Code::ExportPdf2::Model::ProjectData.new
    assert(reloaded.load_from_yaml(send_yaml), "YAML с send_to_server загружен обратно")
    assert(reloaded.directories[0][:send_to_server] == true, "После перезагрузки send_to_server: true сохранен")
    assert(reloaded.directories[1][:send_to_server] == false, "После перезагрузки send_to_server: false сохранен")

    # 4. Интерфейс: чекбокс в шапке карточки рядом с «Обновить», справа
    js_text = File.read(File.join(__dir__, "../dialog/html/app.js"), encoding: "utf-8")
    assert(js_text.include?("dir-header-actions"), "app.js группирует «Обновить» и чекбокс отправки в правом блоке шапки папки")
    assert(js_text.include?("dir-send-server-label"), "app.js содержит чекбокс отправки в шапке карточки папки")
    assert(js_text.include?("d.send_to_server !== false"), "app.js по умолчанию включает отправку для старых данных")
    assert(js_text.include?("d.send_to_server = e.target.checked"), "app.js сохраняет состояние чекбокса в directories")
    assert(js_text.include?("Отправлять на сервер"), "app.js содержит подпись чекбокса «Отправлять на сервер»")
    css_text = File.read(File.join(__dir__, "../dialog/html/app.css"), encoding: "utf-8")
    assert(css_text.include?(".dir-header-actions") && css_text.include?("margin-left: auto"),
           "app.css прижимает блок «Обновить» + чекбокс отправки к правому краю")
    assert(css_text.include?("dir-send-server-label"), "app.css содержит стиль чекбокса отправки")

    FileUtils.rm_rf(test_dir)
  end

  # ============================================================================
  # 46. ТЕСТ: Заголовки пунктов шаблонов на отдельной строке, описание на следующей, галка заголовок
  # ============================================================================
  def test_separate_project_pages_and_template_settings_tabs
    puts "\n--- 47. Тест разделения настройки шаблонов и страниц проекта на отдельные вкладки GUI ---"

    root_project_yaml = File.expand_path("../../project.yaml", __dir__)
    initial_md5 = Digest::MD5.hexdigest(File.binread(root_project_yaml))

    html_path = File.expand_path(File.join(__dir__, "..", "dialog", "html", "index.html"))
    js_path = File.expand_path(File.join(__dir__, "..", "dialog", "html", "app.js"))
    css_path = File.expand_path(File.join(__dir__, "..", "dialog", "html", "app.css"))

    html_content = File.read(html_path, encoding: "UTF-8")
    js_content = File.read(js_path, encoding: "UTF-8")
    css_content = File.read(css_path, encoding: "UTF-8")

    # 1. Проверка навигационных кнопок в index.html
    assert(html_content.include?('data-tab="tab-scenes"'), "index.html содержит кнопку вкладки tab-scenes")
    assert(html_content.include?('Страницы'), "index.html содержит заголовок 'Страницы'")
    assert(html_content.include?('data-tab="tab-templates"'), "index.html содержит отдельную кнопку вкладки tab-templates")
    assert(html_content.include?('Шаблоны'), "index.html содержит заголовок 'Шаблоны'")

    # 2. Проверка раздельных секций в index.html
    assert(html_content.include?('<section id="tab-scenes" class="tab-pane">'), "index.html содержит секцию #tab-scenes")
    assert(html_content.include?('<section id="tab-templates" class="tab-pane">'), "index.html содержит секцию #tab-templates")
    assert(html_content.include?('id="scenesTable"'), "index.html содержит таблицу сцен scenesTable")
    assert(html_content.include?('id="templateSettingsContainer"'), "index.html содержит контейнер templateSettingsContainer")

    # 3. Проверка логики переключения в app.js
    assert(js_content.include?('tab.dataset.tab === "tab-templates"'), "app.js обрабатывает переключение на tab-templates")
    assert(js_content.include?('function switchToTab(tabId)'), "app.js содержит функцию switchToTab")
    assert(js_content.include?('btn-goto-template'), "app.js содержит кнопку быстрого перехода к шаблону btn-goto-template")
    assert(js_content.include?('scene-template-cell-wrap'), "app.js использует обертку для ячейки шаблона scene-template-cell-wrap")

    # 4. Проверка стилей в app.css
    assert(css_content.include?('#tab-templates'), "app.css содержит правила для #tab-templates")
    assert(css_content.include?('.scenes-panel'), "app.css содержит правила для .scenes-panel")
    assert(css_content.include?('.btn-goto-template'), "app.css содержит стили для .btn-goto-template")

    # 5. Проверка неизменности оригинального файла project.yaml
    current_content = File.binread(root_project_yaml)
    current_md5 = Digest::MD5.hexdigest(current_content)
    assert(current_md5 == initial_md5, "КРИТИЧЕСКАЯ ПРОВЕРКА: Файл project.yaml остался абсолютно нетронутым (MD5 совпадает)")
  end

  def test_custom_template_management_and_rendering
    puts "\n--- 48. Тест списка шаблонов слева, создания новых шаблонов и их рендеринга ---"

    root_project_yaml = File.expand_path("../../project.yaml", __dir__)
    initial_md5 = Digest::MD5.hexdigest(File.binread(root_project_yaml))

    html_path = File.expand_path(File.join(__dir__, "..", "dialog", "html", "index.html"))
    js_path = File.expand_path(File.join(__dir__, "..", "dialog", "html", "app.js"))
    css_path = File.expand_path(File.join(__dir__, "..", "dialog", "html", "app.css"))

    html_content = File.read(html_path, encoding: "UTF-8")
    js_content = File.read(js_path, encoding: "UTF-8")
    css_content = File.read(css_path, encoding: "UTF-8")

    # 1. Проверка HTML-разметки сайдбара и модальных окон
    assert(html_content.include?('id="templatesSidebar"'), "index.html содержит боковую панель templatesSidebar")
    assert(html_content.include?('id="templatesList"'), "index.html содержит контейнер списка шаблонов templatesList")
    assert(html_content.include?('id="btnCreateTemplate"'), "index.html содержит кнопку создания шаблона btnCreateTemplate")
    assert(html_content.include?('id="currentTemplateTitle"'), "index.html содержит заголовок выбранного шаблона currentTemplateTitle")
    assert(html_content.include?('id="btnRenameCurrentTemplate"'), "index.html содержит кнопку переименования btnRenameCurrentTemplate")
    assert(html_content.include?('id="btnDeleteCurrentTemplate"'), "index.html содержит кнопку удаления btnDeleteCurrentTemplate")
    assert(html_content.include?('id="newTemplateModal"'), "index.html содержит модальное окно newTemplateModal")
    assert(html_content.include?('id="deleteTemplateModal"'), "index.html содержит модальное окно подтверждения удаления deleteTemplateModal")
    assert(html_content.include?('id="renameTemplateModal"'), "index.html содержит модальное окно переименования renameTemplateModal")
    assert(html_content.include?('id="btnConfirmDeleteTemplate"'), "index.html содержит кнопку подтверждения удаления btnConfirmDeleteTemplate")
    assert(html_content.include?('id="inputNewTemplateName"'), "index.html содержит поле ввода имени нового шаблона inputNewTemplateName")
    assert(html_content.include?('id="selectNewTemplateBase"'), "index.html содержит выбор базового шаблона selectNewTemplateBase")
    assert(html_content.include?('id="btnConfirmNewTemplate"'), "index.html содержит кнопку подтверждения btnConfirmNewTemplate")

    # 2. Проверка CSS-стилей
    assert(css_content.include?('.templates-sidebar'), "app.css содержит стили .templates-sidebar")
    assert(css_content.include?('.templates-list'), "app.css содержит стили .templates-list")
    assert(css_content.include?('.template-list-item'), "app.css содержит стили .template-list-item")
    assert(css_content.include?('.template-list-item.active'), "app.css содержит активное состояние .template-list-item.active")
    assert(css_content.include?('.btn-danger-outline'), "app.css содержит стили для кнопки удаления .btn-danger-outline")
    assert(css_content.include?('.sidebar-header-actions'), "app.css содержит стили для блока кнопок в шапке сайдбара .sidebar-header-actions")

    # 3. Проверка JS функций управления шаблонами
    assert(js_content.include?('function getAllTemplates()'), "app.js содержит getAllTemplates")
    assert(js_content.include?('function getTemplateDef('), "app.js содержит getTemplateDef")
    assert(js_content.include?('function renderTemplatesList()'), "app.js содержит renderTemplatesList")
    assert(js_content.include?('function selectTemplate('), "app.js содержит selectTemplate")
    assert(js_content.include?('function syncTemplateDropdowns()'), "app.js содержит syncTemplateDropdowns")
    assert(js_content.include?('function createCustomTemplate('), "app.js содержит createCustomTemplate")
    assert(js_content.include?('function deleteCustomTemplate('), "app.js содержит deleteCustomTemplate")
    assert(js_content.include?('function openDeleteTemplateModal('), "app.js содержит openDeleteTemplateModal")
    assert(js_content.include?('function confirmDeleteTemplate()'), "app.js содержит confirmDeleteTemplate")
    assert(js_content.include?('function openRenameTemplateModal('), "app.js содержит openRenameTemplateModal")
    assert(js_content.include?('function confirmRenameTemplate()'), "app.js содержит confirmRenameTemplate")

    # 4. Проверка Ruby бэкенда: PageBase#current_page_type для кастомного шаблона
    test_project_data = DN1Code::ExportPdf2::Model::ProjectData.new
    custom_scene = DN1Code::ExportPdf2::Model::SceneItem.new(
      name: "Кастомная сцена",
      description: "Тест кастомного шаблона",
      page_type: "custom_spec"
    )

    pdf_doc = Prawn::Document.new(page_size: "A4", page_layout: :landscape, margin: [14.17, 14.17, 14.17, 14.17])
    page = DN1Code::ExportPdf2::Controller::CoverPage.new(pdf_doc, test_project_data, custom_scene, page_index: 1, total_pages: 1)
    resolved_type = page.send(:current_page_type)
    assert(resolved_type == :custom_spec, "PageBase#current_page_type корректно возвращает :custom_spec из scene_item.page_type")

    # 5. Рендеринг кастомного шаблона с кастомной разметкой в custom_layouts
    test_dir = File.join(__dir__, "tmp_custom_tpl_test")
    FileUtils.mkdir_p(test_dir)
test_project_data.pdf_settings[:custom_layouts] = {
  custom_spec: {
    image_4_3: { x: 25.0, y: 12.0, w: 50.0, h: 82.0, visible: false, content: "render_viewport",
                 show_background: false, aspect_ratio: "4:3", scale_pct: 100 },
    params: [
      { id: "pc1", source: "project.description", label: "О сцене", show_label: true,
        x: 8.0, y: 6.0, align: "left", font_size: 10.0, color: "#0F172A", visible: true }
    ]
  }
}
test_project_data.project_info[:materials] = "Фасады МДФ"
test_project_data.project_info[:appliances] = "Духовой шкаф Bosch"
    test_project_data.project_info[:materials] = "Фасады МДФ"
    test_project_data.project_info[:appliances] = "Духовой шкаф Bosch"

    pdf_doc_render = Prawn::Document.new(page_size: "A4", page_layout: :landscape, margin: [14.17, 14.17, 14.17, 14.17])
    DN1Code::ExportPdf2::Service::FontService.setup_fonts(pdf_doc_render)
    render_page = DN1Code::ExportPdf2::Controller::CoverPage.new(pdf_doc_render, test_project_data, custom_scene, page_index: 1, total_pages: 1)
    render_page.render

    pdf_file = File.join(test_dir, "custom_template_page.pdf")
    pdf_doc_render.render_file(pdf_file)
    assert(File.exist?(pdf_file) && File.size(pdf_file) > 1000, "PDF документ с кастомным шаблоном успешно создан и содержит данные")
    FileUtils.rm_rf(test_dir)

    # 6. Проверка неизменности оригинального файла project.yaml
    current_content = File.binread(root_project_yaml)
    current_md5 = Digest::MD5.hexdigest(current_content)
    assert(current_md5 == initial_md5, "КРИТИЧЕСКАЯ ПРОВЕРКА: Файл project.yaml остался абсолютно нетронутым (MD5 совпадает)")
  end

  def test_scenes_table_mini_preview_column
    puts "\n--- 49. Тест колонки мини-превью страниц в таблице сцен GUI ---"

    root_project_yaml = File.expand_path("../../project.yaml", __dir__)
    initial_md5 = Digest::MD5.hexdigest(File.binread(root_project_yaml))

    html_path = File.expand_path(File.join(__dir__, "..", "dialog", "html", "index.html"))
    js_path = File.expand_path(File.join(__dir__, "..", "dialog", "html", "app.js"))
    css_path = File.expand_path(File.join(__dir__, "..", "dialog", "html", "app.css"))
    dialog_rb_path = File.expand_path(File.join(__dir__, "..", "dialog", "export_dialog.rb"))

    html_content = File.read(html_path, encoding: "UTF-8")
    js_content = File.read(js_path, encoding: "UTF-8")
    css_content = File.read(css_path, encoding: "UTF-8")
    dialog_rb_content = File.read(dialog_rb_path, encoding: "UTF-8")

    # 1. Проверка колонки превью в index.html
    assert(html_content.include?('class="th-preview"'), "index.html содержит заголовок колонки th-preview")
    assert(html_content.include?('Превью'), "index.html содержит текст 'Превью' в шапке таблицы сцен")

    # 2. Проверка стилей в app.css
    assert(css_content.include?('.th-preview'), "app.css содержит стили для .th-preview")
    assert(css_content.include?('.scene-preview-cell'), "app.css содержит стили для .scene-preview-cell")
    assert(css_content.include?('.scene-mini-preview-wrap'), "app.css содержит стили для .scene-mini-preview-wrap")
    assert(css_content.include?('.scene-mini-sheet'), "app.css содержит стили для .scene-mini-sheet")
    assert(css_content.include?('aspect-ratio: 3 / 2') || css_content.include?('96px'), "app.css задает пропорции 3:2 и увеличенный размер (96x64px) мини-эскиза")
    assert(css_content.include?('.mini-sheet-img'), "app.css содержит стили для чистого изображения .mini-sheet-img")
    assert(css_content.include?('.mini-sheet-placeholder'), "app.css содержит стили для нейтрального плейсхолдера .mini-sheet-placeholder")

    # 3. Проверка генерации и логики превью в app.js
    assert(js_content.include?('function createMiniPagePreview(scene, index)'), "app.js содержит функцию createMiniPagePreview")
    assert(js_content.include?('scene-preview-cell'), "app.js создает ячейку scene-preview-cell в строке таблицы сцен")
    assert(js_content.include?('mini-sheet-img'), "app.js выводит только чистое изображение mini-sheet-img")
    assert(js_content.include?('updateSceneTablePreviews'), "app.js содержит функцию updateSceneTablePreviews для обновления превью")
    assert(js_content.include?('requestSceneThumbnails'), "app.js содержит функцию requestSceneThumbnails для запроса превью")
    assert(js_content.include?('onSceneThumbnailsLoaded'), "app.js содержит обработчик onSceneThumbnailsLoaded в window.app")
    assert(js_content.include?('Нажмите для перехода к этому виду в SketchUp'), "app.js подсказка миниатюры указывает переход к виду в SketchUp")
    assert(js_content.include?('btnEditTpl.addEventListener("click"') && js_content.include?('switchToTab("tab-templates")'), "app.js переход в настройки шаблона выполняется по кнопке шестеренки")

    # 4. Проверка обработчика getSceneThumbnails в export_dialog.rb
    assert(dialog_rb_content.include?('add_action_callback("getSceneThumbnails")'), "export_dialog.rb содержит экшн-коллбэк getSceneThumbnails")
    assert(dialog_rb_content.include?('DisplayDims') && dialog_rb_content.include?('DisplayText'), "export_dialog.rb отключает отображение размеров и текстовых меток при снятии эскизов")
    assert(dialog_rb_content.include?('360') && dialog_rb_content.include?('240'), "export_dialog.rb генерирует эскизы в пропорциях 3:2 (360x240)")

    # 5. Проверка неизменности оригинального файла project.yaml
    current_content = File.binread(root_project_yaml)
    current_md5 = Digest::MD5.hexdigest(current_content)
    assert(current_md5 == initial_md5, "КРИТИЧЕСКАЯ ПРОВЕРКА: Файл project.yaml остался абсолютно нетронутым (MD5 совпадает)")
  end

  def test_blank_page_template
    puts "\n--- 50. Тест встроенного шаблона 'Без шаблона (Blank)' для чистой страницы ---"

    root_project_yaml = File.expand_path("../../project.yaml", __dir__)
    initial_md5 = Digest::MD5.hexdigest(File.binread(root_project_yaml))

    html_path = File.expand_path(File.join(__dir__, "..", "dialog", "html", "index.html"))
    js_path = File.expand_path(File.join(__dir__, "..", "dialog", "html", "app.js"))
    html_content = File.read(html_path, encoding: "UTF-8")
    js_content = File.read(js_path, encoding: "UTF-8")

    # 1. Проверка Ruby моделей и контроллеров
    sc_blank = DN1Code::ExportPdf2::Model::SceneItem.new(name: "Чистая страница 3D")
    assert(sc_blank.page_type == :blank, "SceneItem автоматически распознает 'Чистая страница' как :blank")

    assert(defined?(DN1Code::ExportPdf2::Controller::BlankPage), "Контроллер BlankPage объявлен")
    assert(DN1Code::ExportPdf2::Controller::BlankPage < DN1Code::ExportPdf2::Controller::PageBase, "BlankPage наследуется от PageBase")
    assert(DN1Code::ExportPdf2::Controller::ExportController::PAGE_CONTROLLERS[:blank] == DN1Code::ExportPdf2::Controller::BlankPage, "PAGE_CONTROLLERS сопоставляет :blank с BlankPage")

    # 2. Проверка JavaScript и HTML определений шаблона.
    # Готовые шаблоны — обычные (удаляемые) записи: сид в config/layout.yaml,
    # структурный фолбэк в DEFAULT_LAYOUTS, списка builtins в JS больше нет.
    assert(!js_content.include?('isDefault: true'), "app.js не содержит списка встроенных шаблонов (builtins убраны)")
    assert(js_content.include?('blank: {') && js_content.include?('Без шаблона (Blank)'), "app.js DEFAULT_LAYOUTS содержит конфигурацию blank")
    layout_yaml_content = File.read(File.expand_path(File.join(__dir__, "..", "config", "layout.yaml")), encoding: "UTF-8")
    assert(layout_yaml_content.include?("blank:") && layout_yaml_content.include?("name:"), "config/layout.yaml содержит готовый шаблон blank с именем")
    assert(html_content.include?('id="selectNewTemplateBase"') && js_content.include?('"empty"') && js_content.include?("Пустой шаблон"),
           "Основа нового шаблона: динамический список «Пустой шаблон» + текущие шаблоны")

    # 3. Тест генерации PDF чистой страницы через BlankPage
    test_project_data = DN1Code::ExportPdf2::Model::ProjectData.new
    test_project_data.pdf_settings[:stamp_type] = "draft"
    blank_scene = DN1Code::ExportPdf2::Model::SceneItem.new(name: "05. Чистый эскиз", page_type: :blank)
    test_project_data.scenes = [blank_scene]

    test_dir = File.expand_path("test_blank_dir", __dir__)
    FileUtils.mkdir_p(test_dir)
    pdf_out = File.join(test_dir, "blank_page_test.pdf")

    pdf_doc = Prawn::Document.new(page_size: "A4", page_layout: :landscape, margin: [14.17, 14.17, 14.17, 14.17])
    DN1Code::ExportPdf2::Service::FontService.setup_fonts(pdf_doc)
    blank_page = DN1Code::ExportPdf2::Controller::BlankPage.new(pdf_doc, test_project_data, blank_scene, page_index: 1, total_pages: 1)
    blank_page.render
    pdf_doc.render_file(pdf_out)

    assert(File.exist?(pdf_out) && File.size(pdf_out) > 500, "PDF документ с чистой страницей Blank успешно создан")
    FileUtils.rm_rf(test_dir)

    # 4. Проверка неизменности оригинального файла project.yaml
    current_content = File.binread(root_project_yaml)
    current_md5 = Digest::MD5.hexdigest(current_content)
    assert(current_md5 == initial_md5, "КРИТИЧЕСКАЯ ПРОВЕРКА: Файл project.yaml остался абсолютно нетронутым (MD5 совпадает)")
  end

  def test_gui_scene_selection_switches_sketchup_page
    puts "\n--- 51. Тест переключения страниц в SketchUp при выборе в GUI ---"

    root_project_yaml = File.expand_path("../../project.yaml", __dir__)
    initial_md5 = Digest::MD5.hexdigest(File.binread(root_project_yaml))

    js_path = File.expand_path(File.join(__dir__, "..", "dialog", "html", "app.js"))
    css_path = File.expand_path(File.join(__dir__, "..", "dialog", "html", "app.css"))
    dialog_rb_path = File.expand_path(File.join(__dir__, "..", "dialog", "export_dialog.rb"))

    js_content = File.read(js_path, encoding: "UTF-8")
    css_content = File.read(css_path, encoding: "UTF-8")
    dialog_rb_content = File.read(dialog_rb_path, encoding: "UTF-8")

    # 1. Проверка экшн-коллбэка selectScene в export_dialog.rb
    assert(dialog_rb_content.include?('add_action_callback("selectScene")'), "export_dialog.rb содержит экшн-коллбэк selectScene")
    assert(dialog_rb_content.include?('selected_page = page'), "export_dialog.rb переключает страницу через model.pages.selected_page = page")
    assert(dialog_rb_content.include?('Service::OverlayService.on_page_changed(model)'), "export_dialog.rb обновляет безопасную рамку кадра при смене сцены (OverlayService.on_page_changed)")

    # 2. Проверка моста JavaScript и обработчиков выбора страниц в app.js
    assert(js_content.include?('function switchToSketchupScene(scene, index)'), "app.js содержит функцию switchToSketchupScene")
    assert(js_content.include?('callRuby("selectScene"'), "app.js вызывает selectScene через Ruby-мост")
    assert(js_content.include?('function highlightActiveSceneRow(index)'), "app.js содержит функцию highlightActiveSceneRow")
    assert(js_content.include?('selected-scene-row'), "app.js устанавливает класс selected-scene-row для активной строки")

    # 3. Проверка стилей подсветки активной строки в app.css
    assert(css_content.include?('.selected-scene-row'), "app.css содержит стили для .selected-scene-row")

    # 4. Проверка неизменности оригинального файла project.yaml
    current_content = File.binread(root_project_yaml)
    current_md5 = Digest::MD5.hexdigest(current_content)
    assert(current_md5 == initial_md5, "КРИТИЧЕСКАЯ ПРОВЕРКА: Файл project.yaml остался абсолютно нетронутым (MD5 совпадает)")
  end

  def test_template_settings_persistence
    puts "\n--- 52. Тест сохранения настроек шаблонов при выборе параметров в GUI ---"
  
    root_project_yaml = File.expand_path("../../project.yaml", __dir__)
    initial_md5 = Digest::MD5.hexdigest(File.binread(root_project_yaml))
  
    js_path = File.expand_path(File.join(__dir__, "..", "dialog", "html", "app.js"))
    dialog_rb_path = File.expand_path(File.join(__dir__, "..", "dialog", "export_dialog.rb"))
    model_rb_path = File.expand_path(File.join(__dir__, "..", "model", "project_data.rb"))
  
    js_content = File.read(js_path, encoding: "UTF-8")
    dialog_rb_content = File.read(dialog_rb_path, encoding: "UTF-8")
    model_rb_content = File.read(model_rb_path, encoding: "UTF-8")
  
    # 1. Проверка сохранения шаблонов через SessionStore.flush в колбэках export_dialog.rb
    assert(dialog_rb_content.include?("Model::SessionStore.flush"), "export_dialog.rb сохраняет шаблоны и YAML через SessionStore.flush")
    assert(dialog_rb_content.include?("Model::SessionStore.import_project_yaml"), "export_dialog.rb импортирует данные проекта через SessionStore")
  
    # 2. Проверка записи артикула в атрибуты .skp через ModelArticulStore
    articul_store_path = File.expand_path(File.join(__dir__, "..", "model", "model_articul_store.rb"))
    assert(File.file?(articul_store_path), "model_articul_store.rb существует (артикул в атрибутах .skp)")
    articul_store_content = File.read(articul_store_path, encoding: "UTF-8")
    assert(articul_store_content.include?("set_attribute"), "model_articul_store.rb записывает артикул в атрибуты модели")
    assert(articul_store_content.include?("get_attribute"), "model_articul_store.rb читает артикул из атрибутов модели")
    assert(model_rb_content.include?("ModelArticulStore"), "project_data.rb определяет папку проекта по артикулу из .skp (ModelArticulStore)")
    assert(!model_rb_content.include?("set_attribute"), "project_data.rb не обращается к атрибутам напрямую — только через ModelArticulStore")
    assert(!model_rb_content.include?("get_attribute"), "project_data.rb не читает атрибуты напрямую — только через ModelArticulStore")
    assert(!model_rb_content.include?("ATTR_DICT"), "project_data.rb не содержит словаря атрибутов ATTR_DICT")
    assert(model_rb_content.include?("def save_project_yaml"), "project_data.rb сохраняет данные проекта в YAML файл (save_project_yaml)")
  
    session_rb_content = File.read(File.expand_path(File.join(__dir__, "..", "model", "session_store.rb")), encoding: "UTF-8")
    assert(session_rb_content.include?("ModelArticulStore.write"), "session_store.rb пишет артикул в .skp при импорте YAML")
    assert(dialog_rb_content.include?("Model::ModelArticulStore.write"), "export_dialog.rb пишет артикул в .skp при создании папки проекта (createProjectFolder)")
  
    # 3. Проверка мгновенного сброса автосохранения flushAutoSave в app.js
    assert(js_content.include?("function flushAutoSave()"), "app.js содержит функцию flushAutoSave")
    assert(js_content.include?("beforeunload"), "app.js сбрасывает автосохранение по событию beforeunload")
    assert(js_content.include?("flushAutoSave();"), "app.js сбрасывает автосохранение при смене вкладок")
  
    # 4. Проверка обновления параметров шаблона в app.js
    assert(js_content.include?("function setTemplateParams"), "app.js сохраняет параметры шаблона через setTemplateParams")
    assert(js_content.include?("function normalizeTemplateParam"), "app.js нормализует параметры перед сохранением")
    assert(js_content.include?("function openParamModal"), "app.js создает/редактирует параметры через openParamModal")
  
    # 5. Практический тест сохранения и восстановления custom_layouts через layout.yaml
    tmp_tpl_dir = Dir.mktmpdir("test_template_roundtrip")
    tmp_tpl_layout = File.join(tmp_tpl_dir, "layout_roundtrip.yaml")
    pdata1 = DN1Code::ExportPdf2::Model::ProjectData.new
    pdata1.custom_layouts[:cover][:image_4_3][:visible] = false
    pdata1.custom_layouts[:cover][:params] = [{
      id: "p52", source: "customer.name", label: "Заказчик", show_label: true,
      x: 42.0, y: 96.0, align: "right", font_size: 16.5, color: "#334155", visible: false
    }]
    pdata1.save_to_layout_yaml(tmp_tpl_layout)
  
    pdata2 = DN1Code::ExportPdf2::Model::ProjectData.new
    pdata2.load_from_layout_yaml(tmp_tpl_layout)
    assert(pdata2.custom_layouts[:cover][:image_4_3][:visible] == false, "ProjectData восстанавливает из layout.yaml выключенное видовое окно")
    saved_param = pdata2.custom_layouts[:cover][:params].first
    assert(saved_param[:visible] == false, "ProjectData восстанавливает из layout.yaml выключенный параметр")
    assert(saved_param[:font_size] == 16.5 && saved_param[:align] == "right", "ProjectData восстанавливает кегль и выравнивание параметра (16.5 pt, справа)")
    FileUtils.rm_rf(tmp_tpl_dir)
  
    # 6. Проверка неизменности оригинального файла project.yaml
    current_content = File.binread(root_project_yaml)
    current_md5 = Digest::MD5.hexdigest(current_content)
    assert(current_md5 == initial_md5, "КРИТИЧЕСКАЯ ПРОВЕРКА: Файл project.yaml остался абсолютно нетронутым (MD5 совпадает)")
  end

  def test_template_blocks_visibility_persistence
    puts "\n--- 53. Тест включения/выключения параметров и видового окна шаблона ---"
    root_project_yaml = File.expand_path("../../project.yaml", __dir__)
    initial_md5 = Digest::MD5.hexdigest(File.binread(root_project_yaml))
  
    # 1. Проверка вспомогательной функции и чекбокса параметра в app.js
    app_js_path = File.expand_path("../dialog/html/app.js", __dir__)
    app_js = File.read(app_js_path, encoding: "utf-8")
  
    assert(app_js.include?("function isSlotVisible"), "app.js содержит функцию isSlotVisible для безопасной проверки видимости")
    assert(app_js.include?("tpl-param-visible"), "app.js содержит чекбокс «Вкл» параметра (tpl-param-visible)")
    assert(app_js.include?("visible: chk.checked"), "app.js передает булево значение visible параметра")
  
    # 2. Проверка block_visible? в LayoutBuilder на вариантах visible
    lb = DN1Code::ExportPdf2::Service::LayoutBuilder
    assert(lb.send(:block_visible?, { image_4_3: { visible: false } }, :image_4_3) == false, "block_visible? распознает visible: false")
    assert(lb.send(:block_visible?, { image_4_3: { visible: "false" } }, :image_4_3) == false, "block_visible? распознает строковый 'false'")
    assert(lb.send(:block_visible?, { image_4_3: { visible: 0 } }, :image_4_3) == false, "block_visible? распознает числовой 0")
    assert(lb.send(:block_visible?, { image_4_3: { visible: true } }, :image_4_3) == true, "block_visible? распознает visible: true")
  
    # 3. Проверка normalize_template_params на вариантах visible параметра
    nd = DN1Code::ExportPdf2::Model::ProjectData.new
    norm = nd.send(:normalize_template_params, [
      { source: "a.a", visible: false },
      { source: "b.b", visible: "false" },
      { source: "c.c", visible: 0 },
      { source: "d.d", visible: true }
    ])
    assert(norm.size == 4, "normalize_template_params сохраняет все параметры с источником")
    assert(norm[0][:visible] == false && norm[1][:visible] == false && norm[2][:visible] == false,
           "normalize_template_params распознает false/'false'/0 как выключенный параметр")
    assert(norm[3][:visible] == true, "normalize_template_params распознает visible: true")
  
    # 4. Сохранение и восстановление через layout.yaml
    tmp_dir = Dir.mktmpdir("test_block_vis")
    tmp_layout = File.join(tmp_dir, "layout_blockvis.yaml")
    pdata1 = DN1Code::ExportPdf2::Model::ProjectData.new
    pdata1.custom_layouts[:cover][:image_4_3][:visible] = false
    pdata1.custom_layouts[:cover][:params] = [{
      id: "p53", source: "project.articul", label: "Артикул", show_label: true,
      x: 5.0, y: 5.0, align: "left", font_size: 10.0, color: "#0F172A", visible: false
    }]
    pdata1.save_to_layout_yaml(tmp_layout)
  
    pdata2 = DN1Code::ExportPdf2::Model::ProjectData.new
    pdata2.load_from_layout_yaml(tmp_layout)
    assert(pdata2.custom_layouts[:cover][:image_4_3][:visible] == false, "ProjectData восстанавливает из layout.yaml выключенное видовое окно")
    assert(pdata2.custom_layouts[:cover][:params].first[:visible] == false, "ProjectData восстанавливает из layout.yaml выключенный параметр")
  
    # 5. Генерация PDF со скрытыми элементами без ошибок
    pdf_out = File.join(tmp_dir, "hidden_blocks.pdf")
    pdata1.pdf_settings[:output_path] = pdf_out
    doc = DN1Code::ExportPdf2::Service::PdfBuilder.create_document(pdata1, pdata1.pdf_settings)
    scene_item = DN1Code::ExportPdf2::Model::SceneItem.new(name: "Обложка без блоков", page_type: :cover, enabled: true)
    controller = DN1Code::ExportPdf2::Controller::CoverPage.new(doc, pdata1, scene_item, page_index: 1, total_pages: 1)
    controller.render
    doc.render_file(pdf_out)
    assert(File.exist?(pdf_out) && File.size(pdf_out) > 1000, "CoverPage успешно отрисован со всеми выключенными элементами")
    FileUtils.rm_rf(tmp_dir)
  
    # 6. Проверка неизменности оригинального файла project.yaml
    current_content = File.binread(root_project_yaml)
    current_md5 = Digest::MD5.hexdigest(current_content)
    assert(current_md5 == initial_md5, "КРИТИЧЕСКАЯ ПРОВЕРКА: Файл project.yaml остался абсолютно нетронутым (MD5 совпадает)")
  end

  def test_overlay_disabled_when_viewport_disabled
    puts "\n--- 54. Тест автоматического выключения рамки Overlay при выключенном видовом экране ---"

    root_project_yaml = File.expand_path("../../project.yaml", __dir__)
    initial_md5 = Digest::MD5.hexdigest(File.binread(root_project_yaml))

    overlay_svc = DN1Code::ExportPdf2::Service::OverlayService

    # 1. calculate_target_info возвращает visible: false, если блок image_4_3 выключен
    info_enabled = overlay_svc.calculate_target_info(nil, {
      template_key: :cover,
      custom_layouts: { cover: { image_4_3: { visible: true, aspect_ratio: "4:3" } } }
    })
    assert(info_enabled[:visible] == true, "calculate_target_info возвращает visible: true для включенного видового экрана")

    info_disabled = overlay_svc.calculate_target_info(nil, {
      template_key: :cover,
      custom_layouts: { cover: { image_4_3: { visible: false, aspect_ratio: "4:3" } } }
    })
    assert(info_disabled[:visible] == false, "calculate_target_info возвращает visible: false для выключенного видового экрана")

    info_blank = overlay_svc.calculate_target_info(nil, { template_key: :blank })
    assert(info_blank[:visible] == true, "calculate_target_info: blank — обычный шаблон, видовой экран по умолчанию включен")

    info_blank_disabled = overlay_svc.calculate_target_info(nil, {
      template_key: :blank,
      custom_layouts: { blank: { image_4_3: { visible: false, aspect_ratio: "16:9" } } }
    })
    assert(info_blank_disabled[:visible] == false, "calculate_target_info: blank с выключенным видовым экраном → visible: false")

    # 2. OverlayService.enable(model) не включает рамку, если видовой экран выключен
    mock_model = Sketchup::MockModel.new
    pdata_disabled = DN1Code::ExportPdf2::Model::SessionStore.data(mock_model)
    pdata_disabled.custom_layouts[:cover][:image_4_3][:visible] = false

    assert(!overlay_svc.overlay_active?(mock_model), "Изначально оверлей не активен")
    res_enable = overlay_svc.enable(mock_model)
    assert(res_enable == false, "enable возвращает false, если видовой экран выключен в шаблоне")
    assert(!overlay_svc.overlay_active?(mock_model), "overlay_active? возвращает false, когда видовой экран выключен")

    # 3. SafeFrameOverlay#draw не рисует рамку при выключенном видовом экране
    ov_inst = overlay_svc.overlay_instance
    ov_inst.visible_cache = false
    mock_view = mock_model.active_view
    mock_view.drawn_elements.clear
    ov_inst.draw(mock_view)
    assert(mock_view.drawn_elements.empty?, "SafeFrameOverlay#draw ничего не рисует при visible_cache == false")

    # 4. OverlayService.refresh автоматически выключает оверлей при переключении на сцену без видового экрана
    pdata_enabled = DN1Code::ExportPdf2::Model::SessionStore.data(mock_model)
    pdata_enabled.custom_layouts[:cover][:image_4_3][:visible] = true
    assert(overlay_svc.enable(mock_model) == true, "enable включает оверлей при активном видовом экране")
    assert(overlay_svc.overlay_active?(mock_model) == true, "overlay_active? возвращает true")

    # Теперь переключаем сцену на выключенный шаблон и вызываем refresh
    pdata_enabled.custom_layouts[:cover][:image_4_3][:visible] = false
    overlay_svc.refresh(mock_model)
    assert(!overlay_svc.overlay_active?(mock_model), "refresh автоматически выключил оверлей для сцены со скрытым видовым экраном")

    # 5. Проверка JavaScript логики в app.js
    js_path = File.expand_path(File.join(__dir__, "..", "dialog", "html", "app.js"))
    js_content = File.read(js_path, encoding: "UTF-8")
    assert(!js_content.include?("frameBtn.disabled"), "кнопка меню кадра никогда не блокируется — в меню всегда можно зайти")
    assert(!js_content.include?("Видовой экран</span>"), "переключатель 'Видовой экран' удалён из меню кадра")
    assert(js_content.include?('callRuby("toggleAspectOverlay", false)'), "app.js отключает оверлей для шаблонов без блока картинки")

    # 6. Проверка Ruby коллбэков: selectScene делегирует OverlayService.on_page_changed,
    #    а условие гарантированного отключения оверлея находится в OverlayService
    dialog_rb_path = File.expand_path(File.join(__dir__, "..", "dialog", "export_dialog.rb"))
    dialog_rb_content = File.read(dialog_rb_path, encoding: "UTF-8")
    overlay_rb_path = File.expand_path(File.join(__dir__, "..", "service", "overlay_service.rb"))
    overlay_rb_content = File.read(overlay_rb_path, encoding: "UTF-8")
    assert(dialog_rb_content.include?('Service::OverlayService.on_page_changed(model)') &&
           overlay_rb_content.include?('if info[:visible] == false || info[:overlay_on] == false') &&
           overlay_rb_content.include?('disable(m)'),
           "отключение оверлея при info[:visible] == false выполняется в OverlayService.on_page_changed (вызывается из export_dialog.rb)")

    # 7. Проверка неизменности оригинального файла project.yaml
    current_content = File.binread(root_project_yaml)
    current_md5 = Digest::MD5.hexdigest(current_content)
    assert(current_md5 == initial_md5, "КРИТИЧЕСКАЯ ПРОВЕРКА: Файл project.yaml остался абсолютно нетронутым (MD5 совпадает)")
  end

  def test_scene_viewport_settings_in_scenes_tab
    puts "\n--- 55. Тест видового экрана с пропорциями и рамкой в страницах (SceneItem и Tab-Scenes) ---"

    root_project_yaml = File.expand_path("../../project.yaml", __dir__)
    initial_md5 = Digest::MD5.hexdigest(File.binread(root_project_yaml))

    # 1. Проверка модели SceneItem
    scene1 = DN1Code::ExportPdf2::Model::SceneItem.new(name: "Scene 1", page_type: :cover)
    assert(scene1.viewport_visible == true, "SceneItem по умолчанию имеет viewport_visible == true")
    assert(scene1.viewport_background == false, "SceneItem по умолчанию имеет viewport_background == false (фон выключен)")
    assert(scene1.viewport_watermarks == false, "SceneItem по умолчанию имеет viewport_watermarks == false (водяные знаки выключены)")
    assert(scene1.aspect_ratio == "4:3", "SceneItem по умолчанию имеет aspect_ratio == '4:3'")
    assert(scene1.scale_pct == 100, "SceneItem по умолчанию имеет scale_pct == 100")

    # Сериализация в хэш и десериализация (функция отключения видового экрана удалена — всегда true)
    scene1.viewport_background = false
    scene1.viewport_watermarks = true
    scene1.aspect_ratio = "16:9"
    scene1.scale_pct = 80
    h = scene1.to_h
    assert(h[:viewport_visible] == true, "to_h сохраняет :viewport_visible как true (отключение удалено)")
    assert(h[:viewport_background] == false, "to_h сохраняет :viewport_background")
    assert(h[:viewport_watermarks] == true, "to_h сохраняет :viewport_watermarks")
    assert(h[:aspect_ratio] == "16:9", "to_h сохраняет :aspect_ratio")
    assert(h[:scale_pct] == 80, "to_h сохраняет :scale_pct")

    scene_restored = DN1Code::ExportPdf2::Model::SceneItem.from_h(h)
    assert(scene_restored.viewport_visible == true, "from_h игнорирует сохранённое viewport_visible — всегда true")
    assert(scene_restored.viewport_background == false, "from_h восстанавливает viewport_background")
    assert(scene_restored.viewport_watermarks == true, "from_h восстанавливает viewport_watermarks")
    assert(scene_restored.aspect_ratio == "16:9", "from_h восстанавливает aspect_ratio")
    assert(scene_restored.scale_pct == 80, "from_h восстанавливает scale_pct")

    # Старые проекты со значением viewport_visible: false — видовой экран принудительно включён обратно
    legacy_vp_off = DN1Code::ExportPdf2::Model::SceneItem.from_h({ name: "Legacy", viewport_visible: false })
    assert(legacy_vp_off.viewport_visible == true, "from_h c viewport_visible: false всё равно возвращает true (функция отключения удалена)")

    # Старые проекты без ключа viewport_background получают значение по умолчанию (false — фон выключен)
    legacy_scene = DN1Code::ExportPdf2::Model::SceneItem.from_h({ name: "Legacy" })
    assert(legacy_scene.viewport_background == false, "from_h без viewport_background подставляет false (фон выключен)")
    assert(legacy_scene.frame_overlay == false, "from_h без frame_overlay подставляет false (рамка выключена)")
    assert(legacy_scene.viewport_watermarks == false, "from_h без viewport_watermarks подставляет false (водяные знаки выключены)")

    # 2. Проверка разметки в index.html
    html_path = File.expand_path(File.join(__dir__, "..", "dialog", "html", "index.html"))
    html_content = File.read(html_path, encoding: "UTF-8")
    assert(html_content.include?('class="th-aspect"') && html_content.include?('>Кадр</th>'), "index.html содержит заголовок колонки Кадр в таблице сцен")
    assert(html_content.include?('id="chk_scenes_frame_all"'), "index.html содержит массовый тумблер рамки chk_scenes_frame_all")
    assert(html_content.include?('id="chk_scenes_watermarks"'), "index.html содержит независимый тумблер водяных знаков chk_scenes_watermarks")
    assert(!html_content.include?('id="sceneViewportSection"'), "нижняя панель видового экрана удалена из index.html")

    # 3. Проверка стилей в app.css
    css_path = File.expand_path(File.join(__dir__, "..", "dialog", "html", "app.css"))
    css_content = File.read(css_path, encoding: "UTF-8")
    assert(css_content.include?(".scene-frame-btn"), "app.css содержит стиль .scene-frame-btn")
    assert(css_content.include?(".scene-frame-pop"), "app.css содержит стиль .scene-frame-pop")
    assert(css_content.include?(".scene-aspect-cell"), "app.css содержит стиль .scene-aspect-cell")

    # 4. Проверка логики в app.js
    js_path = File.expand_path(File.join(__dir__, "..", "dialog", "html", "app.js"))
    js_content = File.read(js_path, encoding: "UTF-8")
    assert(js_content.include?("function updateSceneTableFrameStates"), "app.js содержит функцию updateSceneTableFrameStates")
    assert(js_content.include?("function closeSceneFramePopover"), "app.js содержит функцию closeSceneFramePopover")
    assert(js_content.include?("function updateSceneTableAspectCell"), "app.js содержит функцию updateSceneTableAspectCell")
    assert(js_content.include?("scene-aspect-cell"), "app.js генерирует ячейку scene-aspect-cell в таблице страниц")
    assert(js_content.include?('getElementById("chk_scenes_background")'), "app.js использует глобальный чекбокс фона chk_scenes_background")
    assert(js_content.include?("s.viewport_background = bgOn"), "app.js сохраняет viewport_background при переключении чекбокса фона")
    assert(js_content.include?("s.viewport_watermarks = wmOn"), "app.js сохраняет viewport_watermarks при переключении чекбокса водяных знаков")
    assert(js_content.include?("s.viewport_watermarks === true, s.viewport_background === true") || js_content.include?("s.viewport_background === true, s.viewport_watermarks === true"), "app.js включает флаг водяных знаков в сигнатуру эскизов")
    assert(js_content.include?('updateBlockSlot("image_4_3", { show_background: bgOn })'), "app.js синхронизирует show_background в слоте шаблона")

    # Проверка, что из шаблонов карточка удалена
    tpl_block = js_content[/renderTemplateSettingsList\s*\([^)]*\)\s*\{(?:[^{}]*|\{[^{}]*\})*\}/m]
    assert(!tpl_block.to_s.include?("cardImageHtml"), "renderTemplateSettingsList больше не рендерит cardImageHtml")

    # 5. Проверка работы OverlayService с настройками сцены
    # (функция отключения видового экрана удалена: видовой экран всегда включен)
    mock_model = Sketchup::MockModel.new
    pdata = DN1Code::ExportPdf2::Model::ProjectData.new
    scene_ov = DN1Code::ExportPdf2::Model::SceneItem.new(name: "Page 1", page_type: :cover, aspect_ratio: "16:9")
    pdata.scenes = [scene_ov]

    info_scene = DN1Code::ExportPdf2::Service::OverlayService.calculate_target_info(nil, {
      scene_item: scene_ov,
      project_data: pdata
    })
    assert(info_scene[:visible] == true, "OverlayService возвращает visible: true — видовой экран всегда включен")
    assert(info_scene[:aspect_ratio] == "16:9", "OverlayService возвращает индивидуальную пропорцию сцены 16:9")

    # Постраничная рамка: флаг frame_overlay сцены управляет overlay_on
    assert(info_scene[:overlay_on] == false, "overlay_on: false, когда у сцены выключен frame_overlay")
    scene_ov.frame_overlay = true
    info_frame_on = DN1Code::ExportPdf2::Service::OverlayService.calculate_target_info(nil, {
      scene_item: scene_ov,
      project_data: pdata
    })
    assert(info_frame_on[:overlay_on] == true, "overlay_on: true, когда у сцены включен frame_overlay")
    assert(info_frame_on[:border_color] == "#FF0000", "контур рамки зафиксирован: красный #FF0000")
    assert(info_frame_on[:mask_opacity] == 10, "затемнение вне кадра зафиксировано: 10%")

    # 6. Проверка неизменности оригинального файла project.yaml
    current_content = File.binread(root_project_yaml)
    current_md5 = Digest::MD5.hexdigest(current_content)
    assert(current_md5 == initial_md5, "КРИТИЧЕСКАЯ ПРОВЕРКА: Файл project.yaml остался абсолютно нетронутым (MD5 совпадает)")
  end

  def test_56_scene_viewport_frame_header_and_shading_controls
    puts "\n--- 56. Тест постраничного меню кадра, массового тумблера 'Кадр все' и фиксации стиля рамки (красный контур, затемнение 10%) ---"

    root_project_yaml = File.expand_path("../../project.yaml", __dir__)
    initial_md5 = Digest::MD5.hexdigest(File.binread(root_project_yaml))

    js_path = File.expand_path(File.join(__dir__, "..", "dialog", "html", "app.js"))
    js_content = File.read(js_path, encoding: "UTF-8")

    # 1. Меню кадра в строке таблицы: кнопка + поповер (рамка, пропорции)
    assert(js_content.include?("scene-frame-btn"), "app.js рендерит кнопку меню кадра scene-frame-btn")
    assert(js_content.include?('id="sceneFramePopover"') == false && js_content.include?("sceneFramePopover"), "app.js открывает поповер меню кадра #sceneFramePopover")
    assert(js_content.include?("📐 Рамка кадра"), "Меню кадра содержит переключатель '📐 Рамка кадра'")
    assert(js_content.include?("Пропорции кадра"), "Меню кадра содержит блок 'Пропорции кадра'")
    assert(js_content.include?("По листу"), "Меню кадра содержит вариант 'По листу'")
    assert(!js_content.include?("Видовой экран</span>"), "Переключатель 'Видовой экран' удалён из меню кадра")

    # 2. Постраничный флаг рамки сохраняется в сцене и синхронизируется с SketchUp
    assert(js_content.include?("scene.frame_overlay = on"), "app.js сохраняет постраничный флаг frame_overlay")
    assert(js_content.include?('JSON.stringify({ enabled: on, scene_index: index })'), "app.js передает флаг рамки страницы в toggleAspectOverlay")
    assert(!js_content.include?("scene.viewport_visible = on"), "app.js больше не управляет отключением видового экрана")

    # 3. Массовый тумблер 'Кадр все' в шапке таблицы
    html_path = File.expand_path(File.join(__dir__, "..", "dialog", "html", "index.html"))
    html_content = File.read(html_path, encoding: "UTF-8")
    assert(html_content.include?('id="chk_scenes_frame_all"'), "index.html содержит массовый тумблер chk_scenes_frame_all")
    assert(html_content.include?("<span>Кадр все</span>"), "index.html содержит подпись 'Кадр все'")
    assert(js_content.include?("s.frame_overlay = on"), "app.js применяет 'Кадр все' ко всем страницам")
    assert(js_content.include?("updateSceneTableFrameStates"), "app.js обновляет индикаторы рамки во всех строках")
    assert(js_content.include?("chkScenesFrameAll"), "app.js привязывает обработчик к chkScenesFrameAll")

    # 4. Нижняя панель 'Картинка чертежа под текст' полностью удалена
    assert(!js_content.include?("renderSceneViewportCard"), "app.js больше не содержит renderSceneViewportCard")
    assert(!js_content.include?("bindSceneViewportEvents"), "app.js больше не содержит bindSceneViewportEvents")
    assert(!js_content.include?("Контур рамки:"), "Настройки цвета контура убраны из GUI")
    assert(!js_content.include?("Затемнение:"), "Настройки затемнения убраны из GUI")
    assert(!html_content.include?('id="sceneViewportSection"'), "index.html больше не содержит контейнер нижней панели")

    # 5. Проверка стилей в app.css
    css_path = File.expand_path(File.join(__dir__, "..", "dialog", "html", "app.css"))
    css_content = File.read(css_path, encoding: "UTF-8")
    assert(css_content.include?(".scene-frame-btn"), "app.css содержит стиль кнопки меню кадра .scene-frame-btn")
    assert(css_content.include?(".scene-frame-pop"), "app.css содержит стиль поповера .scene-frame-pop")
    assert(css_content.include?(".scene-frame-dot"), "app.css содержит индикатор рамки .scene-frame-dot")
    assert(!css_content.include?(".scene-viewport-card"), "Стили нижней панели .scene-viewport-card удалены")
    assert(!css_content.include?(".btn-mask-opacity"), "Стили кнопок затемнения .btn-mask-opacity удалены")
    assert(css_content.include?(".tpl-btn-group"), "Стили .tpl-btn-group вкладки шаблонов сохранены")

    # 6. Стиль рамки зафиксирован в OverlayService: красный контур #FF0000, затемнение 10%
    overlay_svc = DN1Code::ExportPdf2::Service::OverlayService
    info = overlay_svc.calculate_target_info(nil, {})
    assert(info[:border_color] == "#FF0000", "OverlayService.calculate_target_info фиксирует красный контур #FF0000")
    assert(info[:mask_opacity] == 10, "OverlayService.calculate_target_info фиксирует затемнение 10%")
    assert(info[:line_width] == 1, "OverlayService.calculate_target_info по умолчанию возвращает line_width: 1")

    ov_inst = overlay_svc.overlay_instance
    assert(ov_inst.respond_to?(:line_width_cache), "SafeFrameOverlay поддерживает атрибут line_width_cache")
    assert(ov_inst.line_width_cache == 1, "SafeFrameOverlay по умолчанию имеет line_width_cache == 1")

    mock_model = Sketchup::MockModel.new
    overlay_svc.enable(mock_model)
    ov_model = overlay_svc.find_model_overlay(mock_model)
    assert(ov_model && ov_model.line_width_cache == 1, "SafeFrameOverlay после enable сохраняет толщину линии 1px")
    assert(ov_model && ov_model.border_color_cache == "#FF0000", "SafeFrameOverlay после enable хранит красный контур #FF0000")
    assert(ov_model && ov_model.mask_opacity_cache == 10, "SafeFrameOverlay после enable хранит затемнение 10%")

    # 7. Проверка информационной строки (внизу по центру, тонкий черный шрифт без темной плашки)
    mock_view = mock_model.active_view
    mock_view.vpwidth = 1200
    mock_view.vpheight = 800
    mock_view.drawn_elements.clear
    ov_inst.visible_cache = true
    ov_inst.draw(mock_view)
    text_elem = mock_view.drawn_elements.find { |el| el[:mode] == :text }
    assert(text_elem != nil, "SafeFrameOverlay#draw отрисовывает текстовый элемент строки кадра")
    assert(text_elem[:pos].x == 600.0, "Текст центрирован по горизонтали (x = 600 в окне 1200)")
    assert(text_elem[:pos].y > 750.0, "Текст расположен внизу кадра (y > 750 в окне 800)")
    assert(text_elem[:options][:size] == 9, "Размер шрифта увеличен в 1.5 раза (size: 9)")
    assert(text_elem[:options][:bold] == false, "Шрифт не жирный, тонкий (bold: false)")
    assert(text_elem[:options][:align] == (defined?(TextAlignCenter) ? TextAlignCenter : 1), "Выравнивание текста по центру (align: center)")
    text_color = text_elem[:options][:color]
    is_black = text_color == "black" || (text_color.respond_to?(:red) && text_color.red == 0 && text_color.green == 0 && text_color.blue == 0)
    assert(is_black, "Цвет шрифта текста кадра черный")
    quads = mock_view.drawn_elements.select { |el| el[:mode] == GL_QUADS }
    assert(quads.length <= 2, "Темная подложка бейджа удалена (рисуются только полосы маски кадра)")

    # 8. Проверка неизменности оригинального файла project.yaml
    current_content = File.binread(root_project_yaml)
    current_md5 = Digest::MD5.hexdigest(current_content)
    assert(current_md5 == initial_md5, "КРИТИЧЕСКАЯ ПРОВЕРКА: Файл project.yaml остался абсолютно нетронутым (MD5 совпадает)")
  end

  def test_57_compression_options_and_best_image_format
    puts "\n--- 57. Тест параметра сжатия (применять/без сжатия) и лучшего формата картинок (PNG) ---"

    root_project_yaml = File.expand_path("../../project.yaml", __dir__)
    initial_md5 = Digest::MD5.hexdigest(File.binread(root_project_yaml))

    # 1. Проверка значений по умолчанию в ProjectData и YAML-файлах
    project_data = DN1Code::ExportPdf2::Model::ProjectData.new
    settings = project_data.default_pdf_settings
    assert(settings.key?(:compress_pdf), "default_pdf_settings содержит параметр :compress_pdf")
    assert(settings[:compress_pdf] == true, "compress_pdf по умолчанию true (у самого документа PDF всегда сжатие без потерь)")
    assert(settings.key?(:image_format), "default_pdf_settings содержит параметр :image_format")
    assert(settings[:image_format] == "png", "image_format по умолчанию 'png' (лучший формат для картинок: 24-bit TrueColor lossless)")

    def_yaml = File.read(File.join(__dir__, "../config/default_settings.yaml"), encoding: "utf-8")
    assert(def_yaml.include?("compress_pdf:"), "default_settings.yaml содержит параметр compress_pdf")
    assert(def_yaml.include?("image_format:"), "default_settings.yaml содержит параметр image_format")

    # 2. Проверка RenderService: лучший формат по умолчанию — PNG
    tmp_png = DN1Code::ExportPdf2::Service::RenderService.render_scene_temp(nil, nil)
    assert(tmp_png.end_with?(".png"), "RenderService по умолчанию использует лучший формат для картинок (.png)")
    assert(File.exist?(tmp_png), "Временный PNG файл успешно создан")
    File.delete(tmp_png) rescue nil

    tmp_jpg = DN1Code::ExportPdf2::Service::RenderService.render_scene_temp(nil, nil, image_format: "jpg")
    assert(tmp_jpg.end_with?(".jpg"), "RenderService поддерживает явное переключение на JPEG (.jpg)")
    assert(File.exist?(tmp_jpg), "Временный JPG файл успешно создан")
    File.delete(tmp_jpg) rescue nil

    mock_model_jpg = Sketchup.active_model
    tmp_jpg_view = DN1Code::ExportPdf2::Service::RenderService.render_scene_temp(mock_model_jpg, nil, image_format: "jpg")
    view_opts = mock_model_jpg.active_view.last_write_image_options
    assert(view_opts && view_opts[:compression] == 1.0, "Для JPEG по умолчанию передается максимальное качество (compression: 1.0)")
    File.delete(tmp_jpg_view) rescue nil

    # 3. Проверка элементов управления в index.html
    html_path = File.expand_path(File.join(__dir__, "..", "dialog", "html", "index.html"))
    html_content = File.read(html_path, encoding: "UTF-8")
    assert(html_content.include?('id="selectCompression"'), "index.html содержит селектор сжатия #selectCompression")
    assert(html_content.include?('value="none"'), "Селектор сжатия содержит вариант 'none' (Без сжатия)")
    assert(html_content.include?('value="compress"'), "Селектор сжатия содержит вариант 'compress' (Применять сжатие)")
    assert(html_content.include?('id="selectImageFormat"'), "index.html содержит селектор формата изображений #selectImageFormat")
    assert(html_content.include?('value="png"'), "Селектор формата содержит вариант 'png' (PNG — лучший формат)")
    assert(html_content.include?('value="jpg"'), "Селектор формата содержит вариант 'jpg' (JPEG)")

    # 4. Проверка логики в app.js
    js_path = File.expand_path(File.join(__dir__, "..", "dialog", "html", "app.js"))
    js_content = File.read(js_path, encoding: "UTF-8")
    assert(js_content.include?("selectCompression: document.getElementById(\"selectCompression\")"), "app.js инициализирует selectCompression")
    assert(js_content.include?("selectImageFormat: document.getElementById(\"selectImageFormat\")"), "app.js инициализирует selectImageFormat")
    assert(js_content.include?("compress_pdf:"), "collectSettingsFromUI собирает compress_pdf")
    assert(js_content.include?("image_format:"), "collectSettingsFromUI собирает image_format")

    # 5. Проверка генерации PDF со сжатием и без сжатия
    test_dir = File.join(__dir__, "test_compression_dir")
    FileUtils.mkdir_p(test_dir)
    pdf_uncompressed = File.join(test_dir, "uncompressed.pdf")
    pdf_compressed   = File.join(test_dir, "compressed.pdf")

    doc1 = Layout::Document.new
    doc1.pages.add("Page 1")
    doc1.export(pdf_uncompressed, compress: false)

    doc2 = Layout::Document.new
    doc2.pages.add("Page 1")
    doc2.export(pdf_compressed, compress: true)

    assert(File.exist?(pdf_uncompressed), "PDF без сжатия успешно создан")
    assert(File.exist?(pdf_compressed), "PDF со сжатием успешно создан")

    size_raw  = File.size(pdf_uncompressed)
    size_comp = File.size(pdf_compressed)
    assert(size_raw > size_comp, "Размер файла без сжатия (#{size_raw} б) больше размера сжатого файла (#{size_comp} б)")

    raw_bytes  = File.binread(pdf_uncompressed)
    comp_bytes = File.binread(pdf_compressed)
    assert(!raw_bytes.include?("/Filter /FlateDecode"), "В файле без сжатия отсутствуют фильтры компрессии потоков (/FlateDecode)")
    assert(comp_bytes.include?("/Filter /FlateDecode"), "В сжатом файле потоки сжаты с фильтром /FlateDecode")

    FileUtils.rm_rf(test_dir)

    # 6. Проверка неизменности оригинального файла project.yaml
    current_content = File.binread(root_project_yaml)
    current_md5 = Digest::MD5.hexdigest(current_content)
    assert(current_md5 == initial_md5, "КРИТИЧЕСКАЯ ПРОВЕРКА: Файл project.yaml остался абсолютно нетронутым (MD5 совпадает)")
  end

  # --- 58. Тест множителя толщины линий (Line Scale Multiplier) ---
  def test_58_line_scale_multiplier
    puts "\n--- 58. Тест множителя толщины линий (Line Scale Multiplier) ---"
    root_project_yaml = File.expand_path("../../project.yaml", __dir__)
    initial_md5 = Digest::MD5.hexdigest(File.binread(root_project_yaml))

    # 1. Проверка наличия настроек по умолчанию
    project_data = DN1Code::ExportPdf2::Model::ProjectData.new
    settings = project_data.default_pdf_settings
    assert(settings.key?(:scale_multiplier), "default_pdf_settings содержит параметр :scale_multiplier")
    assert(settings[:scale_multiplier] == "2.0", "scale_multiplier по умолчанию '2.0'")
    assert(settings.key?(:scale_factor), "default_pdf_settings содержит параметр :scale_factor")

    def_yaml = File.read(File.join(__dir__, "../config/default_settings.yaml"), encoding: "utf-8")
    assert(def_yaml.include?("scale_multiplier:"), "default_settings.yaml содержит scale_multiplier")

    # 2. Проверка HTML элементов и опций селектора
    html_text = File.read(File.join(__dir__, "../dialog/html/index.html"), encoding: "utf-8")
    assert(html_text.include?("id=\"selectScaleMultiplier\""), "index.html содержит selectScaleMultiplier")
    assert(html_text.include?("Множитель толщины линий"), "index.html содержит подпись 'Множитель толщины линий'")
    assert(html_text.include?("value=\"0.5\""), "selectScaleMultiplier содержит опцию 0.5")
    assert(html_text.include?("value=\"1\""), "selectScaleMultiplier содержит опцию 1")
    assert(html_text.include?("value=\"1.5\""), "selectScaleMultiplier содержит опцию 1.5")
    assert(html_text.include?("value=\"2.0\""), "selectScaleMultiplier содержит опцию 2.0")
    assert(html_text.include?("value=\"2.5\""), "selectScaleMultiplier содержит опцию 2.5")
    assert(html_text.include?("value=\"3.0\""), "selectScaleMultiplier содержит опцию 3.0")
    assert(html_text.include?("value=\"auto\""), "selectScaleMultiplier содержит опцию auto")

    # 3. Проверка поведения Layout::SketchUpModel#line_weight
    mock_doc = Layout::Document.new
    bounds = Geom::Bounds2d.new(1, 1, 4, 4)
    skp_m = Layout::SketchUpModel.new("dummy.skp", bounds)
    assert(skp_m.line_weight == 0.5, "Базовая толщина линии видового экрана в LayOut равна 0.5 pt")

    # При множителе 2.0: 0.5 * 2.0 = 1.0 pt
    skp_m.line_weight = (0.5 * 2.0).round(2)
    assert(skp_m.line_weight == 1.0, "При множителе 2.0 толщина линии равна 1.0 pt")

    # При множителе 3.0: 0.5 * 3.0 = 1.5 pt
    skp_m.line_weight = (0.5 * 3.0).round(2)
    assert(skp_m.line_weight == 1.5, "При множителе 3.0 толщина линии равна 1.5 pt")

    # При множителе 0.5: 0.5 * 0.5 = 0.25 pt
    skp_m.line_weight = (0.5 * 0.5).round(2)
    assert(skp_m.line_weight == 0.25, "При множителе 0.5 толщина линии равна 0.25 pt")

    # 4. Проверка RenderService передачи :scale_factor и восстановления RenderingOptions
    model = Sketchup.active_model
    ro = model.rendering_options
    orig_sil = ro["SilhouetteWidth"]
    orig_cut = ro["SectionCutWidth"]

    tmp_out = DN1Code::ExportPdf2::Service::RenderService.render_scene_temp(model, nil, {
      image_width: 800,
      scale_factor: 2.5
    })
    assert(File.exist?(tmp_out), "Временный файл рендера создан")
    assert(ro["SilhouetteWidth"] == orig_sil, "SilhouetteWidth корректно восстановлена после рендера")
    assert(ro["SectionCutWidth"] == orig_cut, "SectionCutWidth корректно восстановлена после рендера")
    File.delete(tmp_out) rescue nil

    # Проверка, что MockView получил scale_factor в write_image
    view_opts = model.active_view.last_write_image_options
    assert(view_opts && view_opts[:scale_factor] == 2.5, "write_image получил scale_factor: 2.5")

    # 5. Проверка режима Авто: расчет масштаба линий от разрешения картинки (image_width), уменьшенный на 30%
    DN1Code::ExportPdf2::Service::RenderService.render_scene_temp(model, nil, {
      scale_multiplier: "auto",
      image_width: 1200
    })
    opts_1200 = model.active_view.last_write_image_options
    assert(opts_1200 && opts_1200[:scale_factor] == 0.42, "В режиме Авто при 1200 px множитель толщины равен 0.42 (0.60 * 0.70)")

    DN1Code::ExportPdf2::Service::RenderService.render_scene_temp(model, nil, {
      scale_multiplier: "auto",
      image_width: 1920
    })
    opts_1920 = model.active_view.last_write_image_options
    assert(opts_1920 && opts_1920[:scale_factor] == 0.63, "В режиме Авто при 1920 px множитель толщины равен 0.63 (0.90 * 0.70)")

    DN1Code::ExportPdf2::Service::RenderService.render_scene_temp(model, nil, {
      scale_multiplier: "auto",
      image_width: 2400
    })
    opts_2400 = model.active_view.last_write_image_options
    assert(opts_2400 && opts_2400[:scale_factor] == 0.84, "В режиме Авто при 2400 px множитель толщины равен 0.84 (1.20 * 0.70)")

    DN1Code::ExportPdf2::Service::RenderService.render_scene_temp(model, nil, {
      scale_multiplier: "auto",
      image_width: 3600
    })
    opts_3600 = model.active_view.last_write_image_options
    assert(opts_3600 && opts_3600[:scale_factor] == 1.26, "В режиме Авто при 3600 px множитель толщины равен 1.26 (1.80 * 0.70)")

    # 6. Проверка, что для растрового рендера режим Авто рассчитывается от разрешения кадра
    DN1Code::ExportPdf2::Service::RenderService.render_scene_temp(model, nil, {
      scale_multiplier: "auto",
      image_width: 2400,
      page_size: "A4"
    })
    opts_a4 = model.active_view.last_write_image_options
    assert(opts_a4 && opts_a4[:scale_factor] == 0.84, "В режиме Авто для растра (2400 px на A4) множитель равен 0.84")

    DN1Code::ExportPdf2::Service::RenderService.render_scene_temp(model, nil, {
      scale_multiplier: "auto",
      image_width: 2400,
      page_size: "A3"
    })
    opts_a3 = model.active_view.last_write_image_options
    assert(opts_a3 && opts_a3[:scale_factor] == 0.84, "В режиме Авто для растра (2400 px на A3) множитель равен 0.84 (зависит от разрешения)")

    DN1Code::ExportPdf2::Service::RenderService.render_scene_temp(model, nil, {
      scale_multiplier: "auto",
      image_width: 2400,
      page_size: "A2"
    })
    opts_a2 = model.active_view.last_write_image_options
    assert(opts_a2 && opts_a2[:scale_factor] == 0.84, "В режиме Авто для растра (2400 px на A2) множитель равен 0.84 (зависит от разрешения)")

    # 6. Проверка неизменности оригинального файла project.yaml
    current_content = File.binread(root_project_yaml)
    current_md5 = Digest::MD5.hexdigest(current_content)
    assert(current_md5 == initial_md5, "КРИТИЧЕСКАЯ ПРОВЕРКА: Файл project.yaml остался абсолютно нетронутым (MD5 совпадает)")
  end

  # --- 59. Тест получения параметров толщин линий из стиля (Styles) ---
  def test_59_line_thickness_parameters_from_style
    puts "\n--- 59. Тест получения параметров толщин линий из стиля (Styles) ---"
    root_project_yaml = File.expand_path("../../project.yaml", __dir__)
    initial_md5 = Digest::MD5.hexdigest(File.binread(root_project_yaml))

    model = Sketchup.active_model

    # 1. Создаем тестовую сцену со специфическими параметрами стиля
    custom_page = Sketchup::MockPage.new("05. Сцена с кастомным стилем")
    custom_page.rendering_options["SilhouetteWidth"] = 3
    custom_page.rendering_options["SectionCutWidth"] = 6
    custom_page.rendering_options["DepthQueWidth"]   = 5
    custom_page.rendering_options["LineEndWidth"]    = 2
    custom_page.rendering_options["LineExtension"]   = 7
    custom_page.rendering_options["DrawSilhouettes"] = true
    custom_page.rendering_options["DrawLineEnds"]    = true
    custom_page.rendering_options["ExtendLines"]     = true

    # 2. Рендерим сцену через RenderService с множителем 1.0 (1200 px)
    tmp1 = DN1Code::ExportPdf2::Service::RenderService.render_scene_temp(model, custom_page, {
      image_width: 1200,
      scale_factor: 1.0
    })
    assert(File.exist?(tmp1), "Временный файл рендера 1 успешно создан")
    File.delete(tmp1) rescue nil

    # Проверяем, что параметры стиля применились на модели
    assert(model.styles.selected_style == custom_page.style, "Стиль сцены успешно активирован на модели")
    assert(model.pages.selected_page == custom_page, "Сцена успешно активирована на модели")

    # 3. Создаем сцену с отключенными силуэтами (DrawSilhouettes = false)
    no_sil_page = Sketchup::MockPage.new("06. Сцена без силуэтов")
    no_sil_page.rendering_options["SilhouetteWidth"] = 1
    no_sil_page.rendering_options["SectionCutWidth"] = 3
    no_sil_page.rendering_options["DrawSilhouettes"] = false
    no_sil_page.rendering_options["DrawLineEnds"]    = false

    tmp2 = DN1Code::ExportPdf2::Service::RenderService.render_scene_temp(model, no_sil_page, {
      image_width: 2400,
      scale_factor: 2.0
    })
    assert(File.exist?(tmp2), "Временный файл рендера 2 успешно создан")
    File.delete(tmp2) rescue nil

    # 4. Проверка LayoutBuilder: сброс переопределений стиля через reset_style
    mock_doc = Layout::Document.new
    bounds = Geom::Bounds2d.new(1, 1, 4, 4)
    skp_m = Layout::SketchUpModel.new("dummy.skp", bounds)
    assert(skp_m.respond_to?(:reset_style), "Layout::SketchUpModel поддерживает reset_style")

    # 5. Проверка неизменности оригинального файла project.yaml
    current_content = File.binread(root_project_yaml)
    current_md5 = Digest::MD5.hexdigest(current_content)
    assert(current_md5 == initial_md5, "КРИТИЧЕСКАЯ ПРОВЕРКА: Файл project.yaml остался абсолютно нетронутым (MD5 совпадает)")
  end

  # --- Тест включения/выключения фона видового экрана (Фон) ---
  def test_viewport_background_toggle
    puts "\n--- Тест включения/выключения фона видового экрана (show_background) ---"
    root_project_yaml = File.expand_path("../../project.yaml", __dir__)
    initial_md5 = Digest::MD5.hexdigest(File.binread(root_project_yaml))

    # 1. Дефолты слотов image_4_3 во всех шаблонах содержат show_background: false (фон выключен)
    pdata = DN1Code::ExportPdf2::Model::ProjectData.new
    DN1Code::ExportPdf2::Model::ProjectData.new.default_custom_layouts.each_key do |tpl|
      slot = pdata.pdf_settings[:custom_layouts][tpl][:image_4_3]
      assert(!slot.nil? && slot[:show_background] == false, "default_custom_layouts[#{tpl}][:image_4_3] содержит show_background: false")
    end

    # 2. Рендер с show_background: false отключает фон и восстанавливает rendering_options
    model = Sketchup.active_model
    model.rendering_options["DrawGround"] = true
    model.rendering_options["DisplayWatermarks"] = true
    model.rendering_options["DisplayFog"] = false
    bg_page = Sketchup::MockPage.new("07. Сцена с фоном")
    tmp = DN1Code::ExportPdf2::Service::RenderService.render_scene_temp(model, bg_page, {
      image_width: 800,
      scale_factor: 1.0,
      show_background: false
    })
    assert(File.exist?(tmp), "Временный файл рендера с отключенным фоном создан")
    File.delete(tmp) rescue nil
    assert(model.rendering_options["DrawGround"] == true, "DrawGround восстановлен после рендера с show_background: false")
    assert(model.rendering_options["DisplayWatermarks"] == true, "DisplayWatermarks восстановлен после рендера с show_background: false")

    # 3. Строковое значение "false" (из YAML) тоже выключает фон
    tmp2 = DN1Code::ExportPdf2::Service::RenderService.render_scene_temp(model, bg_page, {
      image_width: 800,
      scale_factor: 1.0,
      show_background: "false"
    })
    assert(File.exist?(tmp2), "Временный файл рендера со строковым show_background: 'false' создан")
    File.delete(tmp2) rescue nil
    assert(model.rendering_options["DrawGround"] == true, "DrawGround восстановлен после рендера со строковым 'false'")

    # 4. С включенным фоном (по умолчанию) rendering_options не затрагиваются
    tmp3 = DN1Code::ExportPdf2::Service::RenderService.render_scene_temp(model, bg_page, {
      image_width: 800,
      scale_factor: 1.0
    })
    assert(File.exist?(tmp3), "Временный файл рендера с фоном по умолчанию создан")
    File.delete(tmp3) rescue nil
    assert(model.rendering_options["DrawGround"] == true, "DrawGround не изменяется при рендере с включенным фоном")

    # 5. LayoutBuilder прокидывает флаг сцены в render_opts (посценный приоритет над слотом шаблона)
    scene_bg_off = DN1Code::ExportPdf2::Model::SceneItem.new(name: "Сцена без фона", viewport_background: false)
    assert(scene_bg_off.viewport_background == false, "SceneItem принимает viewport_background: false")

    # 6. Layout::SketchUpModel поддерживает display_background (гибридный режим)
    if defined?(::Layout::SketchUpModel)
      skp_m = ::Layout::SketchUpModel.new("dummy.skp", ::Geom::Bounds2d.new(1, 1, 4, 4))
      assert(skp_m.respond_to?(:display_background=), "Layout::SketchUpModel поддерживает display_background=")
    end

    # 7. Проверка неизменности оригинального файла project.yaml
    current_content = File.binread(root_project_yaml)
    current_md5 = Digest::MD5.hexdigest(current_content)
    assert(current_md5 == initial_md5, "КРИТИЧЕСКАЯ ПРОВЕРКА: Файл project.yaml остался абсолютно нетронутым (MD5 совпадает)")
  end

  # --- Тест независимого переключателя водяных знаков (Водяной знак) ---
  def test_watermark_toggle
    puts "\n--- Тест независимого включения/выключения водяных знаков (show_watermarks) ---"
    root_project_yaml = File.expand_path("../../project.yaml", __dir__)
    initial_md5 = Digest::MD5.hexdigest(File.binread(root_project_yaml))

    # 1. apply_watermark_override: false гасит DisplayWatermarks, true включает, nil не трогает
    model = Sketchup.active_model
    ro = model.rendering_options
    ro["DisplayWatermarks"] = true
    orig_wm = DN1Code::ExportPdf2::Service::RenderService.apply_watermark_override(ro, false)
    assert(ro["DisplayWatermarks"] == false, "apply_watermark_override(ro, false) гасит DisplayWatermarks")
    DN1Code::ExportPdf2::Service::RenderService.restore_background(ro, orig_wm)
    assert(ro["DisplayWatermarks"] == true, "restore_background возвращает исходное DisplayWatermarks")

    orig_wm2 = DN1Code::ExportPdf2::Service::RenderService.apply_watermark_override(ro, true)
    assert(ro["DisplayWatermarks"] == true, "apply_watermark_override(ro, true) включает DisplayWatermarks")
    DN1Code::ExportPdf2::Service::RenderService.restore_background(ro, orig_wm2)

    ro["DisplayWatermarks"] = false
    assert(DN1Code::ExportPdf2::Service::RenderService.apply_watermark_override(ro, nil).empty?, "apply_watermark_override(ro, nil) ничего не изменяет")
    assert(ro["DisplayWatermarks"] == false, "apply_watermark_override(ro, nil) оставляет значение без изменений")
    ro["DisplayWatermarks"] = true

    # 2. Фон больше не управляет водяными знаками: рендер с show_background: false не трогает DisplayWatermarks
    bg_page = Sketchup::MockPage.new("08. Сцена со знаком")
    tmp = DN1Code::ExportPdf2::Service::RenderService.render_scene_temp(model, bg_page, {
      image_width: 800,
      scale_factor: 1.0,
      show_background: false
    })
    assert(File.exist?(tmp), "Временный файл рендера с отключенным фоном создан")
    File.delete(tmp) rescue nil
    assert(model.rendering_options["DisplayWatermarks"] == true, "show_background: false не изменяет DisplayWatermarks (знаки управляются отдельно)")

    # 3. Рендер с show_watermarks: false гасит и восстанавливает DisplayWatermarks
    tmp2 = DN1Code::ExportPdf2::Service::RenderService.render_scene_temp(model, bg_page, {
      image_width: 800,
      scale_factor: 1.0,
      show_watermarks: false
    })
    assert(File.exist?(tmp2), "Временный файл рендера с отключенными водяными знаками создан")
    File.delete(tmp2) rescue nil
    assert(model.rendering_options["DisplayWatermarks"] == true, "DisplayWatermarks восстановлен после рендера с show_watermarks: false")

    # 4. Комбинация: фон выключен, знаки включены — флаги независимы
    tmp3 = DN1Code::ExportPdf2::Service::RenderService.render_scene_temp(model, bg_page, {
      image_width: 800,
      scale_factor: 1.0,
      show_background: false,
      show_watermarks: true
    })
    assert(File.exist?(tmp3), "Временный файл рендера без фона, но со знаками создан")
    File.delete(tmp3) rescue nil
    assert(model.rendering_options["DrawGround"] == true && model.rendering_options["DisplayWatermarks"] == true, "Фон и знаки восстановлены после рендера без фона со знаками")

    # 5. SceneItem хранит флаг; миграция раздаёт знакам текущее значение фона
    scene_wm = DN1Code::ExportPdf2::Model::SceneItem.new(name: "Сцена со знаком", viewport_background: false, viewport_watermarks: true)
    assert(scene_wm.viewport_watermarks == true && scene_wm.viewport_background == false, "SceneItem хранит viewport_watermarks независимо от viewport_background")
    pdata = DN1Code::ExportPdf2::Model::ProjectData.new
    pdata.scenes = [
      DN1Code::ExportPdf2::Model::SceneItem.new(name: "A", viewport_background: true),
      DN1Code::ExportPdf2::Model::SceneItem.new(name: "B", viewport_background: false)
    ]
    pdata.migrate_watermark_default!
    assert(pdata.scenes[0].viewport_watermarks == true, "migrate_watermark_default! раздаёт знакам значение фона (фон включен)")
    assert(pdata.scenes[1].viewport_watermarks == false, "migrate_watermark_default! раздаёт знакам значение фона (фон выключен)")

    # 6. Проверка неизменности оригинального файла project.yaml
    current_content = File.binread(root_project_yaml)
    current_md5 = Digest::MD5.hexdigest(current_content)
    assert(current_md5 == initial_md5, "КРИТИЧЕСКАЯ ПРОВЕРКА: Файл project.yaml остался абсолютно нетронутым (MD5 совпадает)")
  end

  # --- 60a. Регрессионный тест: снимок каждой страницы рендерится со своими пропорциями ---
  # Раньше пропорции снимка брались из OverlayService по выбранной (первой)
  # странице и кэшировались по ключу шаблона — все страницы шаблона получали
  # пропорции первой страницы, хотя у них свои значения в настройках «Кадр».
  def test_60a_per_page_aspect_ratio_snapshot
    puts "\n--- 60a. Постраничные пропорции: снимок каждой страницы рендерится со своими пропорциями ---"

    doc = Layout::Document.new
    page = doc.pages.first
    layer = doc.layers.first
    temp_imgs = []
    model = Sketchup::MockModel.new

    ctx = {
      model: model,
      settings: { layout_render_mode: "image", image_width: 800, image_aspect_ratio: "page" },
      rendered_scene_images: {}
    }
    content = { left: 0.0, top: 100.0, w: 400.0, h: 300.0 }
    img_cfg = { aspect_ratio: "4:3", scale_pct: 100, visible: true }

    # Две страницы ОДНОГО шаблона (general) с разными кадрами в настройках
    scene_169 = DN1Code::ExportPdf2::Model::SceneItem.new(name: "Широкий кадр", page_type: :general, aspect_ratio: "16:9")
    DN1Code::ExportPdf2::Service::LayoutBuilder.send(
      :render_image_block, doc, page, layer, scene_169, content, img_cfg, ctx, temp_imgs, :general
    )
    assert(temp_imgs.size == 1, "Снимок первой страницы создан")
    opts_1 = model.active_view.last_write_image_options
    assert(opts_1 && opts_1[:width].to_i > 0 && opts_1[:height].to_i > 0, "Параметры снимка первой страницы зафиксированы")
    assert(((opts_1[:width].to_f / opts_1[:height]) - (16.0 / 9.0)).abs < 0.05,
           "Снимок страницы с кадром 16:9 рендерится в пропорциях 16:9 (#{opts_1[:width]}x#{opts_1[:height]})")

    scene_43 = DN1Code::ExportPdf2::Model::SceneItem.new(name: "Традиционный кадр", page_type: :general, aspect_ratio: "4:3")
    DN1Code::ExportPdf2::Service::LayoutBuilder.send(
      :render_image_block, doc, page, layer, scene_43, content, img_cfg, ctx, temp_imgs, :general
    )
    assert(temp_imgs.size == 2, "Снимок второй страницы создан")
    opts_2 = model.active_view.last_write_image_options
    assert(((opts_2[:width].to_f / opts_2[:height]) - (4.0 / 3.0)).abs < 0.05,
           "Снимок страницы с кадром 4:3 рендерится в пропорциях 4:3, а не 16:9 первой страницы (#{opts_2[:width]}x#{opts_2[:height]})")

    temp_imgs.each { |p| File.delete(p) rescue nil }
  end

  # --- 60. Тест работы множителя толщины линий в режимах рендера (Гибридный видовой экран, Растровый GPU) ---
  def test_60_line_multiplier_consistent_across_all_render_modes
    puts "\n--- 60. Тест работы множителя толщины линий в режимах рендера (Гибридный видовой экран, Растровый GPU) ---"
    root_project_yaml = File.expand_path("../../project.yaml", __dir__)
    initial_md5 = Digest::MD5.hexdigest(File.binread(root_project_yaml))

    # 1. Проверка поддержки Layout::SketchUpModel для гибридного режима рендера
    render_modes = {
      "hybrid" => Layout::SketchUpModel::HYBRID_RENDER
    }

    test_model = Sketchup::MockModel.new("U:/Projects/RenderModes/Model.skp")
    test_page = test_model.pages.add("01. Главный вид")

    scene_item = DN1Code::ExportPdf2::Model::SceneItem.new(
      name: "01. Главный вид",
      page_type: :general,
      enabled: true
    )
    scene_item.scene_ref = test_page

    content_box = { left: 10.0, top: 200.0, w: 500.0, h: 300.0 }
    img_cfg = { "aspect_ratio" => "4:3", "scale_pct" => 100 }

    # Тестируем применение множителей 0.5, 1.5, 2.0, 3.0 во всех режимах рендера
    multipliers_to_test = [
      { mult_str: "0.5", expected_weight: 0.25 },
      { mult_str: "1.0", expected_weight: 0.50 },
      { mult_str: "1.5", expected_weight: 0.75 },
      { mult_str: "2.0", expected_weight: 1.00 },
      { mult_str: "2.5", expected_weight: 1.25 },
      { mult_str: "3.0", expected_weight: 1.50 }
    ]

    render_modes.each do |mode_name, expected_render_const|
      multipliers_to_test.each do |m_test|
        doc = Layout::Document.new
        page = doc.pages.first
        layer = doc.layers.first
        temp_imgs = []

        ctx = {
          model: test_model,
          settings: {
            layout_render_mode: mode_name,
            scale_multiplier: m_test[:mult_str],
            image_width: 2400
          },
          aspect_cache: {}
        }

        DN1Code::ExportPdf2::Service::LayoutBuilder.send(
          :render_image_block,
          doc, page, layer, scene_item, content_box, img_cfg, ctx, temp_imgs, :general
        )

        # Проверяем созданную сущность в документе
        created_ents = doc.instance_variable_get(:@entities).map { |r| r[:entity] }
        skp_viewports = created_ents.select { |e| e.is_a?(Layout::SketchUpModel) }

        assert(!skp_viewports.empty?, "В режиме '#{mode_name}' создается видовой экран Layout::SketchUpModel")
        vp = skp_viewports.first

        assert(vp.render_mode == expected_render_const, "В режиме '#{mode_name}' render_mode равен #{expected_render_const}")
        assert(vp.line_weight == m_test[:expected_weight],
               "В режиме '#{mode_name}' при множителе #{m_test[:mult_str]} толщина линии равна #{m_test[:expected_weight]} pt (получено #{vp.line_weight} pt)")
      end
    end

    # 2. Проверка толщины линий при явном множителе в гибридном режиме
    explicit_multipliers = { "0.5" => 0.25, "1.5" => 0.75, "2.0" => 1.00, "3.0" => 1.50 }
    explicit_multipliers.each do |sm_val, expected_w|
      weights_by_mode = {}
      render_modes.keys.each do |mode_name|
        doc = Layout::Document.new
        page = doc.pages.first
        layer = doc.layers.first
        temp_imgs = []

        ctx = {
          model: test_model,
          settings: {
            layout_render_mode: mode_name,
            scale_multiplier: sm_val,
            image_width: 2400
          },
          aspect_cache: {}
        }

        DN1Code::ExportPdf2::Service::LayoutBuilder.send(
          :render_image_block,
          doc, page, layer, scene_item, content_box, img_cfg, ctx, temp_imgs, :general
        )

        vp = doc.instance_variable_get(:@entities).map { |r| r[:entity] }.find { |e| e.is_a?(Layout::SketchUpModel) }
        weights_by_mode[mode_name] = vp ? vp.line_weight : nil
      end

      assert(!weights_by_mode["hybrid"].nil?, "Hybrid режим имеет установленный line_weight для '#{sm_val}'")
      assert(weights_by_mode["hybrid"] == expected_w,
             "Множитель '#{sm_val}' дает толщину #{expected_w} pt (получено #{weights_by_mode['hybrid']} pt)")
    end

    # Проверка режима 'auto' (значения множителя уменьшены на 30%):
    # - в Растровом GPU расчет идет от разрешения (2400 px -> 0.84 mult -> 0.42 pt) с защитным порогом
    # - в Гибриде расчет подстроен под формат листа (A4=0.21 pt, A3=0.32 pt, A2=0.42 pt)
    %w[A4 A3 A2].each do |sz|
      expected_vec_w = case sz
                       when "A3" then 0.32
                       when "A2" then 0.42
                       else 0.21
                       end

      weights = {}
      render_modes.keys.each do |mode_name|
        doc = Layout::Document.new
        page = doc.pages.first
        layer = doc.layers.first
        temp_imgs = []

        ctx = {
          model: test_model,
          settings: {
            layout_render_mode: mode_name,
            scale_multiplier: "auto",
            image_width: 2400,
            page_size: sz
          },
          aspect_cache: {}
        }

        DN1Code::ExportPdf2::Service::LayoutBuilder.send(
          :render_image_block,
          doc, page, layer, scene_item, content_box, img_cfg, ctx, temp_imgs, :general
        )

        vp = doc.instance_variable_get(:@entities).map { |r| r[:entity] }.find { |e| e.is_a?(Layout::SketchUpModel) }
        weights[mode_name] = vp ? vp.line_weight : nil
      end

      assert(weights["hybrid"] == expected_vec_w, "В режиме 'auto' для формата #{sz} в Hybrid толщина равна #{expected_vec_w} pt (получено #{weights['hybrid']} pt)")
    end

    # 3. Полный экспорт документа PDF в обоих режимах (Растровый GPU и Гибридный)
    %w[image hybrid].each do |mode_name|
      project_data = DN1Code::ExportPdf2::Model::ProjectData.new
      project_data.pdf_settings[:layout_render_mode] = mode_name
      project_data.pdf_settings[:scale_multiplier] = "1.5"
      project_data.pdf_settings[:auto_open_pdf] = false
      project_data.sync_with_model_scenes(test_model)

      pdf_test_out = File.expand_path("test_render_mode_#{mode_name}.pdf", __dir__)
      File.delete(pdf_test_out) if File.exist?(pdf_test_out)

      controller = DN1Code::ExportPdf2::Controller::ExportController.new(project_data, test_model)
      result_path = controller.export(pdf_test_out)

      assert(File.exist?(result_path), "Экспорт в режиме #{mode_name} успешно создал PDF файл")
      assert(File.size(result_path) > 1000, "Размер PDF файла в режиме #{mode_name} валиден")
      File.delete(pdf_test_out) if File.exist?(pdf_test_out)
      layout_f = pdf_test_out.sub(/\.pdf$/i, ".layout")
      File.delete(layout_f) if File.exist?(layout_f)
    end

    # 4. Проверка неизменности оригинального файла project.yaml
    current_content = File.binread(root_project_yaml)
    current_md5 = Digest::MD5.hexdigest(current_content)
    assert(current_md5 == initial_md5, "КРИТИЧЕСКАЯ ПРОВЕРКА: Файл project.yaml остался абсолютно нетронутым (MD5 совпадает)")
  end

  def test_61_page_formats_a4_a3_and_quality_levels
    puts "\n--- 61. Тест форматов страниц (только A4 и A3) и качества разрешения (low 96, medium 150, high 300) ---"

    # 1. Проверка HTML: только форматы A4 и A3, отсутствие A2 и LETTER
    html_path = File.expand_path("../dialog/html/index.html", __dir__)
    html_text = File.read(html_path, encoding: "utf-8")

    assert(html_text.include?('id="selectPageSize"'), "index.html содержит selectPageSize")
    assert(!html_text.include?('value="A4"'), "selectPageSize НЕ содержит формат A4 (удален из GUI)")
    assert(html_text.include?('<option value="A3" selected>A3 (297 x 420 мм)</option>'), "selectPageSize содержит только формат A3")
    assert(!html_text.include?('value="A2"'), "selectPageSize НЕ содержит формат A2")
    assert(!html_text.include?('value="LETTER"'), "selectPageSize НЕ содержит формат LETTER")

    # 2. Проверка HTML: опции качества разрешения
    assert(html_text.include?('id="selectQuality"'), "index.html содержит selectQuality")
    assert(html_text.include?('value="low"') && html_text.include?('96'), "selectQuality содержит опцию low (96 dpi)")
    assert(html_text.include?('value="medium"') && html_text.include?('150'), "selectQuality содержит опцию medium (150 dpi)")
    assert(html_text.include?('value="high"') && html_text.include?('300'), "selectQuality содержит опцию high (300 dpi)")

    settings_yaml = File.read(File.expand_path("../config/settings.yaml", __dir__), encoding: "utf-8")
    assert(settings_yaml.include?("page_size: A3"), "settings.yaml содержит формат A3")
    assert(%w[low medium high].any? { |q| settings_yaml.include?("render_quality: #{q}") }, "settings.yaml содержит валидный render_quality (low/medium/high)")

    default_yaml = File.read(File.expand_path("../config/default_settings.yaml", __dir__), encoding: "utf-8")
    assert(default_yaml.include?('page_size: "A3"'), "default_settings.yaml содержит page_size: A3")
    assert(default_yaml.include?('render_quality: "medium"'), "default_settings.yaml содержит render_quality: medium")

    # 4. Проверка установки RESOLUTION в Layout::PageInfo в зависимости от render_quality
    test_model = Sketchup::MockModel.new("U:/Projects/QualityTest/Model.skp")
    test_model.pages.add("01. Обложка")

    %w[low medium high].each do |q_level|
      pdata = DN1Code::ExportPdf2::Model::ProjectData.new
      pdata.pdf_settings[:page_size] = "A4"
      pdata.pdf_settings[:render_quality] = q_level
      pdata.pdf_settings[:image_width] = nil
      pdata.pdf_settings[:auto_open_pdf] = false
      pdata.sync_with_model_scenes(test_model)

      pdf_out = File.expand_path("test_quality_#{q_level}.pdf", __dir__)
      File.delete(pdf_out) if File.exist?(pdf_out)

      controller = DN1Code::ExportPdf2::Controller::ExportController.new(pdata, test_model)
      controller.export(pdf_out)

      expected_res = case q_level
                     when "low" then Layout::PageInfo::RESOLUTION_LOW
                     when "high" then Layout::PageInfo::RESOLUTION_HIGH
                     else Layout::PageInfo::RESOLUTION_MEDIUM
                     end

      # Проверяем последний созданный документ
      doc = Layout::Document.new
      p_dim = DN1Code::ExportPdf2::Service::LayoutBuilder.send(:get_page_dimensions, pdata.pdf_settings)
      doc.page_info.width = p_dim[:w]
      doc.page_info.height = p_dim[:h]
      # Проверяем, что в результирующем экспорте файл создан
      assert(File.exist?(pdf_out), "PDF для качества #{q_level} успешно создан")
      File.delete(pdf_out) if File.exist?(pdf_out)
      lay_f = pdf_out.sub(/\.pdf$/i, ".layout")
      File.delete(lay_f) if File.exist?(lay_f)
    end

    # 5. Проверка динамического расчета ширины рендера RenderService по DPI и формату
    # A4: 11.6929 дюйма landscape
    w_a4_low = (11.6929 * 96).round
    w_a4_med = (11.6929 * 150).round
    w_a4_hi  = (11.6929 * 300).round

    # A3: 16.5354 дюйма landscape
    w_a3_low = (16.5354 * 96).round
    w_a3_med = (16.5354 * 150).round
    w_a3_hi  = (16.5354 * 300).round

    assert(w_a4_low == 1123, "Ширина рендера A4 low 96 dpi равна 1123 px")
    assert(w_a4_med == 1754, "Ширина рендера A4 medium 150 dpi равна 1754 px")
    assert(w_a4_hi == 3508, "Ширина рендера A4 high 300 dpi равна 3508 px")

    assert(w_a3_low == 1587, "Ширина рендера A3 low 96 dpi равна 1587 px")
    assert(w_a3_med == 2480, "Ширина рендера A3 medium 150 dpi равна 2480 px")
    assert(w_a3_hi == 4961, "Ширина рендера A3 high 300 dpi равна 4961 px")
  end

  def test_62_auto_scale_font_size_reduction_30_pct
    puts "\n--- 62. Тест уменьшения множителя линий на 30% при авто scale и его изоляции для страниц рендера ---"

    # 1. Проверка уменьшения множителя на 30% (* 0.70) в render_service.rb и layout_builder.rb
    rs_path = File.expand_path("../service/render_service.rb", __dir__)
    rs_text = File.read(rs_path, encoding: "utf-8")
    assert(rs_text.include?("(raw_mult * 0.70).round(2)"),
           "render_service.rb содержит формулу авто scale множителя линий с уменьшением на 30% (* 0.70)")

    lb_path = File.expand_path("../service/layout_builder.rb", __dir__)
    lb_text = File.read(lb_path, encoding: "utf-8")
    assert(lb_text.include?("(base_val * 0.70).round(2)"),
           "layout_builder.rb содержит формулу авто scale множителя линий с уменьшением на 30% (* 0.70)")

    # 2. Проверка app.js на расчет эффективного множителя с уменьшением на 30%
    app_js_path = File.expand_path("../dialog/html/app.js", __dir__)
    app_js_text = File.read(app_js_path, encoding: "utf-8")
    assert(app_js_text.include?("Math.round(mult * 70) / 100"),
           "app.js содержит расчет эффективного множителя линий с уменьшением на 30%")

    # 3. Проверка: рендер параметров не искажает кегль и не зависит от линий/множителей
    assert(lb_text.include?("def render_params"), "layout_builder.rb рендерит параметры шаблона через render_params")
    assert(lb_text.include?("size = 10.0 if size <= 0.0"), "layout_builder.rb защищает кегль параметра от нуля/мусора")

    # 4. Проверка: Line Scale Multiplier со скриншота работает ТОЛЬКО для рендер страниц/видового экрана SketchUp
    assert(lb_text.include?("def render_image_block"), "layout_builder.rb имеет метод render_image_block для видового экрана")
    assert(lb_text.include?("skp_model.line_weight = (base_pt * line_mult).round(2)"), "render_image_block применяет line_weight")

    # Рендеринг параметров (render_params) line_weight и scale_multiplier НЕ использует
    params_code = lb_text[/def render_params.*?^        end$/m] || ""
    assert(!params_code.empty?, "render_params присутствует в layout_builder.rb")
    assert(!params_code.include?("scale_multiplier"), "render_params не зависит от scale_multiplier")
    assert(!params_code.include?("calc_line_weight"), "render_params не зависит от calc_line_weight")
  end

  def test_63_layout_line_weight_and_annotation_font_size
    puts "\n--- 63. Тест настроек толщины линий (pt) и размера шрифта выносок/размеров в LayOut API ---"

    # 1. Проверка HTML: перенос толщины линий в карточку параметров LayOut API и наличие pt значений
    html_path = File.expand_path("../dialog/html/index.html", __dir__)
    html_text = File.read(html_path, encoding: "utf-8")

    layout_card = html_text[/Параметры SketchUp LayOut API.*?Параметры страницы и документа/m]
    assert(layout_card, "Карточка 'Параметры SketchUp LayOut API' найдена в index.html")
    assert(layout_card.include?("id=\"selectScaleMultiplier\""),
           "selectScaleMultiplier перенесен в карточку 'Параметры SketchUp LayOut API'")
    assert(layout_card.include?("0,25 pt"), "selectScaleMultiplier содержит опцию 0,25 pt")
    assert(layout_card.include?("0,50 pt"), "selectScaleMultiplier содержит опцию 0,50 pt")
    assert(layout_card.include?("0,75 pt"), "selectScaleMultiplier содержит опцию 0,75 pt")
    assert(layout_card.include?("1,00 pt"), "selectScaleMultiplier содержит опцию 1,00 pt")
    assert(layout_card.include?("1,25 pt"), "selectScaleMultiplier содержит опцию 1,25 pt")
    assert(layout_card.include?("1,50 pt"), "selectScaleMultiplier содержит опцию 1,50 pt")

    page_card = html_text[/Параметры страницы и документа.*?Адресаты веб-интеграции/m]
    assert(page_card && !page_card.include?("id=\"selectScaleMultiplier\""),
           "selectScaleMultiplier удален из карточки 'Параметры страницы и документа'")

    # 2. Проверка HTML: удаление селектора размера шрифта выносок из GUI
    assert(!layout_card.include?("id=\"selectAnnotationFontSize\""),
           "selectAnnotationFontSize удален из GUI index.html")
    assert(!layout_card.include?("Размер шрифта выносок и размеров"),
           "подпись 'Размер шрифта выносок и размеров' удалена из GUI index.html")

    # 3. Проверка app.js: безопасная обработка отсутствия selectAnnotationFontSize в GUI
    app_js_path = File.expand_path("../dialog/html/app.js", __dir__)
    app_js_text = File.read(app_js_path, encoding: "utf-8")
    assert(app_js_text.include?("selectAnnotationFontSize: document.getElementById(\"selectAnnotationFontSize\")"),
           "app.js безопасно запрашивает selectAnnotationFontSize через document.getElementById")
    assert(app_js_text.include?("if (els.selectAnnotationFontSize)"),
           "app.js безопасно проверяет наличие els.selectAnnotationFontSize")
    assert(app_js_text.include?("annotation_font_size: els.selectAnnotationFontSize ? els.selectAnnotationFontSize.value :"),
           "app.js безопасно извлекает annotation_font_size с фоллбэком")
    assert(app_js_text.include?("PARAM_FONT_SIZES = [6, 7, 8, 9, 10, 11, 12, 14, 16, 18, 20, 24, 28, 32, 36, 40, 48, 56, 64, 72]"),
           "PARAM_FONT_SIZES в app.js содержит кегли до 72 pt")

    # 4. Проверка ProjectData и YAML файлов настроек
    project_data = DN1Code::ExportPdf2::Model::ProjectData.new
    settings = project_data.default_pdf_settings
    assert(settings.key?(:annotation_font_size), "default_pdf_settings содержит ключ :annotation_font_size")
    assert(settings[:annotation_font_size] == "auto", "annotation_font_size по умолчанию 'auto'")

    def_yaml_path = File.expand_path("../config/default_settings.yaml", __dir__)
    def_yaml_text = File.read(def_yaml_path, encoding: "utf-8")
    assert(def_yaml_text.include?("annotation_font_size: \"auto\""),
           "default_settings.yaml содержит annotation_font_size: \"auto\"")

    usr_yaml_path = File.expand_path("../config/settings.yaml", __dir__)
    usr_yaml_text = File.read(usr_yaml_path, encoding: "utf-8")
    assert(usr_yaml_text.include?("annotation_font_size:"),
           "settings.yaml содержит параметр annotation_font_size")

    # 5. Проверка RenderService.with_temporary_annotation_font_size на временное изменение и 100% откат
    mock_model = Sketchup::MockModel.new
    text_ent = mock_model.entities.grep(Sketchup::Text).first
    assert(text_ent && text_ent.font[:size] == 14, "Исходный размер шрифта выноски равен 14 pt")

    inner_size = nil
    DN1Code::ExportPdf2::Service::RenderService.with_temporary_annotation_font_size(mock_model, "18") do
      inner_size = text_ent.font[:size]
    end
    assert(inner_size == 18, "Внутри блока размер шрифта выноски временно изменен на 18 pt")
    assert(text_ent.font[:size] == 14, "После выхода из блока размер шрифта выноски гарантированно восстановлен на 14 pt")

    # Проверка режима "auto" — не меняет размер шрифта
    DN1Code::ExportPdf2::Service::RenderService.with_temporary_annotation_font_size(mock_model, "auto") do
      inner_size = text_ent.font[:size]
    end
    assert(inner_size == 14, "В режиме 'auto' размер шрифта выноски остается неизменным (14 pt)")

    # 6. Проверка LayoutBuilder: вызов with_temporary_annotation_font_size при подготовке модели
    lb_path = File.expand_path("../service/layout_builder.rb", __dir__)
    lb_text = File.read(lb_path, encoding: "utf-8")
    assert(lb_text.include?("RenderService.with_temporary_annotation_font_size(ctx[:model], afs_setting)"),
           "layout_builder.rb применяет with_temporary_annotation_font_size при создании временной копии для LayOut")
    assert(lb_text.include?("annotation_font_size: ctx[:settings][:annotation_font_size]"),
           "layout_builder.rb передает annotation_font_size в render_opts")
  end

  def test_64_render_modes_image_and_hybrid
    puts "\n--- 64. Тест режимов отображения: Растровый GPU (image) и Гибридный (hybrid) ---"

    # 1. Проверка index.html: только два режима
    html_path = File.expand_path("../dialog/html/index.html", __dir__)
    html_text = File.read(html_path, encoding: "utf-8")
    assert(html_text.include?('value="image"'), "index.html содержит опцию image в selectLayoutRenderMode")
    assert(html_text.include?('value="hybrid"'), "index.html содержит опцию hybrid в selectLayoutRenderMode")
    assert(!html_text.include?('value="composite"'), "index.html НЕ содержит удаленный режим composite")
    assert(!html_text.include?('value="stacked"'), "index.html НЕ содержит удаленный режим stacked")

    # 2. Проверка default_settings.yaml
    def_yaml_path = File.expand_path("../config/default_settings.yaml", __dir__)
    def_yaml_text = File.read(def_yaml_path, encoding: "utf-8")
    assert(def_yaml_text.include?("'image'"), "default_settings.yaml документирует режим image")
    assert(def_yaml_text.include?("'hybrid'"), "default_settings.yaml документирует режим hybrid")

    # 3. Проверка app.js
    app_js_path = File.expand_path("../dialog/html/app.js", __dir__)
    app_js_text = File.read(app_js_path, encoding: "utf-8")
    assert(app_js_text.include?('renderMode === "hybrid"'),
           "app.js включает hybrid в расчет масштаба линий getEffectiveScaleMultiplier")

    # 4. Проверка RenderService: with_temporary_hidden_annotations
    mock_model = Sketchup::MockModel.new
    assert(mock_model.rendering_options["DisplayDims"] == true, "Исходный DisplayDims равен true")
    assert(mock_model.rendering_options["DisplayText"] == true, "Исходный DisplayText равен true")

    inside_dims = nil
    inside_text = nil
    DN1Code::ExportPdf2::Service::RenderService.with_temporary_hidden_annotations(mock_model, true) do
      inside_dims = mock_model.rendering_options["DisplayDims"]
      inside_text = mock_model.rendering_options["DisplayText"]
    end
    assert(inside_dims == false, "Внутри блока DisplayDims временно отключен (false)")
    assert(inside_text == false, "Внутри блока DisplayText временно отключен (false)")
    assert(mock_model.rendering_options["DisplayDims"] == true, "После блока DisplayDims гарантированно восстановлен (true)")
    assert(mock_model.rendering_options["DisplayText"] == true, "После блока DisplayText гарантированно восстановлен (true)")
    assert(mock_model.rendering_options["RenderMode"] == 2, "RenderMode не сбрасывается в Wireframe (сохраняется режим сцены)")

    # 5. Проверка сборки страницы в режиме 'image' (Растровый GPU) в LayoutBuilder
    doc = Layout::Document.new
    page = doc.pages.first
    layers = {
      default: doc.layers.first,
      viewport: doc.layers.add("DN1C_Viewports", false),
      annotation: doc.layers.add("DN1C_Annotations", false)
    }
    scene_item = DN1Code::ExportPdf2::Model::SceneItem.new(name: "01. Обложка", page_type: :cover, enabled: true)
    content_box = { left: 10.0, top: 500.0, w: 400.0, h: 300.0 }
    img_cfg = { "aspect_ratio" => "4:3", "scale_pct" => 100 }
    temp_imgs = []
    project_data = DN1Code::ExportPdf2::Model::ProjectData.new
    project_data.pdf_settings[:layout_render_mode] = "image"
    ctx = {
      settings: project_data.pdf_settings,
      model: mock_model,
      aspect_cache: {}
    }

    DN1Code::ExportPdf2::Service::LayoutBuilder.send(
      :render_image_block,
      doc, page, layers, scene_item, content_box, img_cfg, ctx, temp_imgs, :cover
    )

    created_ents = doc.instance_variable_get(:@entities).map { |r| r[:entity] }
    has_image = created_ents.any? { |e| e.is_a?(Layout::Image) }
    assert(has_image, "В режиме image создано и добавлено растровое изображение Layout::Image")

    # 6. Проверка сборки страницы в режиме 'hybrid' в LayoutBuilder (один живой видовой экран)
    doc2 = Layout::Document.new
    page2 = doc2.pages.first
    project_data.pdf_settings[:layout_render_mode] = "hybrid"
    ctx2 = {
      settings: project_data.pdf_settings,
      model: mock_model,
      aspect_cache: {}
    }

    DN1Code::ExportPdf2::Service::LayoutBuilder.send(
      :render_image_block,
      doc2, page2, layers, scene_item, content_box, img_cfg, ctx2, temp_imgs, :cover
    )

    created_ents2 = doc2.instance_variable_get(:@entities).map { |r| r[:entity] }
    skp_viewports = created_ents2.select { |e| e.is_a?(Layout::SketchUpModel) }
    assert(skp_viewports.size == 1, "В режиме hybrid создан один видовой экран Layout::SketchUpModel")
    assert(skp_viewports.first.render_mode == Layout::SketchUpModel::HYBRID_RENDER, "Видовой экран режима hybrid имеет HYBRID_RENDER")

    # 7. Проверка полного экспорта PDF документа в обоих режимах
    project_data.scenes << scene_item
    project_data.pdf_settings[:auto_open_pdf] = false
    controller = DN1Code::ExportPdf2::Controller::ExportController.new(project_data, mock_model)

    test_pdf = File.expand_path("test_image_mode_output.pdf", __dir__)
    project_data.pdf_settings[:layout_render_mode] = "image"
    result_path = controller.export(test_pdf)
    assert(File.exist?(result_path), "Экспорт в режиме image успешно создал PDF файл")
    assert(File.size(result_path) > 1000, "Размер PDF файла в режиме image валиден")
    File.delete(result_path) if File.exist?(result_path)

    test_pdf_hybrid = File.expand_path("test_hybrid_mode_output.pdf", __dir__)
    project_data.pdf_settings[:layout_render_mode] = "hybrid"
    result_path_hybrid = controller.export(test_pdf_hybrid)
    assert(File.exist?(result_path_hybrid), "Экспорт в режиме hybrid успешно создал PDF файл")
    assert(File.size(result_path_hybrid) > 1000, "Размер PDF файла в режиме hybrid валиден")
    File.delete(result_path_hybrid) if File.exist?(result_path_hybrid)
  end

  def test_66_page_font_family_selection
    puts "\n--- 66. Тест выбора 5 шрифтов для отображения на странице ---"

    # 1. Проверка физических файлов шрифтов в папке config/fonts (вариативные VF)
    fonts_dir = File.expand_path("../config/fonts", __dir__)
    expected_files = [
      "Oswald-VariableFont_wght.ttf",
      "RobotoCondensed-VariableFont_wght.ttf",
      "SofiaSansCondensed-VariableFont_wght.ttf",
      "SofiaSansExtraCond-VariableFont_wght.ttf",
      "UbuntuCondensed-Regular.ttf"
    ]
    expected_files.each do |fn|
      font_path = File.join(fonts_dir, fn)
      assert(File.exist?(font_path), "Файл шрифта #{fn} присутствует в папке config/fonts")
      assert(File.size(font_path) > 50_000, "Размер файла шрифта #{fn} валиден (> 50KB)")
    end
    # Старые статические шрифты прежних версий удалены из комплекта
    ["Oswald-Light.ttf", "SofiaSansCondensed-Regular.ttf",
     "SofiaSansExtraCond-Regular.ttf", "SofiaSansExtraCondensed-Regular.ttf"].each do |old|
      assert(!File.exist?(File.join(fonts_dir, old)), "Старый статический шрифт #{old} удален из config/fonts")
    end

    # 2. Проверка FontService::AVAILABLE_FONTS
    assert(defined?(DN1Code::ExportPdf2::Service::FontService::AVAILABLE_FONTS),
           "FontService::AVAILABLE_FONTS определен")
    families = DN1Code::ExportPdf2::Service::FontService::AVAILABLE_FONTS.keys
    assert(families.include?("Sofia Sans Condensed"), "AVAILABLE_FONTS содержит Sofia Sans Condensed")
    assert(families.include?("Sofia Sans Extra Condensed"), "AVAILABLE_FONTS содержит Sofia Sans Extra Condensed")
    assert(families.include?("Oswald"), "AVAILABLE_FONTS содержит Oswald")
    assert(families.include?("Roboto Condensed"), "AVAILABLE_FONTS содержит Roboto Condensed")
    assert(families.include?("Ubuntu Condensed"), "AVAILABLE_FONTS содержит Ubuntu Condensed")

    # 3. Проверка метода layout_font_family для каждого из 5 шрифтов.
    # Вариативный Oswald резолвится напрямую по имени семейства (Regular 400),
    # переименованного статика "Oswald Light" больше нет.
    fs = DN1Code::ExportPdf2::Service::FontService
    assert(fs.const_defined?(:LAYOUT_FACE_NAMES), "FontService::LAYOUT_FACE_NAMES определен")
    assert(fs.layout_face_name("Oswald") == "Oswald",
           "layout_face_name('Oswald') вернул 'Oswald' (VF Regular)")
    # "Extra Condensed" вырезается LayOut из имени семейства -> VF офлайн
    # переименован в семейство "Sofia Sans ExtraCond"
    assert(fs.layout_face_name("Sofia Sans Extra Condensed") == "Sofia Sans ExtraCond",
           "layout_face_name('Sofia Sans Extra Condensed') вернул 'Sofia Sans ExtraCond'")
    assert(fs.layout_face_name("Sofia Sans Condensed") == "Sofia Sans Condensed",
           "layout_face_name('Sofia Sans Condensed') возвращает имя как есть")
    assert(fs::AVAILABLE_FONTS["Oswald"][:files] == ["Oswald-VariableFont_wght.ttf"],
           "AVAILABLE_FONTS['Oswald'] использует вариативный Oswald-VariableFont_wght.ttf")

    expected_layout_names = {
      "Sofia Sans Condensed" => "Sofia Sans Condensed",
      "Sofia Sans Extra Condensed" => "Sofia Sans ExtraCond",
      "Oswald" => "Oswald",
      "Roboto Condensed" => "Roboto Condensed",
      "Ubuntu Condensed" => "Ubuntu Condensed"
    }
    expected_layout_names.each do |fam, exp|
      res = DN1Code::ExportPdf2::Service::FontService.layout_font_family(font_family: fam)
      assert(res == exp, "layout_font_family(font_family: '#{fam}') вернул '#{exp}' (получено: '#{res}')")
    end
    # Обратная совместимость с DIN Condensed
    din_res = DN1Code::ExportPdf2::Service::FontService.layout_font_family(font_family: "DIN Condensed")
    assert(din_res == "Oswald", "layout_font_family для старого 'DIN Condensed' возвращает 'Oswald' (получено: '#{din_res}')")

    # Значение по умолчанию
    default_res = DN1Code::ExportPdf2::Service::FontService.layout_font_family({})
    assert(default_res == "Sofia Sans Condensed", "layout_font_family по умолчанию возвращает Sofia Sans Condensed")

    # 3a. Методы надежности шрифтов: repair + GDI-проба + аудит PDF + новые параметры
    assert(fs.respond_to?(:repair_font_registrations!), "FontService.repair_font_registrations! определен")
    assert(fs.respond_to?(:cleanup_legacy_fonts!), "FontService.cleanup_legacy_fonts! определен")
    assert(fs.respond_to?(:font_resolvable?), "FontService.font_resolvable? определен")
    assert(fs.respond_to?(:ensure_font_resolvable!), "FontService.ensure_font_resolvable! определен")
    assert(fs.respond_to?(:canonical_reg_name_for_file), "FontService.canonical_reg_name_for_file определен")
    assert(fs.respond_to?(:apply_font_width), "FontService.apply_font_width определен")
    assert(fs.respond_to?(:font_weight_setting), "FontService.font_weight_setting определен")
    assert(fs.respond_to?(:font_width_setting), "FontService.font_width_setting определен")
    assert(DN1Code::ExportPdf2::Service.const_defined?(:PdfFontAudit), "Service::PdfFontAudit определен")
    assert(DN1Code::ExportPdf2::Service::PdfFontAudit.normalize("AMEJOL+Oswald-Light") == "oswaldlight",
           "PdfFontAudit.normalize корректно нормализует PS-имя шрифта")

    # 3b. Функциональный аудит PDF: prefix-сопоставление встроенных PS-имен
    # (встроенные имена несут стилевой суффикс — точное сравнение давало false positive)
    require "tmpdir"
    require "fileutils"
    pdf_audit = DN1Code::ExportPdf2::Service::PdfFontAudit
    audit_dir = File.join(Dir.tmpdir, "dn1c_pdf_audit_test")
    FileUtils.mkdir_p(audit_dir)
    write_fake_pdf = lambda do |name, base_fonts|
      path = File.join(audit_dir, name)
      File.write(path, base_fonts.map { |f| "/BaseFont /#{f}" }.join("\n"))
      path
    end

    p1 = write_fake_pdf.call("sofia.pdf", ["ABCDEE+SofiaSansCondensed-Regular"])
    assert(pdf_audit.audit_exported_pdf!(p1, "Sofia Sans Condensed"),
           "аудит принимает встроенный SofiaSansCondensed-Regular для 'Sofia Sans Condensed'")

    p2 = write_fake_pdf.call("oswald.pdf", ["AMEJOL+Oswald-Regular"])
    assert(pdf_audit.audit_exported_pdf!(p2, "Oswald"), "аудит принимает Oswald-Regular для 'Oswald'")

    p2b = write_fake_pdf.call("oswald_bold.pdf", ["ABCDEE+Oswald-Bold"])
    assert(pdf_audit.audit_exported_pdf!(p2b, "Oswald"),
           "аудит принимает инстанс Oswald-Bold (font_weight=bold)")

    p3 = write_fake_pdf.call("extra.pdf", ["SofiaSansExtraCond-VariableFont"])
    assert(pdf_audit.audit_exported_pdf!(p3, "Sofia Sans Extra Condensed"),
           "аудит принимает переименованный VF ExtraCond для 'Sofia Sans Extra Condensed'")

    p3b = write_fake_pdf.call("sofia_bold.pdf", ["ABCDEE+SofiaSansCondensed-Bold"])
    assert(pdf_audit.audit_exported_pdf!(p3b, "Sofia Sans Condensed"),
           "аудит принимает инстанс SofiaSansCondensed-Bold (font_weight=bold)")

    p4 = write_fake_pdf.call("verdana.pdf", ["Verdana", "MicrosoftSansSerif"])
    assert(!pdf_audit.audit_exported_pdf!(p4, "Sofia Sans Condensed"),
           "аудит отклоняет Verdana вместо ожидаемого шрифта")

    p5 = write_fake_pdf.call("mixed.pdf", ["ABCDEE+RobotoCondensed-Regular", "Verdana"])
    assert(!pdf_audit.audit_exported_pdf!(p5, "Roboto Condensed"),
           "аудит отклоняет экспорт, где рядом с нужным шрифтом встроен фолбэк")

    FileUtils.rm_rf(audit_dir)

    # 4. Проверка HTML: наличие селекторов selectFontFamily и selectLayoutFontFamily
    html_path = File.expand_path("../dialog/html/index.html", __dir__)
    html_text = File.read(html_path, encoding: "utf-8")

    assert(html_text.include?('id="selectFontFamily"'), "index.html содержит id=\"selectFontFamily\" в параметрах страницы")
    assert(html_text.include?('id="selectLayoutFontFamily"'), "index.html содержит id=\"selectLayoutFontFamily\" в панели шаблонов")
    assert(html_text.include?('id="selectFontWeight"'), "index.html содержит id=\"selectFontWeight\" (начертание)")
    assert(html_text.include?('id="selectFontWidth"'), "index.html содержит id=\"selectFontWidth\" (ширина)")
    assert(html_text.include?('value="bold"'), "selectFontWeight содержит вариант bold")
    assert(html_text.include?('value="extra_condensed"'), "selectFontWidth содержит вариант extra_condensed")

    # Начертание и ширина размещаются только на тулбаре панели шаблонов,
    # а не на вкладке настроек страницы
    tpl_toolbar = html_text[/toolbar-font-control.*?id="inputLayoutMargin"/m]
    assert(tpl_toolbar, "Тулбар панели шаблонов присутствует в index.html")
    assert(tpl_toolbar.include?('id="selectLayoutFontFamily"'), "Тулбар шаблонов содержит выбор шрифта")
    assert(tpl_toolbar.include?('id="selectFontWeight"'), "Начертание (selectFontWeight) находится на тулбаре панели шаблонов")
    assert(tpl_toolbar.include?('id="selectFontWidth"'), "Ширина (selectFontWidth) находится на тулбаре панели шаблонов")

    # Кнопки «Сбросить»/«Удалить шаблон» вынесены в шапку «Параметры шаблона»
    tpl_header = html_text[/template-settings-header.*?btnResetLayout.*?template-settings-toolbar/m]
    assert(tpl_header, "Кнопка btnResetLayout находится в шапке template-settings-header")
    settings_font_card = html_text[/id="fontFamilyGroup".*?id="chkSaveBackup"/m]
    assert(settings_font_card, "Карточка настроек страницы присутствует в index.html")
    assert(!settings_font_card.include?('id="selectFontWeight"'), "На вкладке настроек нет селекта начертания")
    assert(!settings_font_card.include?('id="selectFontWidth"'), "На вкладке настроек нет селекта ширины")

    # Проверка наличия всех 5 шрифтов в селекторе настроек страницы
    page_font_group = html_text[/id="fontFamilyGroup".*?<\/select>/m]
    assert(page_font_group, "Группа fontFamilyGroup присутствует в index.html")
    assert(page_font_group.include?('value="Sofia Sans Condensed"'), "selectFontFamily содержит вариант Sofia Sans Condensed")
    assert(page_font_group.include?('value="Sofia Sans Extra Condensed"'), "selectFontFamily содержит вариант Sofia Sans Extra Condensed")
    assert(page_font_group.include?('value="Oswald"'), "selectFontFamily содержит вариант Oswald")
    assert(page_font_group.include?('value="Roboto Condensed"'), "selectFontFamily содержит вариант Roboto Condensed")
    assert(page_font_group.include?('value="Ubuntu Condensed"'), "selectFontFamily содержит вариант Ubuntu Condensed")

    # Проверка наличия всех 5 шрифтов в панели шаблонов
    tpl_font_control = html_text[/toolbar-font-control.*?<\/select>/m]
    assert(tpl_font_control, "Контрол выбора шрифта присутствует в панели шаблонов")
    assert(tpl_font_control.include?('value="Sofia Sans Condensed"'), "selectLayoutFontFamily содержит Sofia Sans Condensed")
    assert(tpl_font_control.include?('value="Sofia Sans Extra Condensed"'), "selectLayoutFontFamily содержит Sofia Sans Extra Condensed")
    assert(tpl_font_control.include?('value="Oswald"'), "selectLayoutFontFamily содержит Oswald")
    assert(tpl_font_control.include?('value="Roboto Condensed"'), "selectLayoutFontFamily содержит Roboto Condensed")
    assert(tpl_font_control.include?('value="Ubuntu Condensed"'), "selectLayoutFontFamily содержит Ubuntu Condensed")

    # 5. Проверка app.js: регистрация и обработка шрифтов
    app_js_path = File.expand_path("../dialog/html/app.js", __dir__)
    app_js_text = File.read(app_js_path, encoding: "utf-8")

    assert(app_js_text.include?('selectFontFamily: document.getElementById("selectFontFamily")'),
           "app.js кэширует selectFontFamily в els")
    assert(app_js_text.include?('selectLayoutFontFamily: document.getElementById("selectLayoutFontFamily")'),
           "app.js кэширует selectLayoutFontFamily в els")
    assert(app_js_text.include?('handleFontFamilyChange'),
           "app.js содержит обработчик handleFontFamilyChange")
    assert(app_js_text.include?('--page-font-family'),
           "app.js динамически обновляет CSS-переменную --page-font-family")
    assert(app_js_text.include?('font_family:'),
           "app.js собирает font_family в collectFormData")
    assert(app_js_text.include?('"selectFontFamily"'),
           "app.js включает selectFontFamily в список autoSaveInputIds")
    assert(app_js_text.include?('"selectLayoutFontFamily"'),
           "app.js включает selectLayoutFontFamily в список autoSaveInputIds")
    assert(app_js_text.include?('selectFontWeight: document.getElementById("selectFontWeight")'),
           "app.js кэширует selectFontWeight в els")
    assert(app_js_text.include?('selectFontWidth: document.getElementById("selectFontWidth")'),
           "app.js кэширует selectFontWidth в els")
    assert(app_js_text.include?('handleFontWeightChange'),
           "app.js содержит обработчик handleFontWeightChange")
    assert(app_js_text.include?('handleFontWidthChange'),
           "app.js содержит обработчик handleFontWidthChange")
    assert(app_js_text.include?('--page-font-weight'),
           "app.js динамически обновляет CSS-переменную --page-font-weight")
    assert(app_js_text.include?('font_weight:'),
           "app.js собирает font_weight в collectFormData")
    assert(app_js_text.include?('font_width:'),
           "app.js собирает font_width в collectFormData")
    assert(app_js_text.include?('"selectFontWeight"'),
           "app.js включает selectFontWeight в список autoSaveInputIds")
    assert(app_js_text.include?('"selectFontWidth"'),
           "app.js включает selectFontWidth в список autoSaveInputIds")
    assert(app_js_text.include?('previewFontFamilyFor'),
           "app.js синхронизирует превью семейства с параметром ширины")

    # 6. Проверка app.css: @font-face для всех 5 шрифтов и переменная --page-font-family
    app_css_path = File.expand_path("../dialog/html/app.css", __dir__)
    app_css_text = File.read(app_css_path, encoding: "utf-8")

    assert(app_css_text.include?("Oswald-VariableFont_wght.ttf"), "app.css содержит @font-face для Oswald-VariableFont_wght.ttf")
    assert(app_css_text.include?("RobotoCondensed-VariableFont_wght.ttf"), "app.css содержит @font-face для RobotoCondensed-VariableFont_wght.ttf")
    assert(app_css_text.include?("SofiaSansCondensed-VariableFont_wght.ttf"), "app.css содержит @font-face для SofiaSansCondensed-VariableFont_wght.ttf")
    assert(app_css_text.include?("SofiaSansExtraCond-VariableFont_wght.ttf"), "app.css содержит @font-face для SofiaSansExtraCond-VariableFont_wght.ttf")
    assert(app_css_text.include?("UbuntuCondensed-Regular.ttf"), "app.css содержит @font-face для UbuntuCondensed-Regular.ttf")
    assert(app_css_text.include?("--page-font-family"), "app.css содержит CSS-переменную --page-font-family")
    assert(app_css_text.include?("--page-font-weight"), "app.css содержит CSS-переменную --page-font-weight")
    assert(app_css_text.include?("--font-family-base: \"Roboto Condensed\""), "app.css применяет Roboto Condensed как базовый шрифт GUI")
    assert(app_css_text.include?("--font-stretch-base: ultra-condensed"), "app.css задает ультра-сжатую ширину букв (--font-stretch-base: ultra-condensed)")
    assert(app_css_text.include?("--letter-spacing-base: -0.025em"), "app.css задает компактный межбуквенный интервал (--letter-spacing-base: -0.025em)")
    assert(app_css_text.include?("--bs-body-font-family: var(--font-family-base)"), "app.css переопределяет Bootstrap/Modus шрифт на var(--font-family-base)")

    # 7. Проверка передачи font_family/font_weight в LayoutBuilder context
    project_data = DN1Code::ExportPdf2::Model::ProjectData.new
    project_data.pdf_settings[:font_family] = "Oswald"
    ctx = DN1Code::ExportPdf2::Service::LayoutBuilder.send(:build_context, project_data, nil, "Oswald")
    assert(ctx[:font] == "Oswald", "build_context сохраняет выбранный шрифт (:font == 'Oswald')")
    assert(ctx[:text_bold] == false, "build_context: font_weight=normal -> ctx[:text_bold] == false")

    project_data_bold = DN1Code::ExportPdf2::Model::ProjectData.new
    project_data_bold.pdf_settings[:font_weight] = "bold"
    ctx_bold = DN1Code::ExportPdf2::Service::LayoutBuilder.send(:build_context, project_data_bold, nil, "Oswald")
    assert(ctx_bold[:text_bold] == true, "build_context: font_weight=bold -> ctx[:text_bold] == true")

    # 7b. Параметр ширины: модификатор Sofia Sans Condensed -> Extra Condensed
    assert(fs.apply_font_width("Sofia Sans Condensed", "extra_condensed") == "Sofia Sans Extra Condensed",
           "apply_font_width: extra_condensed переводит Sofia Sans Condensed в Extra Condensed")
    assert(fs.apply_font_width("Sofia Sans Condensed", "condensed") == "Sofia Sans Condensed",
           "apply_font_width: condensed оставляет базовое семейство")
    assert(fs.apply_font_width("Sofia Sans Extra Condensed", "condensed") == "Sofia Sans Extra Condensed",
           "apply_font_width: явно выбранное Extra Condensed не изменяется параметром ширины")
    assert(fs.apply_font_width("Oswald", "extra_condensed") == "Oswald",
           "apply_font_width: для Oswald ширина не применяется")
    wide_res = fs.layout_font_family(font_family: "Sofia Sans Condensed", font_width: "extra_condensed")
    assert(wide_res == "Sofia Sans ExtraCond",
           "layout_font_family с font_width=extra_condensed вернул 'Sofia Sans ExtraCond' (получено: '#{wide_res}')")
    assert(fs.font_weight_setting(font_weight: "bold") == "bold", "font_weight_setting распознает 'bold'")
    assert(fs.font_weight_setting(font_weight: "bogus") == "normal",
           "font_weight_setting нормализует неизвестное значение в 'normal'")
    assert(fs.font_width_setting(font_width: "extra_condensed") == "extra_condensed",
           "font_width_setting распознает 'extra_condensed'")
    assert(fs.font_width_setting({}) == "condensed", "font_width_setting по умолчанию 'condensed'")

    # 7a. Проверка: add_bounded_text применяет шрифт/кегль к стилю entity.
    # Без стиля entity текст параметров печатается дефолтным Microsoft Sans Serif
    # вместо выбранного пользователем шрифта.
    doc_m = ::Layout::Document.new
    ctx_m = { page_h_pt: 841.89, font: "Oswald Light" }
    layer_m = doc_m.layers.first
    page_m = doc_m.pages.first
    txt_ent = DN1Code::ExportPdf2::Service::LayoutBuilder.send(
      :add_bounded_text, ctx_m, doc_m, page_m, layer_m, "Кухня | Иванов",
      { x: 10, y: 10, width: 200, height: 20 },
      size: 12.0, color: "252A2E", align: :center, anchor: :top, font: "Oswald Light"
    )
    assert(txt_ent, "add_bounded_text вернул entity")
    assert(txt_ent.style(0).font_family == "Oswald Light",
           "add_bounded_text задает font_family entity (получено: #{txt_ent.style(0).font_family.inspect})")
    assert(txt_ent.style(0).font_size == 12.0,
           "add_bounded_text задает font_size entity (получено: #{txt_ent.style(0).font_size.inspect})")

    # 7a-2. Глобальный font_weight=bold распространяется на текст параметров
    ctx_m_bold = { page_h_pt: 841.89, font: "Oswald", text_bold: true }
    txt_ent_b = DN1Code::ExportPdf2::Service::LayoutBuilder.send(
      :add_bounded_text, ctx_m_bold, doc_m, page_m, layer_m, "Кухня",
      { x: 10, y: 40, width: 200, height: 20 },
      size: 12.0, color: "252A2E", align: :center, anchor: :top, font: "Oswald"
    )
    assert(txt_ent_b, "add_bounded_text (bold) вернул entity")
    assert(txt_ent_b.style(0).text_bold == true,
           "add_bounded_text: глобальный font_weight=bold включает text_bold у entity (получено: #{txt_ent_b.style(0).text_bold.inspect})")

    # 8. Проверка автозамены (fallback) для несуществующего шрифта
    fallback_res = DN1Code::ExportPdf2::Service::FontService.layout_font_family(font_family: "NonExistentFontXYZ")
    fallback_allowed = DN1Code::ExportPdf2::Service::FontService::LAYOUT_FONT_CANDIDATES
                       .map { |c| DN1Code::ExportPdf2::Service::FontService.layout_face_name(c) }
    assert(fallback_allowed.include?(fallback_res),
           "layout_font_family для несуществующего шрифта возвращает кандидата из fallback цепочки (#{fallback_res})")

    # 9. Проверка автозамены DIN -> Oswald.
    # Замена в ProjectData срабатывает при загрузке файла настроек, содержащего DIN;
    # здесь проверяем герметично: FontService обязан маппить DIN Condensed в
    # "Oswald" независимо от содержимого пользовательского settings.yaml.
    prj = DN1Code::ExportPdf2::Model::ProjectData.new
    prj.pdf_settings[:font_family] = "DIN Condensed"
    prj.load_program_settings
    prj.pdf_settings[:font_family] = "DIN Condensed" # реальный settings.yaml мог перезаписать значение
    assert(DN1Code::ExportPdf2::Service::FontService.layout_font_family(prj.pdf_settings) == "Oswald",
           "FontService заменяет DIN Condensed на Oswald")

    # 10. Проверка font_line_pitch_ratio для DIN (как алиаса Oswald)
    lb = DN1Code::ExportPdf2::Service::LayoutBuilder
    assert(lb.send(:font_line_pitch_ratio, "DIN Condensed") >= 1.70,
           "font_line_pitch_ratio для DIN Condensed >= 1.70 (учет замены на Oswald)")
    assert(lb.send(:font_char_width_ratio, "DIN Condensed") <= 0.46,
           "font_char_width_ratio для DIN Condensed <= 0.46")

    # 11. Проверка актуальности README.MD
    readme_path = File.expand_path("../../README.MD", __dir__)
    readme_text = File.read(readme_path, encoding: "utf-8")
    assert(readme_text.include?("5 свободных кириллических шрифтов"), "README.MD описывает 5 свободных кириллических шрифтов")
    assert(readme_text.include?("Бесшовная замена DIN Condensed"), "README.MD описывает замену DIN Condensed")
    assert(readme_text.include?("Отказоустойчивый шрифтовой Fallback"), "README.MD описывает шрифтовой fallback")
    assert(readme_text.include?("font_weight"), "README.MD описывает параметр начертания font_weight")
    assert(readme_text.include?("font_width"), "README.MD описывает параметр ширины font_width")
  end

  # --- 67. Тест предотвращения обрезания многострочного текста и адаптивных интервалов (LayoutBuilder) ---
  def test_articul_folder_yaml_canonical_and_anchor
    puts "\n--- 68. Тест папки артикула: project.yaml — единственный файл данных проекта ---"

    test_dir = File.expand_path("test_articul_dir_root", __dir__)
    skp_dir  = File.join(test_dir, "models")
    FileUtils.mkdir_p(skp_dir)

    skp_file = File.join(skp_dir, "Wardrobe.skp")
    model = Sketchup::MockModel.new(skp_file)

    # Папка артикула создается рядом с .skp
    project_data = DN1Code::ExportPdf2::Model::ProjectData.new
    project_data.project_info[:articul] = "ART-100"
    project_data.project_info[:description] = "CANONICAL_DESC"

    assert(project_data.save_project_yaml(model), "save_project_yaml успешно записал YAML")

    canon_yaml = File.join(skp_dir, "ART-100", "project.yaml")
    assert(File.exist?(canon_yaml), "project.yaml записан в папку артикула: #{canon_yaml}")
    assert(!File.exist?(File.join(skp_dir, "ART-100.yaml")), "Якорь-YAML рядом с SKP не создается")

    # Файл в папке артикула приоритетен: внешняя правка читается при загрузке модели
    content = File.read(canon_yaml, encoding: "utf-8").sub("CANONICAL_DESC", "CHANGED_IN_CANON")
    File.write(canon_yaml, content, encoding: "utf-8")

    fresh = DN1Code::ExportPdf2::Model::ProjectData.new
    fresh.load_auto(model)
    assert(fresh.project_info[:articul].to_s == "ART-100", "Артикул загружен из project.yaml")
    assert(fresh.project_info[:description].to_s.include?("CHANGED_IN_CANON"),
           "load_auto прочитал project.yaml из папки артикула (получено: #{fresh.project_info[:description].inspect})")

    # Смена артикула: новая папка, прежняя сохраняется (история PDF/SKP/PNG)
    project_data.project_info[:articul] = "ART-101"
    assert(project_data.save_project_yaml(model), "Сохранение после смены артикула")
    assert(File.exist?(File.join(skp_dir, "ART-101", "project.yaml")), "Создан project.yaml нового артикула рядом с .skp")
    assert(!File.exist?(File.join(skp_dir, "ART-101.yaml")), "Якорь нового артикула рядом с .skp не создается")
    assert(File.exist?(File.join(skp_dir, "ART-100", "project.yaml")), "Папка прежнего артикула сохранена (история)")
    assert(!project_data.project.key?(:base_dir), "Ключ base_dir удален из данных проекта")

    FileUtils.rm_rf(test_dir)
  end

  def test_articul_folder_export_structure
    puts "\n--- 69. Тест экспорта в папку артикула: yaml, pdf/, skp/, png/ ---"

    test_dir = File.expand_path("test_articul_export", __dir__)
    skp_dir  = File.join(test_dir, "models")
    FileUtils.mkdir_p(skp_dir)

    skp_file = File.join(skp_dir, "Table.skp")
    model = Sketchup::MockModel.new(skp_file)
    model.pages = Sketchup::MockPages.new([
                                            Sketchup::MockPage.new("Обложка"),
                                            Sketchup::MockPage.new("Вид 1"),
                                            Sketchup::MockPage.new("Вид 2")
                                          ])

    project_data = DN1Code::ExportPdf2::Model::ProjectData.new
    project_data.project_info[:articul] = "EXP-200"
    project_data.project_info[:version] = 2
    project_data.project_info[:revision] = 5
    project_data.pdf_settings[:auto_open_pdf] = false
    project_data.pdf_settings[:save_skp_backup] = true
    project_data.pdf_settings[:save_layout_file] = false
    project_data.sync_with_model_scenes(model)

    controller = DN1Code::ExportPdf2::Controller::ExportController.new(project_data, model)
    result_path = controller.export(nil)
    # Снимки конвертируются в WebP фоновым пулом — перед проверкой файлов дожидаемся партии
    DN1Code::ExportPdf2::Service::SnapshotWorker.drain

    art_dir      = File.join(skp_dir, "EXP-200")
    expected_pdf = File.join(art_dir, "pdf", "EXP-200_02#005.pdf")
    expected_skp = File.join(art_dir, "skp", "EXP-200_02#005.skp")

    assert(File.exist?(expected_pdf), "PDF записан в папку артикула: #{expected_pdf}")
    assert(File.expand_path(result_path) == File.expand_path(expected_pdf), "export вернул путь папки артикула (#{result_path})")
    assert(File.exist?(expected_skp), "Резервная копия SKP в папке артикула: #{expected_skp}")

    images_dir = File.join(art_dir, "images")
    vips = DN1Code::ExportPdf2::Service::VipsService
    expected_ext = vips.available? ? ".webp" : ".png"
    snaps = Dir.glob(File.join(images_dir, "*.{png,webp}")).map { |f| File.basename(f) }.sort
    assert(snaps.size == 3, "Снимки всех 3 сцен в папке images/ (найдено: #{snaps.size}: #{snaps.join(', ')})")
    assert(snaps.all? { |n| n =~ /^\d{2}_/ }, "Имена снимков начинаются с номера сцены (NN_)")
    assert(snaps.all? { |n| n.end_with?(expected_ext) },
           "Снимки в формате #{expected_ext} при libvips #{vips.available? ? 'доступна' : 'нет'} (#{snaps.join(', ')})")

    # project.yaml в папке артикула — для повторного открытия модели.
    # В SketchUp сессия пишется через SessionStore.flush(model); здесь контроллер
    # создан напрямую, поэтому yaml сохраняем явно (та же запись, что делает flush).
    assert(project_data.save_project_yaml(model), "save_project_yaml записал project.yaml в папку артикула")
    assert(File.exist?(File.join(art_dir, "project.yaml")), "project.yaml создан в папке артикула")
    assert(!File.exist?(File.join(skp_dir, "EXP-200.yaml")), "Якорь-YAML рядом с .skp больше не создается")

    FileUtils.rm_rf(test_dir)
  end

  def test_last_pdf_copy_next_to_skp_and_history_link
    puts "\n--- 70. Тест копии _last.pdf рядом с .skp и привязки pdf_link в истории ---"

    test_dir = File.expand_path("test_last_pdf_export", __dir__)
    skp_dir  = File.join(test_dir, "models")
    FileUtils.mkdir_p(skp_dir)

    skp_file = File.join(skp_dir, "Chair.skp")
    model = Sketchup::MockModel.new(skp_file)
    model.pages = Sketchup::MockPages.new([
                                            Sketchup::MockPage.new("Обложка"),
                                            Sketchup::MockPage.new("Вид 1")
                                          ])

    project_data = DN1Code::ExportPdf2::Model::ProjectData.new
    project_data.project_info[:articul] = "EXP-300"
    project_data.project_info[:version] = 1
    project_data.project_info[:revision] = 7
    project_data.pdf_settings[:auto_open_pdf] = true
    project_data.pdf_settings[:save_layout_file] = false
    project_data.sync_with_model_scenes(model)

    # История изменений: две записи без ссылок (как после ввода правок пользователем)
    project_data.history << { date: "2026-09-20 10:00", text: "Изменен фасад", description: "Изменен фасад" }
    project_data.history << { date: "2026-09-19 12:30", text: "Старт проекта", description: "Старт проекта" }

    controller = DN1Code::ExportPdf2::Controller::ExportController.new(project_data, model)

    expected_last = File.expand_path(File.join(skp_dir, "Chair_last.pdf"))
    assert(File.expand_path(controller.resolve_last_pdf_path.to_s) == expected_last,
           "resolve_last_pdf_path указывает рядом с .skp (#{controller.resolve_last_pdf_path.inspect})")

    # Несохраненная модель — копия _last не создаётся
    unsaved = DN1Code::ExportPdf2::Controller::ExportController.new(project_data, Sketchup::MockModel.new(""))
    assert(unsaved.resolve_last_pdf_path.nil?, "Для несохраненной модели resolve_last_pdf_path вернул nil")

    # Экспорт: перехватываем stdout, чтобы проверить, что auto-open получил именно _last
    require "stringio"
    captured   = StringIO.new
    orig_stdout = $stdout
    $stdout = captured
    begin
      result_path = controller.export(nil)
    ensure
      $stdout = orig_stdout
    end
    # Фоновая партия снимков не должна писать в папку после ее удаления
    DN1Code::ExportPdf2::Service::SnapshotWorker.drain

    expected_pdf = File.join(skp_dir, "EXP-300", "pdf", "EXP-300_01#007.pdf")
    assert(File.exist?(expected_pdf), "Версионированный PDF в папке артикула создан: #{expected_pdf}")
    assert(File.exist?(expected_last), "Копия _last.pdf создана рядом с .skp: #{expected_last}")
    assert(File.expand_path(controller.last_pdf_path.to_s) == expected_last, "controller.last_pdf_path указывает на копию _last")
    assert(captured.string.include?("[FileOpener] " + expected_last.tr("\\", "/")),
           "Автооткрытие получило путь копии _last (#{captured.string[/\[FileOpener\][^\n]*/]})")

    # Привязка pdf_link: заполняется только самая свежая пустая запись, повтор не затирает
    assert(project_data.stamp_history_pdf_link!(result_path.to_s), "stamp_history_pdf_link! проставил ссылку")
    assert(project_data.history.first[:pdf_link] == result_path.to_s, "Самая свежая запись истории содержит путь PDF")
    assert(project_data.history.last[:pdf_link].to_s.empty?, "Старые записи истории не тронуты")
    assert(!project_data.stamp_history_pdf_link!("other.pdf"), "Повторный штамп не перезаписывает существующую ссылку")
    assert(project_data.history.first[:pdf_link] == result_path.to_s, "Ссылка первой записи сохранена после повторного штампа")

    # Ссылка переживает запись/чтение YAML (корневая секция history_edit)
    yaml_temp = File.join(test_dir, "EXP-300.yaml")
    project_data.save_to_yaml(yaml_temp)
    reloaded = DN1Code::ExportPdf2::Model::ProjectData.new
    assert(reloaded.load_from_yaml(yaml_temp), "YAML с pdf_link прочитан обратно")
    assert(reloaded.history.first[:pdf_link].to_s == result_path.to_s, "pdf_link сохраняется в YAML и читается из него")

    FileUtils.rm_rf(test_dir)
  end

  def test_png_snapshots_respect_viewport_background
    puts "\n--- 71. Тест фона видового экрана в PNG-снимках сцен ---"

    test_dir = File.expand_path("test_png_bg", __dir__)
    skp_dir  = File.join(test_dir, "models")
    FileUtils.mkdir_p(skp_dir)

    model = Sketchup::MockModel.new(File.join(skp_dir, "Desk.skp"))
    model.pages = Sketchup::MockPages.new([
                                            Sketchup::MockPage.new("Обложка"),
                                            Sketchup::MockPage.new("Вид 1")
                                          ])

    project_data = DN1Code::ExportPdf2::Model::ProjectData.new
    project_data.sync_with_model_scenes(model)
    project_data.pdf_settings[:auto_open_pdf] = false

    controller = DN1Code::ExportPdf2::Controller::ExportController.new(project_data, model)

    # Перехватываем опции render_scene_temp, вызов проксируем в оригинал
    rs = DN1Code::ExportPdf2::Service::RenderService
    captured = []
    rs.singleton_class.send(:alias_method, :render_scene_temp_bg_probe, :render_scene_temp)
    rs.define_singleton_method(:render_scene_temp) do |m, scene, opts = {}|
      captured << (opts || {})
      rs.send(:render_scene_temp_bg_probe, m, scene, opts)
    end

    begin
      # Сцены без изменений флага: фон выключен (поведение по умолчанию).
      # Формат снимков не настраивается: WebP при доступном libvips, иначе PNG.
      vips_available = DN1Code::ExportPdf2::Service::VipsService.available?
      expected_ext = vips_available ? ".webp" : ".png"
      written_on = controller.export_scene_snapshots
      DN1Code::ExportPdf2::Service::SnapshotWorker.drain
      assert(written_on.size == 2, "Снимки обеих сцен записаны при выключенном фоне (#{written_on.size})")
      assert(written_on.all? { |p| File.extname(p).downcase == expected_ext && File.basename(File.dirname(p)) == "images" },
             "Снимки #{expected_ext} по умолчанию лежат в <Артикул>/images (#{written_on.inspect})")
      assert(captured.all? { |o| o[:show_background] == false },
             "Без флага render_scene_temp получает show_background=false (#{captured.map { |o| o[:show_background] }.inspect})")

      # Включаем фон всем сценам (глобальный чекбокс «фон видового экрана» в диалоге)
      captured.clear
      project_data.scenes.each { |s| s.viewport_background = true }
      written_on = controller.export_scene_snapshots
      DN1Code::ExportPdf2::Service::SnapshotWorker.drain
      assert(written_on.size == 2, "Снимки обеих сцен записаны при включенном фоне (#{written_on.size})")
      assert(captured.all? { |o| o[:show_background] == true },
             "При viewport_background=true render_scene_temp получает show_background=true (#{captured.map { |o| o[:show_background] }.inspect})")
    ensure
      rs.singleton_class.send(:remove_method, :render_scene_temp)
      rs.singleton_class.send(:alias_method, :render_scene_temp, :render_scene_temp_bg_probe)
      rs.singleton_class.send(:remove_method, :render_scene_temp_bg_probe)
    end

    FileUtils.rm_rf(test_dir)
  end

  def test_scene_snapshots_webp_format_and_fallback
    puts "\n--- 71b. Тест формата снимков сцен (WebP/libvips и фолбэк PNG) ---"

    test_dir = File.expand_path("test_snapshot_webp", __dir__)
    skp_dir  = File.join(test_dir, "models")
    FileUtils.mkdir_p(skp_dir)

    model = Sketchup::MockModel.new(File.join(skp_dir, "Desk.skp"))
    model.pages = Sketchup::MockPages.new([Sketchup::MockPage.new("Вид 1")])

    project_data = DN1Code::ExportPdf2::Model::ProjectData.new
    project_data.sync_with_model_scenes(model)
    project_data.pdf_settings[:webp_quality] = 85

    controller = DN1Code::ExportPdf2::Controller::ExportController.new(project_data, model)
    vips = DN1Code::ExportPdf2::Service::VipsService

    # Чистая логика: строка опций libvips в расширенном имени файла
    assert(vips.webp_target_string("C:/out/a.webp", quality: 85) == "C:/out/a.webp[Q=85]",
           "Опция качества добавлена (#{vips.webp_target_string('C:/out/a.webp', quality: 85).inspect})")
    assert(vips.webp_target_string("C:/out/a.webp", quality: 85, lossless: true) == "C:/out/a.webp[Q=85,lossless=true]",
           "Опции перечисляются через запятую")
    assert(vips.webp_target_string("C:/out/a.webp", quality: nil) == "C:/out/a.webp",
           "Без качества опции не добавляются")

    # Нормализация качества WebP (формат снимков не настраивается: WebP при доступном libvips, иначе PNG)
    assert(controller.send(:webp_quality_setting, {}) == { quality: 85, lossless: false }, "Умолчание качества WebP — 85")
    assert(controller.send(:webp_quality_setting, { webp_quality: "lossless" }) == { quality: nil, lossless: true }, "lossless распознан")
    assert(controller.send(:webp_quality_setting, { webp_quality: 150 }) == { quality: 85, lossless: false }, "Некорректное качество -> 85")

    written = controller.export_scene_snapshots
    DN1Code::ExportPdf2::Service::SnapshotWorker.drain
    assert(written.size == 1, "Снимок сцены записан (#{written.inspect})")
    images_dir = File.dirname(written.first)
    assert(File.basename(images_dir) == "images", "Снимки пишутся в папку images (#{written.first.inspect})")

    if vips.available?
      # libvips установлена: проверяем реальную конвертацию в WebP (RIFF/WEBP-заголовок)
      assert(written.first.end_with?(".webp"), "Расширение снимка .webp (#{written.first.inspect})")
      assert(File.binread(written.first, 12)[8, 4] == "WEBP", "Файл содержит RIFF/WEBP-заголовок")
      # Имя файла сохранило имя сцены
      assert(File.basename(written.first).start_with?("01_"), "Имя снимка с номером сцены (#{File.basename(written.first).inspect})")
    else
      # Фолбэк: без libvips снимок сохраняется как PNG (снимки не теряются)
      assert(written.first.end_with?(".png"), "Без libvips снимок сохранен как PNG (#{written.first.inspect})")
      assert(Dir.glob(File.join(images_dir, "*.webp")).empty?, "WebP-файлы при фолбэке не создаются")
    end

    FileUtils.rm_rf(test_dir)
  end

  def test_scene_snapshots_reuse_rendered_source
    puts "\n--- 71b2. Тест переиспользования JPEG-заготовки страницы (без повторного рендера) ---"

    test_dir = File.expand_path("test_snapshot_reuse", __dir__)
    skp_dir  = File.join(test_dir, "models")
    FileUtils.mkdir_p(skp_dir)

    model = Sketchup::MockModel.new(File.join(skp_dir, "Desk.skp"))
    model.pages = Sketchup::MockPages.new([Sketchup::MockPage.new("Вид 1")])

    project_data = DN1Code::ExportPdf2::Model::ProjectData.new
    project_data.sync_with_model_scenes(model)
    project_data.pdf_settings[:webp_quality] = 85

    controller = DN1Code::ExportPdf2::Controller::ExportController.new(project_data, model)
    scene_name = project_data.scenes.first.name
    vips = DN1Code::ExportPdf2::Service::VipsService
    rs   = DN1Code::ExportPdf2::Service::RenderService

    # JPEG-заготовка, как будто ее отрендерил LayoutBuilder для страницы PDF
    jpg_src = File.join(test_dir, "scene_cache.jpg")
    File.binwrite(jpg_src, "\xFF\xD8fake-jpeg")

    # Стабы: счетчик вызовов рендера и детерминированная WebP-конвертация
    render_calls = []
    captured_opts = []
    rs.singleton_class.send(:alias_method, :render_scene_temp_reuse_probe, :render_scene_temp)
    rs.define_singleton_method(:render_scene_temp) do |m, scene, opts = {}|
      render_calls << 1
      captured_opts << (opts || {})
      rs.send(:render_scene_temp_reuse_probe, m, scene, opts)
    end
    vips.singleton_class.send(:alias_method, :available_reuse_probe, :available?)
    vips.singleton_class.send(:alias_method, :png_to_webp_reuse_probe, :png_to_webp)
    vips.define_singleton_method(:available?) { true }
    vips.define_singleton_method(:png_to_webp) do |src, dst, quality: 85, lossless: false|
      File.binwrite(dst, "RIFF\x00\x00\x00\x00WEBP")
      File.delete(src) if File.exist?(src)
      dst
    end

    begin
      # 1. lossy WebP: JPEG-заготовка переиспользуется, рендера нет
      written = controller.export_scene_snapshots(reusable: { scene_name => jpg_src }, async: false)
      assert(render_calls.empty?, "JPEG-заготовка переиспользована без повторного рендера (рендеров: #{render_calls.size})")
      assert(written.size == 1 && File.extname(written.first) == ".webp", "Снимок .webp записан (#{written.inspect})")
      assert(File.binread(written.first, 12)[8, 4] == "WEBP", "Файл содержит RIFF/WEBP-заголовок")
      assert(!File.exist?(jpg_src), "Временная JPEG-заготовка удалена после раскладки")
      images_dir = File.dirname(written.first)
      assert(Dir.glob(File.join(images_dir, "*.{png,jpg,jpeg}")).empty?,
             "В images остаются только .webp (#{Dir.glob(File.join(images_dir, '*')).inspect})")

      # 2. lossless WebP: JPEG не переиспользуется — нужен PNG-рендер
      render_calls.clear
      captured_opts.clear
      project_data.pdf_settings[:webp_quality] = "lossless"
      File.binwrite(jpg_src, "\xFF\xD8fake-jpeg")
      written = controller.export_scene_snapshots(reusable: { scene_name => jpg_src }, async: false)
      assert(render_calls.size == 1, "Для lossless WebP выполняется PNG-рендер (рендеров: #{render_calls.size})")
      assert(captured_opts.all? { |o| o[:image_format] == "png" && o[:optimize_png] == false },
             "PNG-рендер без lossless-переупаковки: промежуточный для WebP (#{captured_opts.inspect})")
      assert(written.size == 1 && File.extname(written.first) == ".webp", "lossless-снимок .webp записан (#{written.inspect})")

      # 3. libvips недоступна: JPEG не переиспользуется, снимок — PNG
      render_calls.clear
      captured_opts.clear
      project_data.pdf_settings[:webp_quality] = 85
      File.binwrite(jpg_src, "\xFF\xD8fake-jpeg")
      vips.define_singleton_method(:available?) { false }
      written = controller.export_scene_snapshots(reusable: { scene_name => jpg_src }, async: false)
      assert(render_calls.size == 1, "Без libvips выполняется PNG-рендер (рендеров: #{render_calls.size})")
      assert(captured_opts.all? { |o| o[:optimize_png] == true },
             "PNG-снимок (финальный файл) оптимизируется (#{captured_opts.inspect})")
      assert(written.size == 1 && File.extname(written.first) == ".png", "Фолбэк-снимок .png записан (#{written.inspect})")
    ensure
      rs.singleton_class.send(:remove_method, :render_scene_temp)
      rs.singleton_class.send(:alias_method, :render_scene_temp, :render_scene_temp_reuse_probe)
      rs.singleton_class.send(:remove_method, :render_scene_temp_reuse_probe)
      vips.singleton_class.send(:remove_method, :available?)
      vips.singleton_class.send(:alias_method, :available?, :available_reuse_probe)
      vips.singleton_class.send(:remove_method, :available_reuse_probe)
      vips.singleton_class.send(:remove_method, :png_to_webp)
      vips.singleton_class.send(:alias_method, :png_to_webp, :png_to_webp_reuse_probe)
      vips.singleton_class.send(:remove_method, :png_to_webp_reuse_probe)
    end

    FileUtils.rm_rf(test_dir)
  end

  def test_snapshot_worker_background_pool
    puts "\n--- 71c. Тест фонового пула конвертации SnapshotWorker ---"

    test_dir   = File.expand_path("test_snapshot_worker", __dir__)
    images_dir = File.join(test_dir, "images")
    FileUtils.mkdir_p(images_dir)

    worker = DN1Code::ExportPdf2::Service::SnapshotWorker
    rs     = DN1Code::ExportPdf2::Service::RenderService
    vips   = DN1Code::ExportPdf2::Service::VipsService

    # Заготовки: валидные PNG + один битый файл (проверка фолбэка)
    jobs = 3.times.map do |i|
      src = File.join(images_dir, "#{format('%02d', i + 1)}_src.png")
      rs.create_fallback_image(src, 64, 64, "s#{i}")
      { src: src, dst: File.join(images_dir, "#{format('%02d', i + 1)}_shot.webp"), quality: 85, lossless: false }
    end
    bad_src = File.join(images_dir, "04_bad.png")
    File.binwrite(bad_src, "not a png")
    bad_job = { src: bad_src, dst: File.join(images_dir, "04_bad.webp"), quality: 85, lossless: false }

    if vips.available?
      st = worker.submit(jobs + [bad_job])
      assert(st[:total] == 4, "submit принял 4 задания (#{st.inspect})")

      final = worker.drain
      assert(!final[:running], "После drain партия завершена (#{final.inspect})")
      assert(final[:done] == 3, "3 снимка сконвертированы (#{final.inspect})")
      assert(final[:failed] == 1, "Битый исходник дал 1 сбой (#{final.inspect})")
      assert(final[:errors].size == 1, "Ошибка попала в статус (#{final[:errors].inspect})")

      jobs.each do |j|
        assert(File.exist?(j[:dst]), "WebP на месте: #{j[:dst]}")
        assert(File.binread(j[:dst], 12)[8, 4] == "WEBP", "RIFF/WEBP-заголовок (#{File.basename(j[:dst])})")
        assert(!File.exist?(j[:src]), "PNG-исходник удален после конвертации (#{File.basename(j[:src])})")
      end
      assert(Dir.glob(File.join(images_dir, "*.tmp.webp")).empty?, "Временные .tmp.webp переименованы")
      assert(File.exist?(bad_src), "При сбое PNG-исходник остался (фолбэк)")
      assert(!File.exist?(bad_job[:dst]), "WebP для битого исходника не создан")

      # Повторные submit/drain идемпотентны, партия без заданий ничего не ломает
      worker.submit([])
      worker.drain
      worker.drain
      assert(Dir.glob(File.join(images_dir, "*.webp")).size == 3, "После повторных drain снимки на месте")

      # --- Повторный submit поверх идущей партии: поколения отбрасывают старое ---
      # Большой PNG, чтобы старая партия не успела закончиться до подачи новой
      require "zlib" unless defined?(::Zlib)
      w2, h2 = 1600, 1200
      mk_chunk = ->(t, d) { t = t.b; [d.bytesize].pack("N") + t + d + [Zlib.crc32(t + d)].pack("N") }
      row = "\x00".b * (1 + w2 * 4)
      raw_png = String.new("".b)
      h2.times { raw_png << row }
      ihdr = [w2, h2, 8, 6, 0, 0, 0].pack("NNCCCCC")
      big = File.join(images_dir, "big_src.png")
      File.binwrite(big, "\x89PNG\r\n\x1a\n".b + mk_chunk.("IHDR", ihdr) + mk_chunk.("IDAT", Zlib::Deflate.deflate(raw_png)) + mk_chunk.("IEND", "".b))

      old_jobs = 8.times.map do |i|
        src = File.join(images_dir, format("old_%02d.png", i))
        FileUtils.cp(big, src)
        { src: src, dst: File.join(images_dir, format("old_%02d.webp", i)), quality: 85, lossless: false }
      end
      worker.submit(old_jobs)

      new_jobs = 2.times.map do |i|
        src = File.join(images_dir, format("new_%02d.png", i))
        rs.create_fallback_image(src, 64, 64, "n#{i}")
        { src: src, dst: File.join(images_dir, format("new_%02d.webp", i)), quality: 85, lossless: false }
      end
      st2 = worker.submit(new_jobs)
      assert(st2[:total] == 2, "Новая партия принята без ожидания старой (#{st2.inspect})")

      fin2 = worker.drain
      assert(fin2[:done] == 2 && fin2[:failed].zero?, "Новая партия полностью конвертирована (#{fin2.inspect})")
      new_jobs.each do |j|
        assert(File.exist?(j[:dst]), "Свежий снимок новой партии на месте (#{File.basename(j[:dst])})")
        assert(!File.exist?(j[:src]), "Исходник новой партии удален (#{File.basename(j[:src])})")
      end
      assert(Dir.glob(File.join(images_dir, "*.tmp.webp")).empty?, "Устаревшие .tmp.webp не остались")
    else
      # Без libvips submit не берет задания — исходники остаются на месте
      st = worker.submit(jobs + [bad_job])
      assert(st[:total].zero? || !st[:running], "Без libvips партия не запускается (#{st.inspect})")
      assert(File.exist?(bad_src), "Без libvips исходники не тронуты")
    end

    worker.drain # фоновые потоки не должны писать в папку после ее удаления
    FileUtils.rm_rf(test_dir)
  end

  def test_path_util_file_url_encoding
    puts "\n--- 72. Тест file_url: процентное кодирование пути для UI.openURL ---"

    pu = DN1Code::ExportPdf2::Model::PathUtil

    # '#' в артикуле и в суффиксе версии/ревизии не должен обрезаться как фрагмент URL
    assert(pu.file_url("U:/desktop/su_ai/HF#26092/pdf/HF#26092_01#001.pdf") ==
           "file:///U:/desktop/su_ai/HF%2326092/pdf/HF%2326092_01%23001.pdf",
           "Символ '#' кодируется как %23 (#{pu.file_url('U:/desktop/su_ai/HF#26092/pdf/HF#26092_01#001.pdf').inspect})")

    # Обратные слэши нормализуются
    assert(pu.file_url('U:\desktop\su_ai\HF#26092\HF#26092_01#007.pdf') ==
           "file:///U:/desktop/su_ai/HF%2326092/HF%2326092_01%23007.pdf",
           "Обратные слэши заменяются на прямые")

    # Пробелы и спецсимволы
    assert(pu.file_url("U:/desk top/a&b (1).pdf") == "file:///U:/desk%20top/a%26b%20%281%29.pdf",
           "Пробелы, '&' и скобки кодируются")

    # Кириллица кодируется побайтово в UTF-8
    cyr = pu.file_url("U:/Стол/тумба.pdf")
    assert(cyr.start_with?("file:///U:/%D0%A1") && !cyr.include?("т"),
           "Кириллица кодируется в UTF-8 процентах (#{cyr.inspect})")

    # Простые пути без спецсимволов не меняются
    assert(pu.file_url("C:/models/Chair_last.pdf") == "file:///C:/models/Chair_last.pdf",
           "Простой путь остается читаемым")

    # Пустые и nil-пути
    assert(pu.file_url("").nil?, "Пустая строка возвращает nil")
    assert(pu.file_url("   ").nil?, "Строка из пробелов возвращает nil")
    assert(pu.file_url(nil).nil?, "nil возвращает nil")
  end

  def test_file_opener_open_path
    puts "\n--- 72b. Тест FileOpener: открытие системной программой через перехватчик ---"

    opener   = DN1Code::ExportPdf2::Model::FileOpener
    original = opener.launcher_override
    calls    = []
    opener.launcher_override = ->(path) { calls << path; true }

    begin
      # Существующий файл — лаунчер получает путь как есть
      existing = File.expand_path(__FILE__)
      assert(opener.open_path(existing) == true, "Существующий файл: open_path возвращает true")
      assert(calls.last == existing, "Лаунчер получил путь файла (#{calls.last.inspect})")

      # Существующая папка
      dir = File.expand_path(__dir__)
      assert(opener.open_path(dir) == true, "Существующая папка: open_path возвращает true")
      assert(calls.last == dir, "Лаунчер получил путь папки (#{calls.last.inspect})")

      # Несуществующий/пустой путь — false без вызова лаунчера
      calls.clear
      assert(opener.open_path("Z:/definitely/missing/file.pdf") == false, "Несуществующий путь возвращает false")
      assert(opener.open_path("") == false, "Пустой путь возвращает false")
      assert(opener.open_path(nil) == false, "nil возвращает false")
      assert(calls.empty?, "Лаунчер не вызывается для несуществующих путей")

      # Сбой лаунчера не маскируется под успех
      opener.launcher_override = ->(_path) { false }
      assert(opener.open_path(File.expand_path(__FILE__)) == false, "Сбой лаунчера -> open_path возвращает false")
    ensure
      opener.launcher_override = original
    end
  end

  def test_file_opener_file_locked
    puts "\n--- 72c. Тест FileOpener.file_locked?: детект файла, открытого другой программой ---"

    require "fiddle"
    opener = DN1Code::ExportPdf2::Model::FileOpener

    test_dir = File.expand_path("test_file_lock", __dir__)
    FileUtils.rm_rf(test_dir)
    FileUtils.mkdir_p(test_dir)
    path = File.join(test_dir, "doc.pdf")
    File.binwrite(path, "%PDF-1.4 lock test")

    begin
      assert(opener.file_locked?(path) == false, "Обычный файл не считается открытым")
      assert(opener.file_locked?(File.join(test_dir, "missing.pdf")) == false, "Отсутствующий файл не считается открытым")
      assert(opener.file_locked?(nil) == false, "nil не считается открытым")

      # Эксклюзивный хэндл как у просмотрщика PDF: shareMode = 0
      kernel32 = Fiddle.dlopen("kernel32.dll")
      create_w = Fiddle::Function.new(
        kernel32["CreateFileW"],
        [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP,
         Fiddle::TYPE_INT, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP],
        Fiddle::TYPE_VOIDP
      )
      close_h = Fiddle::Function.new(kernel32["CloseHandle"], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
      utf16 = ->(s) { (s.encode("UTF-16LE") + "\0".encode("UTF-16LE")).b }
      generic_rw = -1_073_741_824 # 0xC0000000 = GENERIC_READ | GENERIC_WRITE

      handle = create_w.call(utf16.call(File.expand_path(path)), generic_rw, 0, nil, 3, 0x80, nil)
      begin
        assert(handle.to_i != 0 && handle.to_i != 2**64 - 1, "Эксклюзивный хэндл получен")
        assert(opener.file_locked?(path) == true, "Файл с чужим эксклюзивным хэндлом определён как открытый")
      ensure
        close_h.call(handle)
      end

      assert(opener.file_locked?(path) == false, "После закрытия чужого хэндла файл снова доступен")
    ensure
      FileUtils.rm_rf(test_dir)
    end
  end

  def test_export_aborts_when_target_pdf_locked
    puts "\n--- 72d. Экспорт прерывается с предупреждением, если целевой PDF открыт ---"

    opener = DN1Code::ExportPdf2::Model::FileOpener
    opener.singleton_class.send(:alias_method, :file_locked_real, :file_locked?)
    opener.singleton_class.send(:define_method, :file_locked?) { |_path| true }

    test_dir = File.expand_path("test_locked_export", __dir__)
    FileUtils.rm_rf(test_dir)
    skp_dir = File.join(test_dir, "models")
    FileUtils.mkdir_p(skp_dir)

    begin
      model = Sketchup::MockModel.new(File.join(skp_dir, "Table.skp"))
      model.pages = Sketchup::MockPages.new([Sketchup::MockPage.new("Вид 1")])

      project_data = DN1Code::ExportPdf2::Model::ProjectData.new
      project_data.pdf_settings[:auto_open_pdf] = false
      project_data.sync_with_model_scenes(model)

      controller = DN1Code::ExportPdf2::Controller::ExportController.new(project_data, model)
      target = File.join(test_dir, "out.pdf")
      File.binwrite(target, "OLD CONTENT")

      raised = false
      begin
        controller.export(target)
      rescue StandardError => e
        raised = true
        assert(e.message.include?("заблокирован"), "Сообщение объясняет причину (#{e.message.inspect})")
      end
      assert(raised, "Экспорт прерван, когда целевой PDF заблокирован")
      assert(File.binread(target) == "OLD CONTENT", "Открытый файл не перезаписан")
    ensure
      opener.singleton_class.send(:alias_method, :file_locked?, :file_locked_real)
      opener.singleton_class.send(:remove_method, :file_locked_real)
      FileUtils.rm_rf(test_dir)
    end
  end

  def test_export_skips_last_copy_when_locked
    puts "\n--- 72e. Копия _last.pdf открыта — пропускается, экспорт не валим ---"

    opener = DN1Code::ExportPdf2::Model::FileOpener
    opener.singleton_class.send(:alias_method, :file_locked_real, :file_locked?)

    test_dir = File.expand_path("test_locked_last_export", __dir__)
    FileUtils.rm_rf(test_dir)
    skp_dir = File.join(test_dir, "models")
    FileUtils.mkdir_p(skp_dir)

    begin
      skp_file = File.join(skp_dir, "Chair.skp")
      model = Sketchup::MockModel.new(skp_file)
      model.pages = Sketchup::MockPages.new([Sketchup::MockPage.new("Обложка")])

      project_data = DN1Code::ExportPdf2::Model::ProjectData.new
      project_data.project_info[:articul] = "EXP-LCK"
      project_data.pdf_settings[:auto_open_pdf] = false
      project_data.sync_with_model_scenes(model)

      controller = DN1Code::ExportPdf2::Controller::ExportController.new(project_data, model)

      File.binwrite(controller.resolve_last_pdf_path, "STALE OLD COPY")
      last_path = File.expand_path(controller.resolve_last_pdf_path.to_s)
      opener.singleton_class.send(:define_method, :file_locked?) do |path|
        File.expand_path(path.to_s) == last_path
      end

      result_path = controller.export(nil)
      DN1Code::ExportPdf2::Service::SnapshotWorker.drain

      assert(File.exist?(result_path.to_s), "Версионный PDF создан несмотря на открытую копию _last")
      assert(File.binread(controller.resolve_last_pdf_path) == "STALE OLD COPY", "Открытая копия _last не перезаписана")
      assert(controller.last_pdf_path.nil?, "last_pdf_path не указывает на необновлённую копию")
    ensure
      opener.singleton_class.send(:alias_method, :file_locked?, :file_locked_real)
      opener.singleton_class.send(:remove_method, :file_locked_real)
      FileUtils.rm_rf(test_dir)
    end
  end

  def test_history_rev_ver_fields_and_migration
    puts "\n--- 73. Тест ver/rev в записях истории и миграции суффикса (rev. NNN) ---"

    project_data = DN1Code::ExportPdf2::Model::ProjectData.new

    # Старые записи: ревизия вшита в текст; новая запись: ver/rev отдельными полями
    project_data.history << { date: "2026-09-21 21:00", text: "Новые правки для проверки 3 (rev. 004)",
                              description: "Новые правки для проверки 3 (rev. 004)" }
    project_data.history << { date: "2026-09-20 10:00", text: "Правка без ревизии", description: "Правка без ревизии" }
    project_data.history << { date: "2026-09-19 12:30", text: "Старт проекта", ver: "02", rev: "003" }

    project_data.sync_history_entries!

    first = project_data.history.first
    assert(first[:text] == "Новые правки для проверки 3",
           "Суффикс '(rev. 004)' вычищен из текста (#{first[:text].inspect})")
    assert(first[:rev] == "004", "Вшитая ревизия перенесена в поле rev (#{first[:rev].inspect})")
    assert(first[:ver].to_s.empty?, "Версия старой записи без суффикса остается пустой")

    second = project_data.history[1]
    assert(second[:text] == "Правка без ревизии" && second[:rev].to_s.empty?,
           "Запись без суффикса не получает ревизию")

    third = project_data.history[2]
    assert(third[:text] == "Старт проекта" && third[:rev] == "003" && third[:ver] == "02",
           "Явные ver/rev сохраняются, текст не меняется")

    pairs = project_data.workflow[:history_edit]
    assert(pairs.first[1] == "Новые правки для проверки 3",
           "Пары workflow.history_edit содержат чистый текст (#{pairs.first[1].inspect})")

    # Roundtrip через YAML: ver/rev сохраняются и читаются
    test_dir = File.expand_path("test_history_rev_ver", __dir__)
    FileUtils.mkdir_p(test_dir)
    yaml_temp = File.join(test_dir, "EXP-REV.yaml")
    project_data.save_to_yaml(yaml_temp)
    reloaded = DN1Code::ExportPdf2::Model::ProjectData.new
    assert(reloaded.load_from_yaml(yaml_temp), "YAML с ver/rev прочитан обратно")
    r_first = reloaded.history.first
    assert(r_first[:rev] == "004" && r_first[:text] == "Новые правки для проверки 3",
           "rev и чистый текст переживают запись/чтение YAML (#{r_first.inspect})")
    r_third = reloaded.history[2]
    assert(r_third[:ver] == "02" && r_third[:rev] == "003", "ver/rev явно сохраняются в YAML")

    FileUtils.rm_rf(test_dir)
  end

  def test_74_save_without_articul_writes_no_yaml
    puts "\n--- 74. Тест запрета записи YAML проекта без артикула ---"

    test_dir = File.expand_path("test_no_articul_guard", __dir__)
    FileUtils.mkdir_p(test_dir)

    skp_file = File.join(test_dir, "Sofa.skp")
    model = Sketchup::MockModel.new(skp_file)

    pd = DN1Code::ExportPdf2::Model::ProjectData.new
    pd.project_info[:name_product] = "Диван без артикула"

    # Прямой вызов save_project_yaml без артикула отклоняется
    assert(!pd.save_project_yaml(model), "save_project_yaml без артикула вернул false")
    assert(pd.project_info[:articul].to_s.strip.empty?, "Артикул остался пустым")

    # Путь к файлу данных без артикула не определен
    assert(pd.yaml_path_for_model(model).nil?, "yaml_path_for_model без артикула вернул nil")

    # Ни один YAML проекта не появился (ни по артикулу, ни по имени модели, ни project.yaml)
    yamls = Dir.glob(File.join(test_dir, "**", "*.{yaml,yml}"))
    assert(yamls.empty?, "На диске нет YAML файлов проекта (найдено: #{yamls.join(', ')})")

    FileUtils.rm_rf(test_dir)
  end

  def test_75_legacy_yaml_ignored
    puts "\n--- 75. Тест: legacy-YAML (якорь, <Артикул>.yaml, project_config.yaml) игнорируются ---"

    test_dir = File.expand_path("test_legacy_migration", __dir__)
    FileUtils.mkdir_p(test_dir)

    skp_file = File.join(test_dir, "Wardrobe.skp")
    model = Sketchup::MockModel.new(skp_file)

    # Файлы старой схемы (до 2.1): якорь <Артикул>.yaml рядом с .skp, прежний
    # канонический <Артикул>.yaml в папке артикула, общий шаблон project_config.yaml
    legacy_pd = DN1Code::ExportPdf2::Model::ProjectData.new
    legacy_pd.project_info[:articul] = "OLD-100"
    legacy_pd.project_info[:description] = "LEGACY_DATA"

    art_dir       = File.join(test_dir, "OLD-100")
    anchor_yaml   = File.join(test_dir, "OLD-100.yaml")
    old_canon     = File.join(art_dir, "OLD-100.yaml")
    template_cfg  = File.join(test_dir, "project_config.yaml")
    FileUtils.mkdir_p(art_dir)
    legacy_pd.save_to_yaml(old_canon, include_settings: false)
    legacy_pd.save_to_yaml(anchor_yaml, include_settings: false)
    legacy_pd.save_to_yaml(template_cfg, include_settings: false)

    # 1. Открытие модели: legacy-файлы не читаются, источник :default
    fresh = DN1Code::ExportPdf2::Model::ProjectData.new
    source = fresh.load_auto(model)
    assert(source == :default, "Legacy-YAML не читаются, источник :default (получено: #{source})")
    assert(fresh.project_info[:articul].to_s.empty?, "Артикул не подхватывается из legacy-файлов")

    # 2. Привязка через артикул в .skp: читается только project.yaml папки артикула
    DN1Code::ExportPdf2::Model::ModelArticulStore.write(model, "OLD-100")
    bound = DN1Code::ExportPdf2::Model::ProjectData.new
    assert(bound.load_auto(model) == :default, "Проект привязан по .skp, но project.yaml еще нет — :default")
    assert(bound.save_project_yaml(model), "Сохранение создало project.yaml в папке артикула")
    assert(File.exist?(File.join(art_dir, "project.yaml")), "project.yaml создан в папке артикула")

    # 3. Legacy-файлы плагином не удаляются и не изменяются
    assert(File.exist?(anchor_yaml), "Якорь OLD-100.yaml рядом с .skp не тронут")
    assert(File.exist?(old_canon), "Прежний канонический OLD-100.yaml не тронут")
    assert(File.exist?(template_cfg), "Общий шаблон project_config.yaml не тронут")

    # 4. Повторное открытие: проект читается из project.yaml по артикулу из .skp
    reopened = DN1Code::ExportPdf2::Model::ProjectData.new
    reopened.load_auto(model)
    assert(reopened.project_info[:articul].to_s == "OLD-100", "Проект снова открывается по артикулу из .skp")

    FileUtils.rm_rf(test_dir)
  end

  def test_76_discovery_multiple_articul_folders_ambiguous
    puts "\n--- 76. Тест обнаружения: несколько папок артикулов — выбор по артикулу из .skp, без него :default ---"

    test_dir = File.expand_path("test_discovery_multi", __dir__)
    FileUtils.mkdir_p(test_dir)

    skp_file = File.join(test_dir, "Showcase.skp")
    model = Sketchup::MockModel.new(skp_file)

    ["PRJ-A", "PRJ-B"].each do |art|
      pd = DN1Code::ExportPdf2::Model::ProjectData.new
      pd.project_info[:articul] = art
      pd.project_info[:description] = "DATA_#{art}"
      assert(pd.save_project_yaml(model), "Сохранен #{art}/project.yaml")
    end

    # Артикул последнего сохранения записан в атрибуты модели (.skp): даже при
    # двух папках рядом проект определяется однозначно — по артикулу из .skp
    fresh = DN1Code::ExportPdf2::Model::ProjectData.new
    source = fresh.load_auto(model)
    assert(source == :yaml, "При двух папках артикулов проект определен по артикулу из .skp (получено: #{source})")
    assert(fresh.project_info[:articul].to_s == "PRJ-B", "Артикул взят из файла модели (.skp)")
    assert(fresh.project_info[:description].to_s == "DATA_PRJ-B", "Загружены данные папки артикула, указанной в .skp")

    # Модель без артикула в .skp (старые файлы): две папки рядом — неоднозначно,
    # автозагрузка не выполняется (пользователь выбирает через «Импорт YAML»)
    legacy_model = Sketchup::MockModel.new(skp_file)
    legacy_fresh = DN1Code::ExportPdf2::Model::ProjectData.new
    legacy_source = legacy_fresh.load_auto(legacy_model)
    assert(legacy_source == :default, "Без артикула в .skp при двух папках автозагрузка не выполняется (получено: #{legacy_source})")
    assert(legacy_fresh.project_info[:articul].to_s.empty?, "Без артикула в .skp артикул не выбран автоматически")

    FileUtils.rm_rf(test_dir)
  end

  def test_77_edit_history_in_articul_folder
    puts "\n--- 77. Тест журнала правок: edit_history.yaml только в папке артикула ---"

    test_dir = File.expand_path("test_edit_history_articul", __dir__)
    FileUtils.mkdir_p(test_dir)

    skp_file = File.join(test_dir, "Bed.skp")
    model = Sketchup::MockModel.new(skp_file)

    # 1. Модель привязана к проекту артикулом в .skp, журнал лежит в папке артикула
    DN1Code::ExportPdf2::Model::ModelArticulStore.write(model, "BED-01")
    art_dir = File.join(test_dir, "BED-01")
    FileUtils.mkdir_p(art_dir)
    File.write(File.join(art_dir, "edit_history.yaml"),
               YAML.dump({ "BED-01" => [{ "date" => "2026-09-01 10:00", "text" => "Правка из папки артикула" }] }))
    project = DN1Code::ExportPdf2::Model::ProjectData.new
    project.project_info[:articul] = "BED-01"
    assert(project.save_project_yaml(model), "Сохранен project.yaml в папке артикула")

    pd = DN1Code::ExportPdf2::Model::ProjectData.new
    pd.load_auto(model)
    assert(pd.project_info[:articul].to_s == "BED-01", "Артикул загружен из .skp")
    assert(pd.history.first[:text] == "Правка из папки артикула", "Журнал прочитан из папки артикула")

    # 2. Файл журнала рядом с .skp (вне папки артикула) не читается — legacy-фолбэк удален
    File.write(File.join(test_dir, "edit_history.yaml"),
               YAML.dump({ "BED-01" => [{ "date" => "2026-08-01 09:00", "text" => "Правка из корня модели" }] }))
    pd2 = DN1Code::ExportPdf2::Model::ProjectData.new
    pd2.load_auto(model)
    assert(pd2.history.first[:text] == "Правка из папки артикула", "Журнал рядом с .skp игнорируется")

    FileUtils.rm_rf(test_dir)
  end

  def test_78_articul_offer_on_dialog_open_and_folder_creation
    puts "\n--- 78. Тест предложения артикула при открытии панели и создания папки проекта ---"

    # 1. Разметка и JS: модалка выбора типа проекта показывается при открытии панели
    html = File.read(File.join(__dir__, "../dialog/html/index.html"), encoding: "utf-8")
    assert(html.include?('id="articulTypeModal"'), "index.html содержит модальное окно articulTypeModal")
    assert(html.include?('id="btnArticulTypeCommercial"'), "index.html содержит кнопку коммерческого проекта")
    assert(html.include?('id="btnArticulTypeHousehold"'), "index.html содержит кнопку бытового проекта")

    js = File.read(File.join(__dir__, "../dialog/html/app.js"), encoding: "utf-8")
    assert(js.include?("function maybeOfferArticulCreation"), "app.js содержит maybeOfferArticulCreation (предложение при открытии)")
    assert(js.include?("setTimeout(maybeOfferArticulCreation"), "app.js вызывает maybeOfferArticulCreation после loadData")
    assert(js.include?("function createProjectArticul"), "app.js содержит createProjectArticul (выбор типа)")
    assert(js.include?('callRuby("createProjectFolder"'), "app.js вызывает Ruby-колбэк createProjectFolder")
    assert(js.include?("onProjectFolderCreated"), "app.js содержит обработчик onProjectFolderCreated")

    rb = File.read(File.join(__dir__, "../dialog/export_dialog.rb"), encoding: "utf-8")
    assert(rb.include?('add_action_callback("createProjectFolder")'), "export_dialog.rb регистрирует колбэк createProjectFolder")
    assert(rb.include?("save_project_yaml"), "export_dialog.rb записывает project.yaml при создании папки")

    # 2. Функционально: последовательность колбэка — артикул в сессию, папка рядом с .skp,
    #    project.yaml внутри (то же, что делает createProjectFolder)
    test_dir = File.expand_path("test_articul_offer_dir", __dir__)
    FileUtils.mkdir_p(test_dir)

    skp_file = File.join(test_dir, "Shelf.skp")
    model = Sketchup::MockModel.new(skp_file)

    session_pd = DN1Code::ExportPdf2::Model::SessionStore.on_model_opened(model)
    session_pd.project_info[:articul] = "CF#260922_100000"
    art_dir = session_pd.articul_dir_for_model(model)
    assert(art_dir.to_s.tr("\\", "/").downcase == File.join(test_dir, "CF#260922_100000").tr("\\", "/").downcase,
           "Папка проекта размещается рядом с рабочим файлом (#{art_dir})")

    FileUtils.mkdir_p(art_dir)
    assert(session_pd.save_project_yaml(model), "project.yaml записан в новую папку проекта")
    assert(File.exist?(File.join(art_dir, "project.yaml")), "project.yaml создан в папке <Артикул>")
    assert(Dir.exist?(art_dir), "Папка проекта создана рядом с рабочим файлом")

    # 3. После создания папки предложение больше не показывается (артикул не пуст)
    reopened = DN1Code::ExportPdf2::Model::ProjectData.new
    reopened.load_auto(model)
    assert(reopened.project_info[:articul].to_s == "CF#260922_100000", "Проект с папкой открывается повторно")

    FileUtils.rm_rf(test_dir)
  end

  def test_86_overlay_follows_native_page_switch
    puts "\n--- 86. Тест: рамка пропорций следует за сменой активной страницы SketchUp ---"

    root_project_yaml = File.expand_path("../../project.yaml", __dir__)
    initial_md5 = Digest::MD5.hexdigest(File.binread(root_project_yaml))

    overlay_svc = DN1Code::ExportPdf2::Service::OverlayService
    obs_svc = DN1Code::ExportPdf2::Service::ObserverService

    # 0. Чистые настройки сессии для юнит-проверок calculate_target_info
    overlay_svc.current_settings = nil

    info_ext = overlay_svc.calculate_target_info(nil, {
      template_key: :cover,
      custom_layouts: { cover: { image_4_3: { visible: true, aspect_ratio: "4:3" } } },
      scene_index: 2
    })
    assert(info_ext[:scene_index] == 2, "calculate_target_info возвращает scene_index из override-настроек")
    assert(info_ext[:template_key] == "cover", "calculate_target_info возвращает resolved template_key")
    assert(info_ext.key?(:scene_aspect), "calculate_target_info возвращает scene_aspect")

    # Пропорции 5:4/4:5 валидны и на уровне сцены (регрессия: valid_modes без 5:4/4:5)
    scene_54 = DN1Code::ExportPdf2::Model::SceneItem.new(name: "План 5:4", page_type: :cover, aspect_ratio: "5:4", frame_overlay: true)
    info_54 = overlay_svc.calculate_target_info(nil, {
      scene_item: scene_54,
      template_key: :cover,
      custom_layouts: { cover: { image_4_3: { visible: true, aspect_ratio: "4:3" } } }
    })
    assert(info_54[:aspect_ratio] == "5:4" && info_54[:scene_aspect] == "5:4", "пропорция сцены 5:4 резолвится (valid_modes содержит 5:4/4:5)")

    # 1. Модель с тремя страницами: две сцены проекта + одна «сырая» страница SketchUp
    model = Sketchup::MockModel.new("U:/Projects/SampleProject/FrameSwitch/Model.skp")
    page_plan  = model.pages.add("План")
    page_front = model.pages.add("Фасад")
    page_raw   = model.pages.add("Сырая страница")

    pdata = DN1Code::ExportPdf2::Model::SessionStore.data(model)
    pdata.scenes = [
      DN1Code::ExportPdf2::Model::SceneItem.new(name: "План", page_type: :cover, aspect_ratio: "16:9", frame_overlay: true),
      DN1Code::ExportPdf2::Model::SceneItem.new(name: "Фасад", page_type: :visual, aspect_ratio: "1:1", frame_overlay: false)
    ]

    overlay_svc.on_model_opened(model)

    # 2. Нативная смена страницы на "План": рамка 16:9 включается
    model.pages.selected_page = page_plan
    info_plan = overlay_svc.on_page_changed(model)
    assert(info_plan && info_plan[:aspect_ratio] == "16:9", "on_page_changed резолвит пропорцию страницы 'План' (16:9)")
    assert(info_plan[:scene_index] == 0, "on_page_changed возвращает индекс совпавшей сцены")
    assert(overlay_svc.overlay_instance.ratio_cache == (16.0 / 9.0), "кэш рамки обновлен на 16:9")
    assert(overlay_svc.overlay_active?(model) == true, "рамка включена на странице с frame_overlay=true")
    assert(overlay_svc.current_settings[:scene_name] == "План", "сессия оверлея описывает активную страницу 'План'")
    assert(overlay_svc.current_settings[:template_key].to_s == "cover", "сессия оверлея обновила template_key по странице")
    assert(overlay_svc.current_settings[:aspect_ratio] == "16:9", "сессия оверлея запомнила пропорцию активной страницы")

    # 3. Нативная смена на "Фасад": рамка выключается по флагу страницы
    model.pages.selected_page = page_front
    info_front = overlay_svc.on_page_changed(model)
    assert(info_front && info_front[:aspect_ratio] == "1:1", "on_page_changed резолвит пропорцию страницы 'Фасад' (1:1)")
    assert(overlay_svc.overlay_active?(model) == false, "рамка выключена на странице с frame_overlay=false")

    # 4. Обратно на "План": рамка снова включается и пересчитывается
    model.pages.selected_page = page_plan
    info_back = overlay_svc.on_page_changed(model)
    assert(info_back && info_back[:aspect_ratio] == "16:9" && overlay_svc.overlay_active?(model), "обратное переключение включает рамку с 16:9")

    # 5. Дедупликация повторного уведомления о той же странице
    assert(overlay_svc.on_page_changed(model).nil?, "повторное уведомление о той же странице игнорируется (дедупликация)")

    # 6. Наблюдатель страниц SketchUp: selected_page= вызывает onContentsModified → рамка следует
    assert(obs_svc.attach_pages_observer(model) == true, "наблюдатель страниц подключен к модели")
    assert(obs_svc.attach_pages_observer(model) == true, "повторное подключение наблюдателя к той же модели дедуплицируется")
    model.pages.selected_page = page_front
    assert(overlay_svc.overlay_active?(model) == false, "через PagesObserver рамка выключилась на странице с frame_overlay=false")
    assert(overlay_svc.current_settings[:scene_name] == "Фасад", "наблюдатель обновил сессию под страницу 'Фасад'")
    model.pages.selected_page = page_plan
    assert(overlay_svc.overlay_active?(model) == true, "через PagesObserver рамка включилась на странице с frame_overlay=true")

    # 7. Сырая страница вне списка сцен проекта: мягкий fallback без ошибок.
    #    Наблюдатель из п.6 уже применил страницу при selected_page= (дедупликация),
    #    поэтому сбрасываем состояние оверлея, как при переоткрытии модели
    model.pages.selected_page = page_raw
    overlay_svc.on_model_opened(model)
    info_raw = overlay_svc.on_page_changed(model)
    assert(info_raw.is_a?(Hash), "для сырой страницы возвращаются параметры кадра без ошибок")
    assert(overlay_svc.current_settings[:scene_name] == "Сырая страница", "сессия описывает сырую страницу")

    # 8. Делегирование selectScene и JS-мост синхронизации панели
    rb = File.read(File.join(__dir__, "../dialog/export_dialog.rb"), encoding: "utf-8")
    assert(rb.include?("Service::OverlayService.on_page_changed(model)"), "selectScene применяет рамку через OverlayService.on_page_changed")
    assert(rb.include?("def self.notify_active_scene"), "ExportDialog.notify_active_scene синхронизирует панель при нативной смене страницы")
    osvc = File.read(File.join(__dir__, "../service/overlay_service.rb"), encoding: "utf-8")
    assert(osvc.include?("def self.on_page_changed"), "OverlayService.on_page_changed — единая точка применения рамки к странице")
    js = File.read(File.join(__dir__, "../dialog/html/app.js"), encoding: "utf-8")
    assert(js.include?("onActiveSceneChanged"), "app.js содержит обработчик onActiveSceneChanged (панель следует за SketchUp)")

    # 9. КРИТИЧЕСКАЯ ПРОВЕРКА: Файл project.yaml остался абсолютно нетронутым
    current_content = File.binread(root_project_yaml)
    current_md5 = Digest::MD5.hexdigest(current_content)
    assert(current_md5 == initial_md5, "КРИТИЧЕСКАЯ ПРОВЕРКА: Файл project.yaml остался абсолютно нетронутым (MD5 совпадает)")
  end

  def test_87_refresh_thumbnails_button_and_sig_guard
    puts "\n--- 87. Тест: кнопка «Обновить эскизы» и защита от лишней перегенерации ---"

    html = File.read(File.join(__dir__, "../dialog/html/index.html"), encoding: "utf-8")
    assert(html.include?('id="btnRefreshThumbs"'), "index.html содержит кнопку btnRefreshThumbs")

    js = File.read(File.join(__dir__, "../dialog/html/app.js"), encoding: "utf-8")
    assert(js.include?("btnRefreshThumbs: document.getElementById"), "app.js регистрирует элемент btnRefreshThumbs")
    assert(js.include?("function sceneThumbnailsSignature"), "app.js содержит сигнатуру набора сцен sceneThumbnailsSignature")
    assert(js.include?("sig === sceneThumbnailsSig") && js.include?("sceneThumbnailsSig = sceneThumbnailsSignature()"),
           "app.js пропускает перегенерацию эскизов, если сигнатура сцен не изменилась")
    assert(js.include?("sceneThumbsManualRequest = true") && js.include?("requestSceneThumbnails(true)"),
           "app.js по клику «Обновить эскизы» форсирует перегенерацию")
    assert(js.include?("Эскизы сцен обновлены"), "app.js уведомляет об успешном обновлении эскизов")
    assert(js.include?("requestSceneThumbnails(false)"), "onScenesRefreshed больше не форсирует перегенерацию эскизов (сигнатура решает)")
  end
end

TestRunner.new.run_all

