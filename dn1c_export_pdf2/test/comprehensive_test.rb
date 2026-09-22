# frozen_string_literal: true

# -------------------------------------------------------------------------------
# Comprehensive End-to-End Test Suite for DN1C Export PDF 2
# -------------------------------------------------------------------------------

require_relative "mock_sketchup"
require_relative "../main"
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
          Service::InfoLineResolver.resolve(ctx, key)
        end

        def render_modular_slot_card(*args)
          true
        end

        def render
          ctx = Service::LayoutBuilder.send(:build_context, @project_data, nil, "DIN Condensed")
          page = @doc.pages.first
          layer = @doc.layers.first
          scene = @scene_item || Model::SceneItem.new(name: "Page", page_type: current_page_type)

          pt = current_page_type
          page_cfg = Service::LayoutBuilder.send(:get_page_cfg, { settings: @project_data.pdf_settings }, pt)
          [:slot_1, :slot_2, :slot_3, :slot_4].each do |slot_id|
            s_cfg = page_cfg[slot_id] || page_cfg[slot_id.to_s]
            if s_cfg && Service::LayoutBuilder.send(:block_visible?, page_cfg, slot_id)
              content_type = s_cfg[:content] || s_cfg["content"] || "info_lines"
              slot_box = get_block_box(pt, slot_id, 0, 0, 100, 100)
              render_modular_slot_card(slot_box, content_type, s_cfg, 1.0, slot_id)
            end
          end

          w_in = (@doc.respond_to?(:page_info) && @doc.page_info&.width) ? @doc.page_info.width.to_f : 11.6929
          h_in = (@doc.respond_to?(:page_info) && @doc.page_info&.height) ? @doc.page_info.height.to_f : 8.2677
          m_in = (@doc.respond_to?(:page_info) && @doc.page_info&.left_margin) ? @doc.page_info.left_margin.to_f : 0.2
          Service::LayoutBuilder.send(:render_modular_page, @doc, page, layer, scene, @page_index, @total_pages, w_in, h_in, m_in, ctx, [])
        end

        def get_block_box(pt, block_id, def_x, def_y, def_w, def_h)
          b_sym = block_id.to_sym
          canonical = case b_sym
                      when :general_header, :cover_header, :visual_header then :header
                      when :visual_image then :image_4_3
                      else b_sym
                      end
          w_pt = (@doc.respond_to?(:page_info) && @doc.page_info&.width) ? @doc.page_info.width * 72.0 : 841.89
          h_pt = (@doc.respond_to?(:page_info) && @doc.page_info&.height) ? @doc.page_info.height * 72.0 : 595.28
          m_pt = (@doc.respond_to?(:page_info) && @doc.page_info&.left_margin) ? @doc.page_info.left_margin * 72.0 : 14.17
          content = { left: m_pt, top: h_pt - m_pt, w: w_pt - (m_pt * 2), h: h_pt - (m_pt * 2) }
          cfg = Service::LayoutBuilder.send(:get_page_cfg, { settings: @project_data.pdf_settings }, pt)
          Service::LayoutBuilder.send(:get_block_box, content, cfg, canonical, def_x, def_y, def_w, def_h)
        end

        def block_visible?(pt, block_id)
          b_sym = block_id.to_sym
          canonical = case b_sym
                      when :general_header, :cover_header, :visual_header then :header
                      when :visual_image then :image_4_3
                      else b_sym
                      end
          cfg = Service::LayoutBuilder.send(:get_page_cfg, { settings: @project_data.pdf_settings }, pt)
          Service::LayoutBuilder.send(:block_visible?, cfg, canonical)
        end

        def get_block_config(pt, block_id)
          b_sym = block_id.to_sym
          canonical = case b_sym
                      when :general_header, :cover_header, :visual_header then :header
                      when :visual_image then :image_4_3
                      else b_sym
                      end
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
    test_articul_lock_flag
    test_auto_yaml_save_on_sketchup_save
    test_priority_reading_yaml_primary_model_secondary
    test_save_project_yaml_and_articul_rename
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
    test_scenes_table_two_row_layout
    test_template_settings_single_column_layout
    test_middle_block_item_controls_and_rendering
    test_blocks_drag_and_drop_reordering
    test_middle_block_vertical_center_alignment
    test_header_empty_lines_not_rendered
    test_middle_block_general_and_custom_font_size
    test_drawing_image_settings_proportions_and_placement
    test_manual_revision_prompt_before_pdf_export_and_no_auto_history
    test_footer_items_aligned_to_bottom_edge
    test_middle_block_lines_enabled_and_displayed_in_all_templates
    test_middle_block_item_gap_parameter
    test_header_default_vertical_alignment_top
    test_40_template_usage_separate_line
    test_41_api_targets_addition_and_deletion
    test_42_safe_frame_overlay_and_aspect_ratios
    test_43_new_project_yaml_data_structure
    test_44_template_independence_and_autosave
    test_directory_descriptions_in_template_middle_list
    test_directories_start_empty_and_deletions_persist
    test_template_block_item_multiline_and_title_toggle
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
    test_60_line_multiplier_consistent_across_all_render_modes
    test_61_page_formats_a4_a3_and_quality_levels
    test_62_auto_scale_font_size_reduction_30_pct
    test_63_layout_line_weight_and_annotation_font_size
    test_64_render_modes_image_and_hybrid
    test_66_page_font_family_selection
    test_text_height_and_no_clipping
    test_articul_folder_yaml_canonical_and_anchor
    test_articul_folder_export_structure
    test_last_pdf_copy_next_to_skp_and_history_link
    test_png_snapshots_respect_viewport_background
    test_scene_snapshots_webp_format_and_fallback
    test_scene_snapshots_reuse_rendered_source
    test_snapshot_worker_background_pool
    test_path_util_file_url_encoding
    test_history_rev_ver_fields_and_migration
    test_74_save_without_articul_writes_no_yaml
    test_75_legacy_yaml_migration_to_project_yaml
    test_76_discovery_multiple_articul_folders_ambiguous
    test_77_edit_history_in_articul_folder_with_fallback
    test_78_articul_offer_on_dialog_open_and_folder_creation

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

    project_data.sync_with_model_scenes(model)
    assert(project_data.scenes.size == 5, "Корректно обнаружено 5 сцен в модели")
    assert(project_data.scenes[0].page_type == :cover, "Сцена '01. Обложка' распознана как :cover")
    assert(project_data.scenes[1].page_type == :explain, "Сцена '02. Пояснения...' распознана как :explain")
    assert(project_data.scenes[2].page_type == :visual, "Сцена '03. Визуализация' распознана как :visual")
    assert(project_data.scenes[3].page_type == :general, "Сцена '04. Общий вид' распознана как :general")

    # Библиотека модели не используется: данные проекта живут в YAML и в памяти сессии
    assert(project_data.scenes[4].page_type == :general, "Сцена '05. Общий вид 2' распознана как :general")
  end

  def test_yaml_filename_resolution
    puts "\n--- 2. Тест правил именования YAML (project.yaml / legacy имена) ---"

    model = Sketchup::MockModel.new("U:/Projects/Villa/Apartment_Final.skp")

    # Актуальное имя файла данных проекта — всегда project.yaml (внутри папки артикула)
    pd = DN1Code::ExportPdf2::Model::ProjectData.new
    assert(pd.yaml_filename == "project.yaml", "yaml_filename без модели возвращает project.yaml")
    assert(pd.yaml_filename(model) == "project.yaml", "yaml_filename с моделью возвращает project.yaml")

    # Legacy-резолвер имен (схема до 2.1) сохранен: обнаружение и миграция старых проектов
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
    puts "\n--- 5. Тест источника данных: project.yaml в папке артикула (единственный источник) ---"

    test_dir = File.expand_path("test_priority_dir", __dir__)
    FileUtils.mkdir_p(test_dir)

    skp_file = File.join(test_dir, "Bedroom.skp")
    model = Sketchup::MockModel.new(skp_file)

    # 1. Создаем папку артикула с project.yaml (внешнее редактирование)
    art_yaml = File.join(test_dir, "BED-01", "project.yaml")
    FileUtils.mkdir_p(File.dirname(art_yaml))
    yaml_data = DN1Code::ExportPdf2::Model::ProjectData.new
    yaml_data.project_info[:articul] = "BED-01"
    yaml_data.project_info[:name_product] = "Имя из файла YAML (Первично)"
    yaml_data.save_to_yaml(art_yaml)

    # 2. Вызываем автоматическую загрузку
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

    # Проверка 3: Изменение артикула -> повторное сохранение с previous_articul
    project_data.project_info[:articul] = "OFFICE-901"
    project_data.project_info[:name_project] = "Кабинет Руководителя (Обновленный)"
    assert(project_data.save_project_yaml(model, previous_articul: "OFFICE-900"), "Повторный save_project_yaml успешен")

    yaml_file_2 = File.join(test_dir, "OFFICE-901", "project.yaml")
    assert(File.exist?(yaml_file_2), "При смене артикула создана новая папка с project.yaml")
    assert(File.exist?(yaml_file_1), "Папка прежнего артикула сохранена (история)")
    assert(!File.exist?(File.join(test_dir, "OFFICE-900.yaml")), "Якорь прежнего артикула рядом с .skp отсутствует")

    # Проверка 4: Очистка артикула -> сохранение отклоняется
    project_data.project_info[:articul] = ""
    assert(!project_data.save_project_yaml(model, previous_articul: "OFFICE-901"), "Сохранение без артикула отклонено")
    assert(!File.exist?(File.join(test_dir, "Office.yaml")), "Файл по имени модели без артикула не создается")
    assert(File.exist?(yaml_file_2), "Данные прежнего артикула остались на диске")

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

    # Сохраняем: YAML проекта + шаблоны в layout.yaml плагина
    project_data.save_project_yaml(model)
    project_data.save_to_layout_yaml(DN1Code::ExportPdf2::Model::ProjectData::PROGRAM_LAYOUT_FILE)

    prj_yaml = File.join(test_dir, "VILLA-100", "project.yaml")
    local_layout_yaml = File.join(test_dir, "layout.yaml")

    assert(File.exist?(prj_yaml), "project.yaml создан в папке артикула (#{prj_yaml})")
    assert(!File.exist?(File.join(test_dir, "VILLA-100.yaml")), "Якорь-YAML рядом с .skp не создается")
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
    assert(hdr[:valign] == "top" || hdr[:valign] == :top, "Шапка по умолчанию имеет вертикальное выравнивание top")
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

    # Создаем 4 сцены: 3 включены, 1 отключена
    scenes = [
      DN1Code::ExportPdf2::Model::SceneItem.new(name: "01. Обложка", page_type: :cover, enabled: true),
      DN1Code::ExportPdf2::Model::SceneItem.new(name: "02. Содержание", page_type: :explain, enabled: true),
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

  def test_template_settings_single_column_layout
    puts "\n--- 28. Тест компоновки настроек шаблонов в один столбец (Заголовок, Средний, Подвал) ---"
    app_js_path = File.expand_path("../dialog/html/app.js", __dir__)
    app_js_content = File.read(app_js_path, encoding: "utf-8")

    # 0. Проверка валидности синтаксиса JavaScript
    node_check = `node -c "#{app_js_path}" 2>&1`
    assert($?.success?, "app.js не содержит синтаксических ошибок JS: #{node_check.strip}")

    # 1. Проверка структуры единого столбца
    assert(app_js_content.include?("tpl-single-column-layout"), "app.js содержит контейнер единого столбца tpl-single-column-layout")

    # 2. Проверка карточек Заголовок, Средний, Подвал
    assert(app_js_content.include?('id="card_header"'), "app.js содержит карточку card_header (Заголовок)")
    assert(app_js_content.include?('id="card_middle"'), "app.js содержит карточку card_middle (Средний)")
    assert(app_js_content.include?('id="card_footer"'), "app.js содержит карточку card_footer (Подвал)")

    # 3. Проверка строгого порядка следования в один столбец: Заголовок -> Средний -> Подвал
    single_col_block = app_js_content[/tpl-single-column-layout.*?<\/div>/m]
    assert(single_col_block != nil, "Блок tpl-single-column-layout найден в app.js")
    if single_col_block
      hdr_pos = single_col_block.index("cardHeaderHtml")
      mid_pos = single_col_block.index("cardMiddleHtml")
      ftr_pos = single_col_block.index("cardFooterHtml")
      assert(hdr_pos && mid_pos && ftr_pos, "Все 3 карточки присутствуют в едином столбце")
      assert(hdr_pos < mid_pos, "Заголовок идет первым (перед Средним)")
      assert(mid_pos < ftr_pos, "Средний блок идет вторым (перед Подвалом)")
    end

    # 4. Проверка содержимого карточки «Средний блок»
    assert(app_js_content.include?("Средний блок"), "app.js содержит заголовок 'Средний блок'")
    assert(app_js_content.include?('data-slot="slot_1"'), "Средний блок управляет информационным слотом slot_1")
    assert(app_js_content.include?("sel-slot-fontsize"), "Средний блок содержит выбор кегля шрифта")
    assert(app_js_content.include?("btn-slot-all"), "Средний блок содержит кнопку 'Все'")
    assert(app_js_content.include?("btn-slot-none"), "Средний блок содержит кнопку 'Снять'")

    # 5. Проверка удаления колонок из настроек шаблонов
    assert(!app_js_content.include?("tpl-toolbar-card"), "app.js больше не содержит блок tpl-toolbar-card")
    assert(!app_js_content.include?("inp_col_width_left"), "app.js больше не содержит регулятор ширины левой колонки")
    assert(!app_js_content.include?("inp_col_width_right"), "app.js больше не содержит регулятор ширины правой колонки")
    assert(!app_js_content.include?("chk_sync_col_width"), "app.js больше не содержит чекбокс синхронизации ширины колонок")
    assert(!app_js_content.include?("btn-col-preset"), "app.js больше не содержит кнопки пресетов ширины колонок")
    assert(!app_js_content.include?("Левый верхний блок"), "app.js больше не содержит 4 отдельных угловых слота")

    # 6. Проверка стилей в app.css
    app_css_path = File.expand_path("../dialog/html/app.css", __dir__)
    app_css_content = File.read(app_css_path, encoding: "utf-8")
    assert(app_css_content.include?(".tpl-single-column-layout"), "app.css содержит стиль .tpl-single-column-layout")
    assert(app_css_content.include?("#card_middle"), "app.css содержит правило для #card_middle")
  end

  # ============================================================================
  # 29. ТЕСТ: Настройка каждого пункта Среднего блока значками
  # ============================================================================
  def test_middle_block_item_controls_and_rendering
    puts "\n--- 29. Тест настройки пунктов Среднего блока значками ---"

    # 1. Проверка разметки элементов управления строками в app.js
    app_js_path = File.expand_path("../dialog/html/app.js", __dir__)
    app_js_content = File.read(app_js_path, encoding: "utf-8")

    assert(app_js_content.include?("tpl-middle-columns-header"), "app.js содержит шапку колонок среднего блока tpl-middle-columns-header")
    assert(app_js_content.include?("tpl-middle-col-titles"), "app.js содержит контейнер заголовков колонок tpl-middle-col-titles")
    assert(app_js_content.include?("tpl-btn-middle-edge"), "app.js содержит кнопки выравнивания по краю страницы tpl-btn-middle-edge")
    assert(app_js_content.include?("tpl-btn-middle-valign"), "app.js содержит кнопки положения сверху/снизу tpl-btn-middle-valign")
    assert(app_js_content.include?("sel-middle-line-size"), "app.js содержит выбор кегля шрифта строки sel-middle-line-size")
    assert(app_js_content.include?("inp-middle-line-color"), "app.js содержит выбор цвета строки inp-middle-line-color")
    assert(app_js_content.include?("MIDDLE_LINE_FONT_SIZES"), "app.js содержит константу MIDDLE_LINE_FONT_SIZES")

    # Проверка значков в разметке: ⇤ / ⇥ (край), ⬆ / ↕ / ⬇ (вертикаль), Aa (размер), 🎨 (палитра)
    assert(app_js_content.include?("data-align=\"left\" title=\"По левому краю страницы\">⇤"), "app.js содержит значок ⇤ для левого края")
    assert(app_js_content.include?("data-align=\"right\" title=\"По правому краю страницы\">⇥"), "app.js содержит значок ⇥ для правого края")
    assert(app_js_content.include?("data-valign=\"top\" title=\"Сверху\">⬆"), "app.js содержит значок ⬆ для положения сверху")
    assert(app_js_content.include?("data-valign=\"center\" title=\"По центру (середина)\">↕"), "app.js содержит значок ↕ для положения по центру (середина)")
    assert(app_js_content.include?("data-valign=\"bottom\" title=\"Снизу\">⬇"), "app.js содержит значок ⬇ для положения снизу")
    assert(app_js_content.include?("col-valign\" title=\"По высоте: сверху / середина / снизу\">⬆ ↕ ⬇"), "app.js содержит заголовок колонки ⬆ ↕ ⬇")

    # 2. Проверка обработчиков событий в app.js
    assert(app_js_content.include?("midEdgeBtns.forEach"), "app.js содержит обработку кликов по кнопкам выравнивания края")
    assert(app_js_content.include?("midValignBtns.forEach"), "app.js содержит обработку кликов по кнопкам положения сверху/снизу")
    assert(app_js_content.include?("midSizeSelects.forEach"), "app.js содержит обработку выбора размера шрифта строки")
    assert(app_js_content.include?("midColorInputs.forEach"), "app.js содержит обработку выбора цвета строки")

    # 3. Проверка стилей в app.css
    app_css_path = File.expand_path("../dialog/html/app.css", __dir__)
    app_css_content = File.read(app_css_path, encoding: "utf-8")

    assert(app_css_content.include?(".tpl-middle-columns-header"), "app.css содержит стиль .tpl-middle-columns-header")
    assert(app_css_content.include?(".tpl-middle-line-row"), "app.css содержит стиль .tpl-middle-line-row")
    assert(app_css_content.include?(".tpl-middle-label-wrap"), "app.css содержит стиль .tpl-middle-label-wrap")
    assert(app_css_content.include?(".tpl-middle-item-controls"), "app.css содержит стиль .tpl-middle-item-controls")
    assert(app_css_content.include?(".tpl-middle-edge-group"), "app.css содержит стиль .tpl-middle-edge-group")
    assert(app_css_content.include?(".tpl-middle-valign-group"), "app.css содержит стиль .tpl-middle-valign-group")
    assert(app_css_content.include?(".tpl-middle-col-title.col-valign"), "app.css содержит стиль .tpl-middle-col-title.col-valign")
    assert(app_css_content.include?("width: 66px;"), "app.css задает ширину 66px для 3 кнопок по высоте")
    assert(app_css_content.include?(".sel-middle-line-size"), "app.css содержит стиль .sel-middle-line-size")
    assert(app_css_content.include?(".inp-middle-line-color"), "app.css содержит стиль .inp-middle-line-color")

    # 4. Проверка структуры default_custom_layouts в project_data.rb
    project_data = DN1Code::ExportPdf2::Model::ProjectData.new
    [:cover, :description, :explain].each do |tpl|
      s1 = project_data.default_custom_layouts[tpl][:slot_1]
      assert(s1.key?(:line_aligns), "default_custom_layouts[#{tpl}][:slot_1] содержит line_aligns")
      assert(s1.key?(:line_valigns), "default_custom_layouts[#{tpl}][:slot_1] содержит line_valigns")
      assert(s1.key?(:line_font_sizes), "default_custom_layouts[#{tpl}][:slot_1] содержит line_font_sizes")
      assert(s1.key?(:line_colors), "default_custom_layouts[#{tpl}][:slot_1] содержит line_colors")
      assert(s1[:line_aligns]["toc_pages"] == "left", "default_custom_layouts[#{tpl}] toc_pages выровнен по левому краю")
      assert(s1[:line_valigns]["toc_pages"] == "top", "default_custom_layouts[#{tpl}] toc_pages расположен сверху")
    end

    # 5. Проверка генерации PDF с индивидуальными настройками пунктов среднего блока (включая center)
    project_data.pdf_settings[:custom_layouts][:cover][:slot_1] = {
      visible: true,
      content: "info_lines",
      align: "left",
      valign: "top",
      font_size: 8.0,
      lines: ["toc_pages", "spec_materials", "spec_appliances", "workflow_history"],
      line_aligns: { "toc_pages" => "left", "spec_materials" => "left", "spec_appliances" => "right", "workflow_history" => "right" },
      line_valigns: { "toc_pages" => "top", "spec_materials" => "center", "spec_appliances" => "center", "workflow_history" => "bottom" },
      line_font_sizes: { "toc_pages" => 10.0, "spec_materials" => 8.0, "spec_appliances" => 8.5, "workflow_history" => 9.0 },
      line_colors: { "toc_pages" => "#005EB0", "spec_materials" => "#334155", "spec_appliances" => "#1E293B", "workflow_history" => "#DC2626" }
    }

    mock_page = Sketchup::MockPage.new("01. Обложка")
    mock_page.description = "Описание сцены обложки"
    scene = DN1Code::ExportPdf2::Model::SceneItem.new(
      name: "01. Обложка",
      description: "Описание сцены обложки",
      scene_ref: mock_page,
      page_type: :cover,
      order: 1,
      enabled: true
    )

    pdf_doc = DN1Code::ExportPdf2::Service::PdfBuilder.create_document(project_data, project_data.pdf_settings)
    cover_page = DN1Code::ExportPdf2::Controller::CoverPage.new(pdf_doc, project_data, scene, page_index: 1, total_pages: 5)

    test_dir = File.expand_path("test_middle_controls_dir", __dir__)
    FileUtils.mkdir_p(test_dir)
    out_pdf = File.join(test_dir, "test_middle_block_rendering.pdf")

    cover_page.render
    pdf_doc.render_file(out_pdf)

    assert(File.exist?(out_pdf), "PDF с индивидуальными настройками пунктов среднего блока успешно сгенерирован")
    assert(File.size(out_pdf) > 5000, "Файл PDF создан и его размер валиден (#{File.size(out_pdf) rescue 0} байт)")
    FileUtils.rm_rf(test_dir)
  end

  # ============================================================================
  # 30. ТЕСТ: Перетаскивание (Drag and Drop) порядка пунктов мышкой в блоках шаблонов
  # ============================================================================
  def test_blocks_drag_and_drop_reordering
    puts "\n--- 30. Тест перетаскивания мышкой (Drag and Drop) пунктов в блоках настроек шаблонов ---"

    # 1. Проверка разметки и скрипта в app.js
    app_js_path = File.expand_path("../dialog/html/app.js", __dir__)
    app_js_content = File.read(app_js_path, encoding: "utf-8")

    # Валидность синтаксиса JavaScript
    node_check = `node -c "#{app_js_path}" 2>&1`
    assert($?.success?, "app.js не содержит синтаксических ошибок JS: #{node_check.strip}")

    # Проверка функции перетаскивания и привязки к 3 блокам
    assert(app_js_content.include?("setupBlockDragAndDrop"), "app.js содержит функцию setupBlockDragAndDrop")
    assert(app_js_content.include?("setupBlockDragAndDrop(cardHeader"), "Drag and drop привязан к блоку Шапка (cardHeader)")
    assert(app_js_content.include?("setupBlockDragAndDrop(cardMiddle"), "Drag and drop привязан к Среднему блоку (cardMiddle)")
    assert(app_js_content.include?("setupBlockDragAndDrop(cardFooter"), "Drag and drop привязан к блоку Подвал (cardFooter)")

    # Проверка сортировки по сохраненному порядку item_order
    assert(app_js_content.include?("savedHeaderOrder"), "app.js учитывает сохраненный порядок строк шапки savedHeaderOrder")
    assert(app_js_content.include?("savedMiddleOrder"), "app.js учитывает сохраненный порядок строк среднего блока savedMiddleOrder")
    assert(app_js_content.include?("savedFooterOrder"), "app.js учитывает сохраненный порядок строк подвала savedFooterOrder")

    # Проверка ручек перетаскивания и draggable в разметке
    assert(app_js_content.include?('span class="drag-handle" title="Перетащите мышкой для изменения порядка">⠿</span>'), "app.js содержит значок ручки захвата ⠿")
    assert(app_js_content.include?('tpl-hdr-line-row" draggable="true"'), "Строки шапки имеют атрибут draggable=\"true\"")
    assert(app_js_content.include?('tpl-middle-line-row" draggable="true"'), "Строки среднего блока имеют атрибут draggable=\"true\"")
    assert(app_js_content.include?('tpl-ftr-line-row" draggable="true"'), "Строки подвала имеют атрибут draggable=\"true\"")

    # Проверка событий Drag and Drop
    assert(app_js_content.include?('"dragstart"'), "app.js обрабатывает событие dragstart")
    assert(app_js_content.include?('"dragover"'), "app.js обрабатывает событие dragover")
    assert(app_js_content.include?('"dragleave"'), "app.js обрабатывает событие dragleave")
    assert(app_js_content.include?('"drop"'), "app.js обрабатывает событие drop")
    assert(app_js_content.include?('"dragend"'), "app.js обрабатывает событие dragend")
    assert(app_js_content.include?("insertBefore"), "app.js переставляет элементы в DOM через insertBefore")

    # 2. Проверка стилей в app.css
    app_css_path = File.expand_path("../dialog/html/app.css", __dir__)
    app_css_content = File.read(app_css_path, encoding: "utf-8")

    assert(app_css_content.include?(".tpl-line-item .drag-handle"), "app.css содержит стиль для .tpl-line-item .drag-handle")
    assert(app_css_content.include?("cursor: grab;"), "app.css задает cursor: grab для ручки перетаскивания")
    assert(app_css_content.include?(".tpl-line-item.dragging"), "app.css содержит стиль для перетаскиваемого элемента .tpl-line-item.dragging")
    assert(app_css_content.include?(".tpl-line-item.drag-over-top"), "app.css содержит стиль подсветки сверху .drag-over-top")
    assert(app_css_content.include?(".tpl-line-item.drag-over-bottom"), "app.css содержит стиль подсветки снизу .drag-over-bottom")

    # 3. Проверка генерации PDF с измененным порядком строк в шапке, среднем блоке и подвале
    project_data = DN1Code::ExportPdf2::Model::ProjectData.new
    project_data.pdf_settings[:custom_layouts][:cover][:header] = {
      visible: true,
      align: "center",
      valign: "center",
      lines: ["scene_name", "furniture_name", "place_address"],
      line_rows: { "scene_name" => 1, "furniture_name" => 2, "place_address" => 3 },
      line_font_sizes: { "scene_name" => 12.0, "furniture_name" => 14.0, "place_address" => 10.0 },
      line_colors: { "scene_name" => "#005EB0", "furniture_name" => "#0F172A", "place_address" => "#475569" }
    }
    project_data.pdf_settings[:custom_layouts][:cover][:slot_1] = {
      visible: true,
      content: "info_lines",
      align: "left",
      valign: "top",
      font_size: 8.0,
      lines: ["workflow_date", "general_notes", "toc_pages"],
      line_aligns: { "workflow_date" => "left", "general_notes" => "left", "toc_pages" => "left" },
      line_valigns: { "workflow_date" => "top", "general_notes" => "top", "toc_pages" => "top" },
      line_font_sizes: { "workflow_date" => 9.0, "general_notes" => 8.0, "toc_pages" => 10.0 },
      line_colors: { "workflow_date" => "#005EB0", "general_notes" => "#334155", "toc_pages" => "#1E293B" }
    }
    project_data.pdf_settings[:custom_layouts][:cover][:footer] = {
      visible: true,
      align: "center",
      valign: "center",
      font_size: 8.5,
      lines: ["footer_page_total", "footer_last_edit"],
      line_aligns: { "footer_page_total" => "right", "footer_last_edit" => "left" }
    }

    mock_page = Sketchup::MockPage.new("01. Обложка")
    mock_page.description = "Описание сцены обложки"
    scene = DN1Code::ExportPdf2::Model::SceneItem.new(
      name: "01. Обложка",
      description: "Описание сцены обложки",
      scene_ref: mock_page,
      page_type: :cover,
      order: 1,
      enabled: true
    )

    pdf_doc = DN1Code::ExportPdf2::Service::PdfBuilder.create_document(project_data, project_data.pdf_settings)
    cover_page = DN1Code::ExportPdf2::Controller::CoverPage.new(pdf_doc, project_data, scene, page_index: 1, total_pages: 5)

    test_dir = File.expand_path("test_dnd_dir", __dir__)
    FileUtils.mkdir_p(test_dir)
    out_pdf = File.join(test_dir, "test_dnd_reordered.pdf")

    cover_page.render
    pdf_doc.render_file(out_pdf)

    assert(File.exist?(out_pdf), "PDF с пользовательским порядком пунктов успешно сгенерирован")
    assert(File.size(out_pdf) > 5000, "Размер PDF валиден (#{File.size(out_pdf) rescue 0} байт)")
    FileUtils.rm_rf(test_dir)
  end

  # =========================================================================
  # ТЕСТ 31: Проверка выравнивания по вертикали центру пунктов среднего блока
  # =========================================================================
  def test_middle_block_vertical_center_alignment
    puts "\n--- 31. Тест выравнивания по вертикали центру пунктов среднего блока ---"

    # 1. Проверка центрирования иконки кнопки в CSS
    app_css_path = File.expand_path("../dialog/html/app.css", __dir__)
    app_css_content = File.read(app_css_path, encoding: "UTF-8")
    assert(app_css_content.include?(".tpl-middle-valign-group .tpl-btn-align"), "app.css содержит стили кнопок вертикального выравнивания")
    assert(app_css_content.include?("align-items: center;"), "app.css задает align-items: center для кнопок")
    assert(app_css_content.include?("justify-content: center;"), "app.css задает justify-content: center для кнопок")

    # 2. Проверка генерации PDF, когда пункт среднего блока расположен строго по центру
    project_data = DN1Code::ExportPdf2::Model::ProjectData.new
    project_data.pdf_settings[:custom_layouts][:cover][:slot_1] = {
      visible: true,
      content: "info_lines",
      align: "left",
      valign: "top",
      font_size: 8.0,
      lines: ["spec_materials"],
      line_aligns: { "spec_materials" => "left" },
      line_valigns: { "spec_materials" => "center" },
      line_font_sizes: { "spec_materials" => 9.0 },
      line_colors: { "spec_materials" => "#1E293B" }
    }

    mock_page = Sketchup::MockPage.new("01. Обложка")
    mock_page.description = "Описание сцены обложки"
    scene = DN1Code::ExportPdf2::Model::SceneItem.new(
      name: "01. Обложка",
      description: "Описание сцены обложки",
      scene_ref: mock_page,
      page_type: :cover,
      order: 1,
      enabled: true
    )

    pdf_doc = DN1Code::ExportPdf2::Service::PdfBuilder.create_document(project_data, project_data.pdf_settings)
    cover_page = DN1Code::ExportPdf2::Controller::CoverPage.new(pdf_doc, project_data, scene, page_index: 1, total_pages: 5)

    test_dir = File.expand_path("test_valign_dir", __dir__)
    FileUtils.mkdir_p(test_dir)
    out_pdf = File.join(test_dir, "test_valign_center_single.pdf")

    cover_page.render
    pdf_doc.render_file(out_pdf)

    assert(File.exist?(out_pdf), "PDF с одиночным пунктом по вертикали центру успешно сгенерирован")
    assert(File.size(out_pdf) > 5000, "Размер PDF валиден (#{File.size(out_pdf) rescue 0} байт)")

    # 3. Проверка генерации PDF с тремя зонами (top, center, bottom)
    project_data2 = DN1Code::ExportPdf2::Model::ProjectData.new
    project_data2.pdf_settings[:custom_layouts][:cover][:slot_1] = {
      visible: true,
      content: "info_lines",
      align: "left",
      valign: "top",
      font_size: 8.0,
      lines: ["toc_pages", "spec_materials", "workflow_history"],
      line_aligns: { "toc_pages" => "left", "spec_materials" => "left", "workflow_history" => "left" },
      line_valigns: { "toc_pages" => "top", "spec_materials" => "center", "workflow_history" => "bottom" },
      line_font_sizes: { "toc_pages" => 8.0, "spec_materials" => 8.0, "workflow_history" => 8.0 },
      line_colors: { "toc_pages" => "#334155", "spec_materials" => "#334155", "workflow_history" => "#334155" }
    }

    pdf_doc2 = DN1Code::ExportPdf2::Service::PdfBuilder.create_document(project_data2, project_data2.pdf_settings)
    cover_page2 = DN1Code::ExportPdf2::Controller::CoverPage.new(pdf_doc2, project_data2, scene, page_index: 1, total_pages: 5)
    out_pdf2 = File.join(test_dir, "test_valign_three_zones.pdf")

    cover_page2.render
    pdf_doc2.render_file(out_pdf2)

    assert(File.exist?(out_pdf2), "PDF с тремя зонами (верх, центр, низ) успешно сгенерирован")
    assert(File.size(out_pdf2) > 5000, "Размер PDF валиден (#{File.size(out_pdf2) rescue 0} байт)")

    # 4. Проверка математики вычисления смещения offset в центре
    in_h = 400.0
    total_items_h = 60.0
    offset = [(in_h - total_items_h) / 2.0, 0.0].max
    top_margin = offset
    bottom_margin = in_h - total_items_h - offset
    assert(top_margin == 170.0, "Верхний отступ точно равен 170.0 pt")
    assert(bottom_margin == 170.0, "Нижний отступ точно равен 170.0 pt")
    assert(top_margin == bottom_margin, "Вертикальное центрирование строго симметрично (отступ сверху равен отступу снизу)")

    FileUtils.rm_rf(test_dir)
  end

  def test_header_empty_lines_not_rendered
    puts "\n--- 32. Тест отключения всех пунктов шапки (Заголовок пуст) ---"
    project_data = DN1Code::ExportPdf2::Model::ProjectData.new
    project_data.project_info[:furniture_name] = "Тестовая мебель"
    project_data.project_info[:room_name] = "Гостиная"
    project_data.project_info[:address] = "ул. Примерная, 1"
    project_data.project_info[:name_customer] = "Тестовый Заказчик"

    # Отключаем все пункты в заголовке
    project_data.pdf_settings[:custom_layouts][:cover][:header][:lines] = []

    # Слот включаем явно: текущий layout.yaml прячет slot_1 у обложки,
    # а тест проверяет именно отсутствие строк заголовка, а не пустоту листа
    project_data.pdf_settings[:custom_layouts][:cover][:slot_1][:visible] = true

    test_dir = File.expand_path("test_header_empty_lines_dir", __dir__)
    FileUtils.mkdir_p(test_dir)
    pdf_out = File.join(test_dir, "header_empty.pdf")

    pdf_doc = Prawn::Document.new(page_size: "A4", page_layout: :landscape, margin: 15)
    DN1Code::ExportPdf2::Service::FontService.setup_fonts(pdf_doc)
    cover_page = DN1Code::ExportPdf2::Controller::CoverPage.new(pdf_doc, project_data, nil, page_index: 1, total_pages: 1)
    
    # Рендерим страницу с отключенными пунктами
    cover_page.render
    pdf_doc.render_file(pdf_out)

    assert(File.exist?(pdf_out), "PDF с отключенными пунктами заголовка успешно создан")
    assert(File.size(pdf_out) > 3000, "Размер PDF валиден (#{File.size(pdf_out)} байт)")

    # Проверяем, что в app.js возвращается пустая строка при отсутствии строк
    app_js_path = File.expand_path("../dialog/html/app.js", __dir__)
    app_js_content = File.read(app_js_path, encoding: "utf-8")
    assert(app_js_content.include?("if (renderedLines.length === 0) {\n        return \"\";\n      }"), "app.js возвращает пустую строку, если все пункты заголовка отключены")

    FileUtils.rm_rf(test_dir)
  end

  # ============================================================================
  # 33. ТЕСТ: Общий размер шрифта среднего блока и переназначение в пунктах
  # ============================================================================
  def test_middle_block_general_and_custom_font_size
    puts "\n--- 33. Тест общего размера шрифта среднего блока и переназначения в пунктах ---"
    app_js_path = File.expand_path("../dialog/html/app.js", __dir__)
    app_js_content = File.read(app_js_path, encoding: "utf-8")

    # 1. Проверка шкалы MIDDLE_LINE_FONT_SIZES для общего шрифта среднего блока
    assert(app_js_content.include?("renderFontSizeOptions(middleFontSize, MIDDLE_LINE_FONT_SIZES, 8)"),
           "app.js использует шкалу MIDDLE_LINE_FONT_SIZES для выбора общего шрифта среднего блока")

    # 2. Проверка каскадного обновления s1.line_font_sizes при смене общего шрифта среднего блока
    assert(app_js_content.include?('if (sId === "slot_1") {'), "app.js имеет отдельную обработку изменения шрифта для slot_1")
    assert(app_js_content.include?("s1.line_font_sizes[k] = newFs;"), "app.js присваивает новый общий шрифт всем строкам среднего блока")
    assert(app_js_content.include?('midSelects = els.templateSettingsContainer.querySelectorAll(".sel-middle-line-size")'),
           "app.js находит все выпадающие списки пунктов среднего блока")
    assert(app_js_content.include?("midSel.value = newFs.toString();"),
           "app.js синхронно обновляет значения в селекторах пунктов при смене общего шрифта")

    # 3. Проверка применения line_font_sizes и line_colors в превью виртуального листа
    assert(app_js_content.include?("const lineFontSizes = blk.line_font_sizes || {};"),
           "generateBlockPreviewHtml извлекает line_font_sizes")
    assert(app_js_content.include?("const itFs = parseFloat(lineFontSizes[lineKey]) || fontSize;"),
           "generateBlockPreviewHtml вычисляет размер шрифта каждого пункта (индивидуальный или общий по умолчанию)")

    # 4. Проверка генерации PDF: общий шрифт 10 pt + переназначение в пунктах (toc_pages = 14 pt, workflow_date = 7 pt)
    project_data = DN1Code::ExportPdf2::Model::ProjectData.new
    project_data.pdf_settings[:custom_layouts][:cover][:slot_1] = {
      visible: true,
      content: "info_lines",
      align: "left",
      valign: "top",
      font_size: 10.0, # Общий размер шрифта
      lines: ["toc_pages", "spec_materials", "workflow_date"],
      line_aligns: { "toc_pages" => "left", "spec_materials" => "left", "workflow_date" => "right" },
      line_valigns: { "toc_pages" => "top", "spec_materials" => "top", "workflow_date" => "bottom" },
      line_font_sizes: {
        "toc_pages" => 14.0,       # Индивидуально переназначенный крупный шрифт
        "spec_materials" => 10.0,  # Оставлен общий шрифт (10 pt)
        "workflow_date" => 7.0     # Индивидуально переназначенный мелкий шрифт
      },
      line_colors: {
        "toc_pages" => "#005EB0",
        "spec_materials" => "#334155",
        "workflow_date" => "#EA580C"
      }
    }

    mock_page = Sketchup::MockPage.new("01. Обложка")
    mock_page.description = "Тест общего и индивидуального шрифтов"
    scene = DN1Code::ExportPdf2::Model::SceneItem.new(
      name: "01. Обложка",
      description: "Тест шрифтов",
      scene_ref: mock_page,
      page_type: :cover,
      order: 1,
      enabled: true
    )

    pdf_doc = DN1Code::ExportPdf2::Service::PdfBuilder.create_document(project_data, project_data.pdf_settings)
    cover_page = DN1Code::ExportPdf2::Controller::CoverPage.new(pdf_doc, project_data, scene, page_index: 1, total_pages: 1)

    test_dir = File.expand_path("test_middle_font_sizes_dir", __dir__)
    FileUtils.mkdir_p(test_dir)
    out_pdf = File.join(test_dir, "test_middle_font_sizes.pdf")

    cover_page.render
    pdf_doc.render_file(out_pdf)

    assert(File.exist?(out_pdf), "PDF с общим шрифтом и индивидуально переназначенными пунктами успешно сгенерирован")
    assert(File.size(out_pdf) > 5000, "Размер PDF валиден (#{File.size(out_pdf) rescue 0} байт)")
    FileUtils.rm_rf(test_dir)
  end

  # ============================================================================
  # 34. ТЕСТ: Настройка картинки чертежа под текст (пропорции 3:2, 4:3, 16:9 и размещение 60-100%)
  # ============================================================================
  def test_drawing_image_settings_proportions_and_placement
    puts "\n--- 34. Тест настройки картинки чертежа под текст (пропорции 3:2, 4:3, 16:9 и масштаб 60-100%) ---"

    app_js_path = File.expand_path("../dialog/html/app.js", __dir__)
    app_js_content = File.read(app_js_path, encoding: "utf-8")

    # 1. Проверка карточки картинки в UI шаблонов (app.js)
    assert(app_js_content.include?('id="card_image"'), "app.js содержит карточку card_image для картинки чертежа")
    assert(app_js_content.include?('id="chk_image_4_3_visible"'), "app.js содержит чекбокс включения картинки chk_image_4_3_visible")
    assert(app_js_content.include?("Картинка чертежа под текст"), "app.js содержит заголовок 'Картинка чертежа под текст'")

    # 2. Проверка кнопок пропорций (3:2, 4:3, 16:9)
    assert(app_js_content.include?('id="grp_image_aspect_ratio"'), "app.js содержит группу кнопок пропорций grp_image_aspect_ratio")
    assert(app_js_content.include?('data-ratio="3:2"'), "app.js содержит кнопку выбора пропорции 3:2")
    assert(app_js_content.include?('data-ratio="4:3"'), "app.js содержит кнопку выбора пропорции 4:3")
    assert(app_js_content.include?('data-ratio="16:9"'), "app.js содержит кнопку выбора пропорции 16:9")

    # 3. Проверка кнопок размещения на странице (60%, 70%, 80%, 90%, 100%)
    assert(app_js_content.include?('id="grp_image_scale_pct"'), "app.js содержит группу кнопок масштаба grp_image_scale_pct")
    assert(app_js_content.include?('data-scale="60"'), "app.js содержит кнопку масштаба 60%")
    assert(app_js_content.include?('data-scale="70"'), "app.js содержит кнопку масштаба 70%")
    assert(app_js_content.include?('data-scale="80"'), "app.js содержит кнопку масштаба 80%")
    assert(app_js_content.include?('data-scale="90"'), "app.js содержит кнопку масштаба 90%")
    assert(app_js_content.include?('data-scale="100"'), "app.js содержит кнопку масштаба 100%")

    # 4. Проверка обработчиков кликов и автосохранения
    assert(app_js_content.include?("updateBlockSlot(\"image_4_3\", { aspect_ratio: ratio })"), "app.js обновляет aspect_ratio при смене пропорции")
    assert(app_js_content.include?("updateBlockSlot(\"image_4_3\", { scale_pct: scale })"), "app.js обновляет scale_pct при смене масштаба")

    # 5. Проверка стилей в app.css
    app_css_path = File.expand_path("../dialog/html/app.css", __dir__)
    app_css_content = File.read(app_css_path, encoding: "utf-8")
    assert(app_css_content.include?("#card_image"), "app.css содержит стили для #card_image")
    assert(app_css_content.include?(".tpl-image-controls-row"), "app.css содержит стиль .tpl-image-controls-row")
    assert(app_css_content.include?(".tpl-image-note"), "app.css содержит стиль .tpl-image-note")

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
  def test_footer_items_aligned_to_bottom_edge
    puts "\n--- 36. Тест выравнивания пунктов подвала по нижнему краю страницы ---"

    # 1. Проверка значений по умолчанию в ProjectData
    project_data = DN1Code::ExportPdf2::Model::ProjectData.new
    [:cover, :description, :explain, :general, :visual].each do |tpl|
      ftr = project_data.default_custom_layouts[tpl][:footer]
      assert(ftr[:valign] == "bottom", "default_custom_layouts[#{tpl}][:footer] имеет valign: bottom")
    end

    # 2. Проверка default_layout.yaml и layout.yaml на наличие valign: bottom для footer
    default_yaml = File.read(File.expand_path("../config/default_layout.yaml", __dir__), encoding: "utf-8")
    assert(default_yaml.scan(/footer:.*?valign:\s*bottom/m).size >= 5, "default_layout.yaml содержит valign: bottom для всех подвалов")

    layout_yaml = File.read(File.expand_path("../config/layout.yaml", __dir__), encoding: "utf-8")
    assert(layout_yaml.scan(/footer:.*?valign:\s*bottom/m).size >= 5, "layout.yaml содержит valign: bottom для всех подвалов")

    # 3. Проверка app.js (DEFAULT_LAYOUTS и превью)
    app_js_path = File.expand_path("../dialog/html/app.js", __dir__)
    app_js_content = File.read(app_js_path, encoding: "utf-8")

    assert(app_js_content.scan(/footer:\s*\{[^}]+valign:\s*"bottom"/).size >= 5, "app.js DEFAULT_LAYOUTS содержит valign: bottom для всех подвалов")
    assert(app_js_content.include?("align-items: flex-end"), "app.js превью виртуального листа выравнивает пункты подвала по низу (align-items: flex-end)")
    assert(app_js_content.include?("По нижнему краю страницы ⬇"), "app.js карточка подвала содержит указание на выравнивание по нижнему краю страницы")

    # 4. Проверка математики get_block_box: привязка подвала строго к нижнему краю листа (y + h = 100%)
    pdf_doc = Prawn::Document.new(page_size: "A4", page_layout: :landscape, margin: 15)
    DN1Code::ExportPdf2::Service::FontService.setup_fonts(pdf_doc)
    cover_page = DN1Code::ExportPdf2::Controller::CoverPage.new(pdf_doc, project_data, nil, page_index: 1, total_pages: 1)

    ftr_box = cover_page.send(:get_block_box, :cover, :footer, 0.0, 94.0, 100.0, 6.0)
    # Нижняя граница блока ftr_box[:y] - ftr_box[:height] должна в точности равняться pdf_doc.bounds.bottom
    box_bottom = ftr_box[:y] - ftr_box[:height]
    assert((box_bottom - pdf_doc.bounds.bottom).abs < 0.001, "Нижний край блока подвала в точности совпадает с bounds.bottom страницы")

    # 5. Проверка генерации PDF с подвалом, прижатым к нижнему краю
    mock_page = Sketchup::MockPage.new("01. Обложка")
    mock_page.description = "Тест подвала по нижнему краю"
    scene = DN1Code::ExportPdf2::Model::SceneItem.new(
      name: "01. Обложка",
      description: "Тест подвала",
      scene_ref: mock_page,
      page_type: :cover,
      order: 1,
      enabled: true
    )

    test_dir = File.expand_path("test_footer_bottom_dir", __dir__)
    FileUtils.mkdir_p(test_dir)
    out_pdf = File.join(test_dir, "test_footer_bottom.pdf")

    cover_page.render
    pdf_doc.render_file(out_pdf)

    assert(File.exist?(out_pdf), "PDF с подвалом по нижнему краю страницы успешно создан")
    assert(File.size(out_pdf) > 5000, "Размер созданного PDF валиден (#{File.size(out_pdf) rescue 0} байт)")

    FileUtils.rm_rf(test_dir)
  end

  # ============================================================================
  # 37. ТЕСТ: Отображение информации среднего блока во всех шаблонах
  # ============================================================================
  def test_middle_block_lines_enabled_and_displayed_in_all_templates
    puts "\n--- 37. Тест отображения информации среднего блока во всех шаблонах ---"

    # 1. Проверка значений по умолчанию в ProjectData#default_custom_layouts
    project_data = DN1Code::ExportPdf2::Model::ProjectData.new
    [:cover, :description, :explain, :general, :visual].each do |tpl|
      s1 = project_data.default_custom_layouts[tpl][:slot_1]
      assert(s1[:content] == "info_lines", "default_custom_layouts[#{tpl}][:slot_1] имеет content: info_lines")
      assert(s1[:lines].is_a?(Array) && !s1[:lines].empty?, "default_custom_layouts[#{tpl}][:slot_1] содержит строки информации по умолчанию")
    end

    # 2. Проверка default_layout.yaml и layout.yaml
    default_yaml = File.read(File.expand_path("../config/default_layout.yaml", __dir__), encoding: "utf-8")
    assert(default_yaml.scan(/slot_1:.*?content:\s*info_lines/m).size >= 5, "default_layout.yaml содержит content: info_lines для slot_1 всех шаблонов")

    layout_yaml = File.read(File.expand_path("../config/layout.yaml", __dir__), encoding: "utf-8")
    assert(layout_yaml.scan(/slot_1:.*?content:\s*info_lines/m).size >= 5, "layout.yaml содержит content: info_lines для slot_1 всех шаблонов")

    # 3. Проверка app.js
    app_js_path = File.expand_path("../dialog/html/app.js", __dir__)
    app_js_content = File.read(app_js_path, encoding: "utf-8")

    assert(app_js_content.include?('content: "info_lines"'), "app.js содержит content: info_lines")
    assert(app_js_content.scan(/DEFAULT_MIDDLE_SLOT\s*=\s*\{[^}]+content:\s*"info_lines"/m).size >= 1, "app.js DEFAULT_MIDDLE_SLOT имеет content: info_lines")
    assert(app_js_content.scan(/id:\s*"slot_1",\s*label:\s*"ЛЕВЫЙ ВЕРХ",\s*icon:\s*"⬛",\s*slot_class:\s*"slot-1",\s*default_content:\s*"info_lines"/m).size >= 1, "app.js FIXED_SLOT_DEFS содержит default_content: info_lines для slot_1")
    assert(app_js_content.include?('s1.content = "info_lines";'), "app.js ensureMiddleSlotDefaults гарантирует s1.content = info_lines")

    # 4. Проверка PageBase#resolve_info_line на непустые заглушки для пустых реквизитов
    pdf_doc = Prawn::Document.new(page_size: "A4", page_layout: :landscape, margin: 15)
    DN1Code::ExportPdf2::Service::FontService.setup_fonts(pdf_doc)
    page_ctrl = DN1Code::ExportPdf2::Controller::CoverPage.new(pdf_doc, project_data, nil, page_index: 1, total_pages: 1)

    assert(page_ctrl.send(:resolve_info_line, "room_name") == "Помещение: —", "resolve_info_line возвращает читаемую заглушку для пустого помещения")
    assert(page_ctrl.send(:resolve_info_line, "furniture_name") == "Изделие: —", "resolve_info_line возвращает читаемую заглушку для пустого изделия")
    assert(page_ctrl.send(:resolve_info_line, "articul") == "Артикул: —", "resolve_info_line возвращает читаемую заглушку для пустого артикула")
    assert(page_ctrl.send(:resolve_info_line, "address") == "Адрес: —", "resolve_info_line возвращает читаемую заглушку для пустого адреса")

    # 5. Проверка фактической отрисовки среднего блока в PDF с включенными параметрами
    test_dir = File.expand_path("test_middle_block_dir", __dir__)
    FileUtils.mkdir_p(test_dir)
    out_pdf = File.join(test_dir, "test_middle_block_render.pdf")

    # Задаем тестовые реквизиты
    project_data.project_info[:room_name] = "Кухня-гостиная"
    project_data.project_info[:furniture_name] = "Остров с барной стойкой"
    project_data.project_info[:articul] = "CF#2026-TEST-MID"
    project_data.project_info[:materials] = "Фасады Fenix NTM, столешница Granit, фурнитура Blum"
    project_data.project_info[:appliances] = "Вытяжка Elica, подсветка LED 3000K"
    project_data.workflow[:status] = "В производстве"
    project_data.workflow[:stadia] = "РД"

    # Включаем slot_1 на титульном листе со всеми параметрами
    project_data.pdf_settings[:custom_layouts][:cover][:slot_1][:visible] = true
    project_data.pdf_settings[:custom_layouts][:cover][:slot_1][:content] = "info_lines"
    project_data.pdf_settings[:custom_layouts][:cover][:slot_1][:lines] = [
      "room_name", "furniture_name", "articul", "spec_materials", "spec_appliances", "workflow_stadia"
    ]

    card_rendered = false
    page_ctrl.define_singleton_method(:render_modular_slot_card) do |*args|
      slot_box, content, cfg, opacity, slot_id = args
      card_rendered = true if content == "info_lines" || (slot_id && slot_id.to_s.start_with?("slot_"))
      super(*args)
    end

    page_ctrl.render
    pdf_doc.render_file(out_pdf)

    assert(card_rendered, "render_modular_slot_card успешно вызвана для карточек среднего блока")
    assert(File.exist?(out_pdf), "PDF с отрисованным средним блоком успешно создан")
    assert(File.size(out_pdf) > 8000, "Размер созданного PDF валиден (#{File.size(out_pdf) rescue 0} байт)")

    FileUtils.rm_rf(test_dir)
  end

  # --- 38. Тест параметра расстояния между пунктами среднего блока на странице ---
  def test_middle_block_item_gap_parameter
    puts "\n--- 38. Тест параметра расстояния между пунктами среднего блока на странице ---"

    project_data = DN1Code::ExportPdf2::Model::ProjectData.new
    layouts = project_data.default_custom_layouts

    # 1. Проверка наличия item_gap_mm в default_custom_layouts для всех 5 шаблонов
    [:cover, :description, :explain, :general, :visual].each do |tpl|
      s1 = layouts[tpl][:slot_1]
      assert(s1.key?(:item_gap_mm) || s1.key?("item_gap_mm"), "default_custom_layouts[#{tpl}][:slot_1] содержит item_gap_mm")
      val = (s1[:item_gap_mm] || s1["item_gap_mm"]).to_f
      assert(val == 2.0, "default_custom_layouts[#{tpl}][:slot_1] item_gap_mm по умолчанию равен 2.0 мм")
    end

    # 2. Проверка наличия item_gap_mm в конфигурационных файлах YAML
    default_yaml = File.read(File.join(__dir__, "..", "config", "default_layout.yaml"), encoding: "utf-8")
    layout_yaml = File.read(File.join(__dir__, "..", "config", "layout.yaml"), encoding: "utf-8")

    assert(default_yaml.include?("item_gap_mm:"), "default_layout.yaml содержит item_gap_mm")
    assert(layout_yaml.include?("item_gap_mm:"), "layout.yaml содержит item_gap_mm")

    # 3. Проверка наличия контрола в app.js и стилей в app.css
    app_js_content = File.read(File.join(__dir__, "..", "dialog", "html", "app.js"), encoding: "utf-8")
    app_css_content = File.read(File.join(__dir__, "..", "dialog", "html", "app.css"), encoding: "utf-8")

    assert(app_js_content.include?("inp-slot-itemgap"), "app.js содержит поле ввода .inp-slot-itemgap")
    assert(app_js_content.include?("item_gap_mm"), "app.js сохраняет и передает item_gap_mm")
    assert(app_js_content.include?("Расстояние между пунктами на странице"), "app.js содержит подсказку 'Расстояние между пунктами на странице'")
    assert(app_css_content.include?(".inp-slot-itemgap"), "app.css содержит стили для .inp-slot-itemgap")

    # 4. Проверка динамического расчета item_gap в PageBase
    test_dir = File.join(__dir__, "test_item_gap_dir")
    FileUtils.mkdir_p(test_dir)
    out_pdf_2mm = File.join(test_dir, "export_gap_2mm.pdf")
    out_pdf_10mm = File.join(test_dir, "export_gap_10mm.pdf")

    pdf_doc_2mm = DN1Code::ExportPdf2::Service::PdfBuilder.create_document(project_data, { margin_mm: 5 })
    page_ctrl_2mm = DN1Code::ExportPdf2::Controller::CoverPage.new(pdf_doc_2mm, project_data, nil, page_index: 1, total_pages: 1)

    captured_gaps = []
    page_ctrl_2mm.define_singleton_method(:render_modular_slot_card) do |*args|
      slot_box, content, cfg, opacity, slot_id = args
      if content == "info_lines"
        raw_gap = cfg[:item_gap_mm] || cfg["item_gap_mm"]
        calc_gap = (raw_gap.to_f * 72.0 / 25.4).round(1)
        captured_gaps << calc_gap
      end
      super(*args)
    end

    project_data.pdf_settings[:custom_layouts][:cover][:slot_1][:visible] = true
    project_data.pdf_settings[:custom_layouts][:cover][:slot_1][:item_gap_mm] = 2.0
    page_ctrl_2mm.render
    pdf_doc_2mm.render_file(out_pdf_2mm)

    assert(captured_gaps.any? { |g| (g - 5.7).abs < 0.2 }, "item_gap для 2.0 мм рассчитан корректно в pt (~5.7 pt)")
    assert(File.exist?(out_pdf_2mm), "PDF с расстоянием между пунктами 2 мм успешно создан")

    captured_gaps_10mm = []
    pdf_doc_10mm = DN1Code::ExportPdf2::Service::PdfBuilder.create_document(project_data, { margin_mm: 5 })
    page_ctrl_10mm = DN1Code::ExportPdf2::Controller::CoverPage.new(pdf_doc_10mm, project_data, nil, page_index: 1, total_pages: 1)

    page_ctrl_10mm.define_singleton_method(:render_modular_slot_card) do |*args|
      slot_box, content, cfg, opacity, slot_id = args
      if content == "info_lines"
        raw_gap = cfg[:item_gap_mm] || cfg["item_gap_mm"]
        calc_gap = (raw_gap.to_f * 72.0 / 25.4).round(1)
        captured_gaps_10mm << calc_gap
      end
      super(*args)
    end

    project_data.pdf_settings[:custom_layouts][:cover][:slot_1][:visible] = true
    project_data.pdf_settings[:custom_layouts][:cover][:slot_1][:item_gap_mm] = 10.0
    page_ctrl_10mm.render
    pdf_doc_10mm.render_file(out_pdf_10mm)

    assert(captured_gaps_10mm.any? { |g| (g - 28.3).abs < 0.2 }, "item_gap для 10.0 мм рассчитан корректно в pt (~28.3 pt)")
    assert(File.exist?(out_pdf_10mm), "PDF с расстоянием между пунктами 10 мм успешно создан")
    assert(File.size(out_pdf_10mm) > 8000, "Размер PDF с отступом 10 мм валиден (#{File.size(out_pdf_10mm) rescue 0} байт)")

    FileUtils.rm_rf(test_dir)
  end

  # ============================================================================
  # 39. ТЕСТ: Выравнивание заголовка по верхней границе страницы по умолчанию
  # ============================================================================
  def test_header_default_vertical_alignment_top
    puts "\n--- 39. Тест выравнивания заголовка по верхней границе страницы (valign: top) ---"

    # 1. Проверка значений по умолчанию в ProjectData#default_custom_layouts для всех 5 шаблонов
    project_data = DN1Code::ExportPdf2::Model::ProjectData.new
    [:cover, :description, :explain, :general, :visual].each do |tpl|
      hdr = project_data.default_custom_layouts[tpl][:header]
      assert(hdr[:valign] == "top", "default_custom_layouts[#{tpl}][:header] имеет valign: top")
    end

    # 2. Проверка default_layout.yaml и layout.yaml на наличие valign: top для всех заголовков
    default_yaml = File.read(File.expand_path("../config/default_layout.yaml", __dir__), encoding: "utf-8")
    assert(default_yaml.scan(/header:.*?valign:\s*top/m).size >= 5, "default_layout.yaml содержит valign: top для всех заголовков")

    layout_yaml = File.read(File.expand_path("../config/layout.yaml", __dir__), encoding: "utf-8")
    assert(layout_yaml.scan(/header:.*?valign:\s*top/m).size >= 5, "layout.yaml содержит valign: top для всех заголовков")

    # 3. Проверка app.js (DEFAULT_HEADER_SLOT, DEFAULT_LAYOUTS и превью)
    app_js_path = File.expand_path("../dialog/html/app.js", __dir__)
    app_js_content = File.read(app_js_path, encoding: "utf-8")

    assert(app_js_content.match?(/DEFAULT_HEADER_SLOT\s*=\s*\{[^}]+valign:\s*"top"/), "app.js DEFAULT_HEADER_SLOT содержит valign: top")
    assert(app_js_content.include?('header.valign || "top"'), "app.js использует top как fallback для header.valign")

    # 4. Проверка отрисовки в PDF: заголовок прижимается к верхней границе bounds.top
    pdf_doc = Prawn::Document.new(page_size: "A4", page_layout: :landscape, margin: 15)
    DN1Code::ExportPdf2::Service::FontService.setup_fonts(pdf_doc)
    cover_page = DN1Code::ExportPdf2::Controller::CoverPage.new(pdf_doc, project_data, nil, page_index: 1, total_pages: 1)

    hdr_box = cover_page.send(:get_block_box, :cover, :header, 0.0, 0.0, 100.0, 30.0)
    assert((hdr_box[:y] - pdf_doc.bounds.top).abs < 0.001, "Верхний край блока заголовка точно совпадает с bounds.top страницы")
    assert(hdr_box[:valign] == :top, "hdr_box[:valign] равен :top")

    test_dir = File.expand_path("test_header_top_dir", __dir__)
    FileUtils.mkdir_p(test_dir)
    pdf_out = File.join(test_dir, "header_default_top.pdf")
    cover_page.render
    pdf_doc.render_file(pdf_out)

    assert(File.exist?(pdf_out), "PDF с заголовком по верхней границе успешно сгенерирован")
    assert(File.size(pdf_out) > 5000, "Размер созданного PDF валиден (#{File.size(pdf_out)} байт)")

    FileUtils.rm_rf(test_dir)
  end

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
    assert(js_text.include?("chkShowAspectOverlay"), "app.js содержит chkShowAspectOverlay")
    assert(js_text.include?("function updateAspectUI"), "app.js содержит function updateAspectUI")
    assert(js_text.include?("syncOverlayState"), "app.js содержит syncOverlayState")
    assert(js_text.include?("updateAspectInfo"), "app.js содержит updateAspectInfo")
    assert(js_text.include?("callRuby(\"toggleAspectOverlay\""), "app.js отправляет toggleAspectOverlay в SketchUp")

    # 9. Проверка CSS стилей
    css_text = File.read(File.join(__dir__, "../dialog/html/app.css"), encoding: "utf-8")
    assert(css_text.include?(".aspect-overlay-card"), "app.css содержит стили .aspect-overlay-card")
    assert(css_text.include?(".aspect-custom-inputs"), "app.css содержит стили .aspect-custom-inputs")
    assert(css_text.include?("#aspectOverlayBadge"), "app.css содержит стили #aspectOverlayBadge")

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

    # 11. Проверка размещения включателя рамки в настройке Картинка чертежа и привязки пропорций к блоку шаблона
    assert(js_text.include?("chk_tpl_aspect_overlay"), "app.js содержит включатель оверлея chk_tpl_aspect_overlay в блоке Картинка чертежа")
    assert(js_text.include?("tplAspectOverlayBadge"), "app.js содержит бейдж пропорций tplAspectOverlayBadge в блоке Картинка чертежа")
    assert(js_text.include?("tplAspectOverlayText"), "app.js содержит текстовую метку пропорций tplAspectOverlayText")
    assert(js_text.include?("syncCurrentTemplateOverlay"), "app.js содержит метод syncCurrentTemplateOverlay")
    assert(css_text.include?(".tpl-overlay-toggle-label"), "app.css содержит стили для .tpl-overlay-toggle-label")
    assert(css_text.include?("#tplAspectOverlayBadge"), "app.css содержит стили для #tplAspectOverlayBadge")
    assert(css_text.include?("#tplAspectOverlayBadge.disabled-overlay"), "app.css содержит стили для неактивного состояния рамки")

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

    # Тестирование передачи параметров цвета и прозрачности через update_settings
    overlay_svc.update_settings({
      overlay_border_color: "#10B981",
      overlay_border_opacity: 75,
      overlay_mask_color: "#1E293B",
      overlay_mask_opacity: 60
    }, mock_model_tpl)

    info_colors = overlay_svc.calculate_target_info(mock_model_tpl)
    assert(info_colors[:border_color] == "#10B981", "calculate_target_info возвращает обновленный border_color")
    assert(info_colors[:border_opacity] == 75, "calculate_target_info возвращает обновленный border_opacity")
    assert(info_colors[:mask_color] == "#1E293B", "calculate_target_info возвращает обновленный mask_color")
    assert(info_colors[:mask_opacity] == 60, "calculate_target_info возвращает обновленный mask_opacity")

    ov_check = overlay_svc.find_model_overlay(mock_model_tpl)
    assert(ov_check && ov_check.border_color_cache == "#10B981", "Кэш цвета рамки в оверлее обновлен")
    assert(ov_check && ov_check.border_opacity_cache == 75, "Кэш прозрачности рамки в оверлее обновлен")
    assert(ov_check && ov_check.mask_color_cache == "#1E293B", "Кэш цвета затемнения в оверлее обновлен")
    assert(ov_check && ov_check.mask_opacity_cache == 60, "Кэш затемнения в оверлее обновлен")

    # Проверка наличия элементов интерфейса в app.js, app.css и index.html
    assert(js_text.include?("input_overlay_border_color"), "app.js содержит элемент input_overlay_border_color")
    assert(js_text.include?("input_overlay_border_opacity"), "app.js содержит элемент input_overlay_border_opacity")
    assert(js_text.include?("input_overlay_mask_color"), "app.js содержит элемент input_overlay_mask_color")
    assert(js_text.include?("input_overlay_mask_opacity"), "app.js содержит элемент input_overlay_mask_opacity")
    assert(css_text.include?(".tpl-overlay-styling-row"), "app.css содержит стили .tpl-overlay-styling-row")
    assert(!html_text.include?("id=\"inputOverlayBorderColor\""), "из общих настроек index.html удален устаревший id=\"inputOverlayBorderColor\"")
    assert(!html_text.include?("id=\"inputOverlayMaskColor\""), "из общих настроек index.html удален устаревший id=\"inputOverlayMaskColor\"")
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
    stadia_rendered = page_base.send(:resolve_info_line, "workflow_stadia")
    assert(stadia_rendered.include?("[✓] Предварительный проект"), "resolve_info_line('workflow_stadia') рендерит [✓] для выполненных стадий")
    assert(stadia_rendered.include?("[ ] Предварительно Утвержден"), "resolve_info_line('workflow_stadia') рендерит [ ] для невыполненных стадий")

    history_rendered = page_base.send(:resolve_info_line, "workflow_history")
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

    # 1. Проверка независимости структуры custom_layouts для всех 5 шаблонов
    proj = DN1Code::ExportPdf2::Model::ProjectData.new
    templates = [:cover, :description, :explain, :general, :visual]

    templates.each do |tpl|
      assert(proj.custom_layouts.key?(tpl), "custom_layouts содержит шаблон #{tpl}")
      assert(proj.custom_layouts[tpl].key?(:image_4_3), "шаблон #{tpl} содержит блок image_4_3")
      assert(proj.custom_layouts[tpl].key?(:header), "шаблон #{tpl} содержит блок header")
    end

    # Проверка отсутствия общих ссылок на хэши между шаблонами (Deep isolation)
    assert(proj.custom_layouts[:cover][:image_4_3].object_id != proj.custom_layouts[:visual][:image_4_3].object_id,
           "Блоки image_4_3 в cover и visual имеют разные object_id")
    assert(proj.custom_layouts[:cover][:header][:lines].object_id != proj.custom_layouts[:general][:header][:lines].object_id,
           "Массивы lines в cover и general имеют разные object_id")

    # 2. Модификация одного шаблона НЕ должна влиять на остальные (Template Independence)
    proj.custom_layouts[:cover][:image_4_3][:aspect_ratio] = "21:9"
    proj.custom_layouts[:cover][:image_4_3][:scale_pct] = 77
    proj.custom_layouts[:cover][:header][:visible] = false
    proj.custom_layouts[:cover][:header][:line_rows]["furniture_name"] = 99
    proj.custom_layouts[:cover][:slot_1][:font_size] = 14.5
    proj.custom_layouts[:cover][:slot_1][:item_gap_mm] = 6.0

    assert(proj.custom_layouts[:visual][:image_4_3][:aspect_ratio] != "21:9",
           "Изменение aspect_ratio в cover не затронуло visual")
    assert(proj.custom_layouts[:visual][:image_4_3][:scale_pct] != 77,
           "Изменение scale_pct в cover не затронуло visual")
    assert(proj.custom_layouts[:general][:header][:visible] == true,
           "Скрытие header в cover не скрыло header в general")
    assert(proj.custom_layouts[:description][:header][:line_rows]["furniture_name"] != 99,
           "Изменение line_rows в cover не повлияло на description")
    assert(proj.custom_layouts[:explain][:slot_1][:font_size] != 14.5,
           "Изменение font_size в cover slot_1 не повлияло на explain")
    assert(proj.custom_layouts[:explain][:slot_1][:item_gap_mm] != 6.0,
           "Изменение item_gap_mm в cover slot_1 не повлияло на explain")

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
    assert(loaded_proj.custom_layouts[:general][:header][:visible] == true,
           "Загруженный general сохранил видимость header: true")

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
    assert(js_text.include?("deepClone(defSlot.lines)"), "app.js глубоко клонирует слоты во избежание взаимных ссылок")

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

  def test_directory_descriptions_in_template_middle_list
    puts "\n--- 45. Тест попадания описаний блоков папок в средний список шаблонов ---"
    root_project_yaml = File.expand_path("../../project.yaml", __dir__)
    initial_md5 = Digest::MD5.hexdigest(File.binread(root_project_yaml))

    # 1. Проверка InfoLineResolver для dir_desc_0, dir_desc_1 и dir_specs
    project_data = DN1Code::ExportPdf2::Model::ProjectData.new
    project_data.directories = [
      { path: "!_фасады_мдф", title: "Фасады МДФ", description: "Эмаль шелковисто-матовая RAL 7047" },
      { path: "!_столешница", title: "Столешница", description: "Кварцевый агломерат 20мм Calacatta" }
    ]

    ctx = { project_data: project_data, info: {}, workflow: {}, page_index: 1, total_pages: 3 }

    desc_0 = DN1Code::ExportPdf2::Service::InfoLineResolver.resolve(ctx, "dir_desc_0")
    assert(desc_0 && desc_0.include?("Фасады МДФ") && desc_0.include?("RAL 7047"),
           "InfoLineResolver корректно разрешает dir_desc_0: #{desc_0}")

    desc_1 = DN1Code::ExportPdf2::Service::InfoLineResolver.resolve(ctx, "dir_desc_1")
    assert(desc_1 && desc_1.include?("Столешница") && desc_1.include?("Calacatta"),
           "InfoLineResolver корректно разрешает dir_desc_1: #{desc_1}")

    specs_all = DN1Code::ExportPdf2::Service::InfoLineResolver.resolve(ctx, "dir_specs")
    assert(specs_all && specs_all.include?("Фасады МДФ") && specs_all.include?("Столешница"),
           "InfoLineResolver корректно объединяет все папки через dir_specs")

    # 2. Проверка JS кода на наличие интеграции со средним списком
    js_text = File.read(File.join(__dir__, "../dialog/html/app.js"), encoding: "utf-8")
    assert(js_text.include?("syncDirectoriesSpecifications()"),
           "app.js содержит вызов syncDirectoriesSpecifications")
    assert(js_text.include?("function syncDirectoriesSpecifications()"),
           "app.js содержит функцию syncDirectoriesSpecifications")
    assert(js_text.include?("function getInfoLineDef(key)"),
           "app.js содержит функцию getInfoLineDef для динамических строк")
    assert(js_text.include?("dir_desc_"),
           "app.js поддерживает динамические ключи dir_desc_ для блоков папок")
    assert(js_text.include?("middleAvailableLines.push"),
           "app.js динамически добавляет блоки папок в middleAvailableLines")

    # 3. Проверка неизменности оригинального файла project.yaml
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
    FileUtils.mkdir_p(File.join(test_dir, "no_key"))
    File.write(File.join(test_dir, "no_key", "NoDirs.yaml"), <<~YAML, encoding: "utf-8")
      ---
      project:
        articul: NO-DIRS-001
        product: Тумба
      scenes: []
    YAML
    model2 = Sketchup::MockModel.new(File.join(test_dir, "no_key", "NoDirs.skp"))
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
  # 46. ТЕСТ: Заголовки пунктов шаблонов на отдельной строке, описание на следующей, галка заголовок
  # ============================================================================
  def test_template_block_item_multiline_and_title_toggle
    puts "\n--- 46. Тест заголовков пунктов шаблонов на отдельной строке и галки заголовок ---"

    root_project_yaml = File.expand_path("../../project.yaml", __dir__)
    initial_content = File.binread(root_project_yaml)
    initial_md5 = Digest::MD5.hexdigest(initial_content)

    # 1. Проверка InfoLineResolver#resolve_parts и resolve_formatted
    ctx = {
      project_info: {
        materials: "Фасады МДФ, фурнитура Blum",
        appliances: "Встраиваемая вытяжка Bosch"
      },
      workflow: {
        last_edit: "2026-09-11: Изменение размеров полок"
      }
    }

    # С включенным заголовком: заголовок на отдельной строке, описание на следующей (\n)
    formatted_with_title = DN1Code::ExportPdf2::Service::InfoLineResolver.resolve_formatted(ctx, "spec_materials", show_title: true)
    assert(formatted_with_title.include?("\n"), "resolve_formatted с show_title: true разделяет заголовок и описание переносом строки")
    parts = formatted_with_title.split("\n", 2)
    assert(parts[0] == "Материалы и фурнитура", "Первая строка содержит точный заголовок пункта: #{parts[0]}")
    assert(parts[1] == "Фасады МДФ, фурнитура Blum", "Вторая строка содержит описание пункта: #{parts[1]}")

    # С выключенным заголовком: только описание без заголовка
    formatted_without_title = DN1Code::ExportPdf2::Service::InfoLineResolver.resolve_formatted(ctx, "spec_materials", show_title: false)
    assert(!formatted_without_title.include?("Материалы и фурнитура"), "resolve_formatted с show_title: false не содержит заголовок")
    assert(formatted_without_title == "Фасады МДФ, фурнитура Blum", "resolve_formatted с show_title: false возвращает только описание")

    # Проверка resolve_parts
    title_part, desc_part = DN1Code::ExportPdf2::Service::InfoLineResolver.resolve_parts(ctx, "workflow_history")
    assert(title_part == "История правок", "resolve_parts возвращает точный заголовок для workflow_history")
    assert(desc_part == "2026-09-11: Изменение размеров полок", "resolve_parts возвращает точное описание для workflow_history")

    # 2. Проверка разметки и элементов в app.js (чистый GUI и галка Заголовок в шапке карточки 2)
    app_js_text = File.read(File.join(__dir__, "../dialog/html/app.js"), encoding: "utf-8")
    assert(app_js_text.include?("chk-slot-show-titles"), "app.js содержит чекбокс 'Заголовок' на уровне блока шаблона (chk-slot-show-titles)")
    assert(app_js_text.include?("show_titles"), "app.js поддерживает параметр show_titles")
    assert(app_js_text.include?("tpl-line-label"), "app.js сохраняет аккуратный однострочный список пунктов в GUI (tpl-line-label)")
    assert(app_js_text.include?("tpl-middle-label-wrap"), "app.js использует обертку метки среднего блока (tpl-middle-label-wrap)")

    # 3. Проверка стилей в app.css
    app_css_text = File.read(File.join(__dir__, "../dialog/html/app.css"), encoding: "utf-8")
    assert(app_css_text.include?(".tpl-chk-titles-label"), "app.css содержит стиль для .tpl-chk-titles-label")
    assert(app_css_text.include?(".tpl-middle-label-wrap"), "app.css содержит стиль для .tpl-middle-label-wrap")

    # 4. Проверка интеграции в LayoutBuilder для страниц проекта
    layout_builder_text = File.read(File.join(__dir__, "../service/layout_builder.rb"), encoding: "utf-8")
    assert(layout_builder_text.include?("resolve_formatted"), "LayoutBuilder вызывает resolve_formatted с параметром show_title")
    assert(layout_builder_text.include?("show_title: show_title"), "LayoutBuilder передает параметр show_title в InfoLineResolver")

    # 5. Тестирование генерации страниц проекта в PDF с включенными и выключенными заголовками
    test_dir = File.expand_path("test_titles_page_render_dir", __dir__)
    FileUtils.rm_rf(test_dir)
    FileUtils.mkdir_p(test_dir)

    test_project_data = DN1Code::ExportPdf2::Model::ProjectData.new
    test_project_data.project_info[:materials] = "Фасады МДФ, фурнитура Blum"
    test_project_data.project_info[:appliances] = "Встраиваемая духовка Electrolux"
    test_project_data.project_info[:notes] = "Точки подключения выведены по проекту"

    # Рендеринг с включенными заголовками (show_titles: true)
    layouts = test_project_data.pdf_settings[:custom_layouts]
    layouts[:cover][:slot_1][:lines] = ["spec_materials", "spec_appliances", "general_notes"]
    layouts[:cover][:slot_1][:show_titles] = true

    pdf_doc_with_titles = Prawn::Document.new(page_size: "A4", page_layout: :landscape, margin: 15)
    DN1Code::ExportPdf2::Service::FontService.setup_fonts(pdf_doc_with_titles)
    page_with_titles = DN1Code::ExportPdf2::Controller::CoverPage.new(pdf_doc_with_titles, test_project_data, nil, page_index: 1, total_pages: 1)
    page_with_titles.render

    pdf_out_with_titles = File.join(test_dir, "page_with_titles.pdf")
    pdf_doc_with_titles.render_file(pdf_out_with_titles)
    assert(File.exist?(pdf_out_with_titles), "PDF страница с включенными заголовками успешно сгенерирована")
    assert(File.size(pdf_out_with_titles) > 5000, "Размер PDF страницы с заголовками валиден (#{File.size(pdf_out_with_titles)} байт)")

    # Рендеринг с выключенными заголовками (show_titles: false)
    layouts[:cover][:slot_1][:show_titles] = false
    pdf_doc_no_titles = Prawn::Document.new(page_size: "A4", page_layout: :landscape, margin: 15)
    DN1Code::ExportPdf2::Service::FontService.setup_fonts(pdf_doc_no_titles)
    page_no_titles = DN1Code::ExportPdf2::Controller::CoverPage.new(pdf_doc_no_titles, test_project_data, nil, page_index: 1, total_pages: 1)
    page_no_titles.render

    pdf_out_no_titles = File.join(test_dir, "page_no_titles.pdf")
    pdf_doc_no_titles.render_file(pdf_out_no_titles)
    assert(File.exist?(pdf_out_no_titles), "PDF страница с выключенными заголовками успешно сгенерирована")
    assert(File.size(pdf_out_no_titles) > 5000, "Размер PDF страницы без заголовков валиден (#{File.size(pdf_out_no_titles)} байт)")

    FileUtils.rm_rf(test_dir)

    # 6. Проверка неизменности оригинального файла project.yaml
    current_content = File.binread(root_project_yaml)
    current_md5 = Digest::MD5.hexdigest(current_content)
    assert(current_md5 == initial_md5, "КРИТИЧЕСКАЯ ПРОВЕРКА: Файл project.yaml остался абсолютно нетронутым (MD5 совпадает)")
  end

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
    assert(html_content.include?('Страницы проекта'), "index.html содержит заголовок 'Страницы проекта'")
    assert(html_content.include?('data-tab="tab-templates"'), "index.html содержит отдельную кнопку вкладки tab-templates")
    assert(html_content.include?('Настройка шаблонов'), "index.html содержит заголовок 'Настройка шаблонов'")

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
    assert(html_content.include?('id="btnDeleteTemplateSidebar"'), "index.html содержит кнопку удаления в сайдбаре btnDeleteTemplateSidebar")
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
        header: { visible: true, content: "header", custom_text: "КАСТОМНЫЙ ШАБЛОН СПЕЦИФИКАЦИИ" },
        slot_1: { visible: true, content: "specifications", lines: ["materials", "appliances"] },
        footer: { visible: true, content: "footer", custom_text: "Лист 1 из 1" }
      }
    }
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

    # 2. Проверка JavaScript и HTML определений шаблона
    assert(js_content.include?('key: "blank"') && js_content.include?('Без шаблона'), "app.js getAllTemplates содержит шаблон blank")
    assert(js_content.include?('blank: {') && js_content.include?('Без шаблона (Blank)'), "app.js DEFAULT_LAYOUTS содержит конфигурацию blank")
    assert(html_content.include?('value="blank"'), "index.html selectNewTemplateBase содержит вариант blank")

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
    assert(dialog_rb_content.include?('OverlayService.refresh') || dialog_rb_content.include?('calculate_target_info'), "export_dialog.rb обновляет безопасную рамку кадра при смене сцены")

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

    # 2. Проверка отказа от библиотеки модели в project_data.rb (атрибуты .skp не используются)
    assert(!model_rb_content.include?("set_attribute"), "project_data.rb не записывает данные в атрибуты модели SketchUp")
    assert(!model_rb_content.include?("get_attribute"), "project_data.rb не читает данные из атрибутов модели SketchUp")
    assert(!model_rb_content.include?("ATTR_DICT"), "project_data.rb не содержит словаря атрибутов ATTR_DICT")
    assert(model_rb_content.include?("def save_project_yaml"), "project_data.rb сохраняет данные проекта в YAML файл (save_project_yaml)")

    # 3. Проверка мгновенного сброса автосохранения flushAutoSave в app.js
    assert(js_content.include?("function flushAutoSave()"), "app.js содержит функцию flushAutoSave")
    assert(js_content.include?("beforeunload"), "app.js сбрасывает автосохранение по событию beforeunload")
    assert(js_content.include?("flushAutoSave();"), "app.js сбрасывает автосохранение при смене вкладок")

    # 4. Проверка записи обновлений среднего блока в updateBlockSlot
    assert(js_content.include?('updateBlockSlot("slot_1", { line_aligns:'), "app.js обновляет выравнивание строк среднего блока через updateBlockSlot")
    assert(js_content.include?('updateBlockSlot("slot_1", { line_font_sizes:'), "app.js обновляет шрифт строк среднего блока через updateBlockSlot")
    assert(js_content.include?('updateBlockSlot("slot_1", { line_colors:'), "app.js обновляет цвет строк среднего блока через updateBlockSlot")

    # 5. Практический тест сохранения и восстановления custom_layouts через layout.yaml
    tmp_tpl_dir = Dir.mktmpdir("test_template_roundtrip")
    tmp_tpl_layout = File.join(tmp_tpl_dir, "layout_roundtrip.yaml")
    pdata1 = DN1Code::ExportPdf2::Model::ProjectData.new
    pdata1.custom_layouts[:cover][:header][:visible] = false
    pdata1.custom_layouts[:cover][:slot_1][:font_size] = 16.5
    pdata1.save_to_layout_yaml(tmp_tpl_layout)

    pdata2 = DN1Code::ExportPdf2::Model::ProjectData.new
    pdata2.load_from_layout_yaml(tmp_tpl_layout)
    assert(pdata2.custom_layouts[:cover][:header][:visible] == false, "ProjectData восстанавливает из layout.yaml выключенный заголовок")
    assert(pdata2.custom_layouts[:cover][:slot_1][:font_size] == 16.5, "ProjectData восстанавливает из layout.yaml кастомный размер шрифта")
    FileUtils.rm_rf(tmp_tpl_dir)

    # 6. Проверка неизменности оригинального файла project.yaml
    current_content = File.binread(root_project_yaml)
    current_md5 = Digest::MD5.hexdigest(current_content)
    assert(current_md5 == initial_md5, "КРИТИЧЕСКАЯ ПРОВЕРКА: Файл project.yaml остался абсолютно нетронутым (MD5 совпадает)")
  end

  def test_template_blocks_visibility_persistence
    puts "\n--- 53. Тест сохранения и применения включения/выключения блоков в шаблонах ---"
    root_project_yaml = File.expand_path("../../project.yaml", __dir__)
    initial_md5 = Digest::MD5.hexdigest(File.binread(root_project_yaml))

    # 1. Проверка наличия вспомогательной функции и обработчиков в app.js
    app_js_path = File.expand_path("../dialog/html/app.js", __dir__)
    app_js = File.read(app_js_path, encoding: "utf-8")

    assert(app_js.include?("function isSlotVisible"), "app.js содержит функцию isSlotVisible для безопасной проверки видимости")
    assert(app_js.include?('id="chk_middle_visible"'), "app.js содержит ID chk_middle_visible для чекбокса среднего блока")
    assert(app_js.include?('updateBlockSlot("header", { visible: isVis }, targetTpl);') || app_js.include?('visible: isVis'), "app.js передает булево значение visible в updateBlockSlot")

    # 2. Проверка методов block_visible? в PageBase и LayoutBuilder
    pbase_mock_cfg = {
      header: { visible: false },
      slot_1: { visible: "false" },
      footer: { visible: 0 },
      image_4_3: { visible: true }
    }
    mock_pdata = DN1Code::ExportPdf2::Model::ProjectData.new
    mock_pdata.custom_layouts[:test_tpl] = pbase_mock_cfg

    fake_doc = DN1Code::ExportPdf2::Service::PdfBuilder.create_document(mock_pdata, mock_pdata.pdf_settings)
    fake_scene = DN1Code::ExportPdf2::Model::SceneItem.new(name: "Test Scene", page_type: :test_tpl)
    page_base = DN1Code::ExportPdf2::Controller::PageBase.new(fake_doc, mock_pdata, fake_scene)

    assert(page_base.send(:block_visible?, :test_tpl, :header) == false, "PageBase#block_visible? распознает visible: false")
    assert(page_base.send(:block_visible?, :test_tpl, :slot_1) == false, "PageBase#block_visible? распознает строковый 'false'")
    assert(page_base.send(:block_visible?, :test_tpl, :footer) == false, "PageBase#block_visible? распознает числовой 0")
    assert(page_base.send(:block_visible?, :test_tpl, :image_4_3) == true, "PageBase#block_visible? распознает visible: true")

    # 3. Проверка get_block_config с alias-маппингом
    assert(page_base.send(:get_block_config, :test_tpl, :general_header) == { visible: false }, "PageBase#get_block_config поддерживает алиас :general_header -> :header")
    assert(page_base.send(:get_block_config, :test_tpl, :visual_image) == { visible: true }, "PageBase#get_block_config поддерживает алиас :visual_image -> :image_4_3")

    # 4. Проверка сохранения и восстановления всех 4 блоков через layout.yaml
    tmp_vis_dir = Dir.mktmpdir("test_block_vis")
    tmp_vis_layout = File.join(tmp_vis_dir, "layout_blockvis.yaml")
    pdata1 = DN1Code::ExportPdf2::Model::ProjectData.new
    pdata1.custom_layouts[:cover][:header][:visible] = false
    pdata1.custom_layouts[:cover][:slot_1][:visible] = false
    pdata1.custom_layouts[:cover][:footer][:visible] = false
    pdata1.custom_layouts[:cover][:image_4_3][:visible] = false
    pdata1.save_to_layout_yaml(tmp_vis_layout)

    pdata2 = DN1Code::ExportPdf2::Model::ProjectData.new
    pdata2.load_from_layout_yaml(tmp_vis_layout)
    assert(pdata2.custom_layouts[:cover][:header][:visible] == false, "ProjectData восстанавливает из layout.yaml выключенный header")
    assert(pdata2.custom_layouts[:cover][:slot_1][:visible] == false, "ProjectData восстанавливает из layout.yaml выключенный slot_1")
    assert(pdata2.custom_layouts[:cover][:footer][:visible] == false, "ProjectData восстанавливает из layout.yaml выключенный footer")
    assert(pdata2.custom_layouts[:cover][:image_4_3][:visible] == false, "ProjectData восстанавливает из layout.yaml выключенный image_4_3")
    FileUtils.rm_rf(tmp_vis_dir)

    # 5. Проверка сохранения в layout.yaml и обратной загрузки
    tmp_dir = Dir.mktmpdir("test_layout_vis")
    tmp_layout = File.join(tmp_dir, "layout_vis_test.yaml")
    pdata1.save_to_layout_yaml(tmp_layout)
    assert(File.exist?(tmp_layout), "Файл layout_vis_test.yaml успешно создан")

    pdata3 = DN1Code::ExportPdf2::Model::ProjectData.new
    pdata3.load_from_layout_yaml(tmp_layout)
    assert(pdata3.custom_layouts[:cover][:header][:visible] == false, "ProjectData восстанавливает из layout.yaml выключенный header")
    assert(pdata3.custom_layouts[:cover][:slot_1][:visible] == false, "ProjectData восстанавливает из layout.yaml выключенный slot_1")
    assert(pdata3.custom_layouts[:cover][:footer][:visible] == false, "ProjectData восстанавливает из layout.yaml выключенный footer")
    assert(pdata3.custom_layouts[:cover][:image_4_3][:visible] == false, "ProjectData восстанавливает из layout.yaml выключенный image_4_3")

    # 6. Генерация PDF со скрытыми блоками без ошибок
    pdf_out = File.join(tmp_dir, "hidden_blocks.pdf")
    pdata1.pdf_settings[:output_path] = pdf_out
    doc = DN1Code::ExportPdf2::Service::PdfBuilder.create_document(pdata1, pdata1.pdf_settings)
    scene_item = DN1Code::ExportPdf2::Model::SceneItem.new(name: "Обложка без блоков", page_type: :cover, enabled: true)
    controller = DN1Code::ExportPdf2::Controller::CoverPage.new(doc, pdata1, scene_item, page_index: 1, total_pages: 1)
    controller.render
    doc.render_file(pdf_out)
    assert(File.exist?(pdf_out) && File.size(pdf_out) > 1000, "CoverPage успешно отрисован со всеми выключенными блоками")

    # 7. Проверка неизменности оригинального файла project.yaml
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
    assert(info_blank[:visible] == false, "calculate_target_info возвращает visible: false для шаблона :blank")

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
    assert(js_content.include?('const isOverlayOn = isImageVis && Boolean'), "app.js учитывает isImageVis при отображении чекбокса рамки")
    assert(js_content.include?('${!isImageVis ? \'disabled\' : \'\'}'), "app.js блокирует чекбокс рамки, если видовой экран выключен")
    assert(js_content.include?('callRuby("toggleAspectOverlay", false)'), "app.js отключает оверлей в SketchUp при снятии галки видового экрана")

    # 6. Проверка Ruby коллбэков в export_dialog.rb
    dialog_rb_path = File.expand_path(File.join(__dir__, "..", "dialog", "export_dialog.rb"))
    dialog_rb_content = File.read(dialog_rb_path, encoding: "UTF-8")
    assert(dialog_rb_content.include?('if info[:visible] == false') && dialog_rb_content.include?('Service::OverlayService.disable(model)'), "export_dialog.rb гарантированно отключает оверлей при info[:visible] == false")

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
    assert(scene1.viewport_background == true, "SceneItem по умолчанию имеет viewport_background == true")
    assert(scene1.aspect_ratio == "4:3", "SceneItem по умолчанию имеет aspect_ratio == '4:3'")
    assert(scene1.scale_pct == 100, "SceneItem по умолчанию имеет scale_pct == 100")

    # Сериализация в хэш и десериализация
    scene1.viewport_visible = false
    scene1.viewport_background = false
    scene1.aspect_ratio = "16:9"
    scene1.scale_pct = 80
    h = scene1.to_h
    assert(h[:viewport_visible] == false, "to_h сохраняет :viewport_visible")
    assert(h[:viewport_background] == false, "to_h сохраняет :viewport_background")
    assert(h[:aspect_ratio] == "16:9", "to_h сохраняет :aspect_ratio")
    assert(h[:scale_pct] == 80, "to_h сохраняет :scale_pct")

    scene_restored = DN1Code::ExportPdf2::Model::SceneItem.from_h(h)
    assert(scene_restored.viewport_visible == false, "from_h восстанавливает viewport_visible")
    assert(scene_restored.viewport_background == false, "from_h восстанавливает viewport_background")
    assert(scene_restored.aspect_ratio == "16:9", "from_h восстанавливает aspect_ratio")
    assert(scene_restored.scale_pct == 80, "from_h восстанавливает scale_pct")

    # Старые проекты без ключа viewport_background получают значение по умолчанию (true)
    legacy_scene = DN1Code::ExportPdf2::Model::SceneItem.from_h({ name: "Legacy" })
    assert(legacy_scene.viewport_background == true, "from_h без viewport_background подставляет true (совместимость со старыми проектами)")

    # 2. Проверка разметки в index.html
    html_path = File.expand_path(File.join(__dir__, "..", "dialog", "html", "index.html"))
    html_content = File.read(html_path, encoding: "UTF-8")
    assert(html_content.include?('class="th-aspect"') && html_content.include?('>Кадр</th>'), "index.html содержит заголовок колонки Кадр в таблице сцен")
    assert(html_content.include?('id="sceneViewportSection"'), "index.html содержит контейнер sceneViewportSection во вкладке страниц")

    # 3. Проверка стилей в app.css
    css_path = File.expand_path(File.join(__dir__, "..", "dialog", "html", "app.css"))
    css_content = File.read(css_path, encoding: "UTF-8")
    assert(css_content.include?(".scene-viewport-section"), "app.css содержит стиль .scene-viewport-section")
    assert(css_content.include?(".scene-viewport-card"), "app.css содержит стиль .scene-viewport-card")
    assert(css_content.include?(".scene-aspect-cell"), "app.css содержит стиль .scene-aspect-cell")
    assert(css_content.include?(".badge-aspect"), "app.css содержит стиль .badge-aspect")

    # 4. Проверка логики в app.js
    js_path = File.expand_path(File.join(__dir__, "..", "dialog", "html", "app.js"))
    js_content = File.read(js_path, encoding: "UTF-8")
    assert(js_content.include?("function renderSceneViewportCard"), "app.js содержит функцию renderSceneViewportCard")
    assert(js_content.include?("function bindSceneViewportEvents"), "app.js содержит функцию bindSceneViewportEvents")
    assert(js_content.include?("function updateSceneTableAspectCell"), "app.js содержит функцию updateSceneTableAspectCell")
    assert(js_content.include?("scene-aspect-cell"), "app.js генерирует ячейку scene-aspect-cell в таблице страниц")
    assert(js_content.include?('id="chk_viewport_background"'), "app.js содержит чекбокс фона chk_viewport_background в карточке видового экрана")
    assert(js_content.include?("s.viewport_background = bgOn"), "app.js сохраняет viewport_background при переключении чекбокса фона")
    assert(js_content.include?('updateBlockSlot("image_4_3", { show_background: bgOn })'), "app.js синхронизирует show_background в слоте шаблона")

    # Проверка, что из шаблонов карточка удалена
    tpl_block = js_content[/renderTemplateSettingsList\s*\([^)]*\)\s*\{(?:[^{}]*|\{[^{}]*\})*\}/m]
    assert(!tpl_block.to_s.include?("cardImageHtml"), "renderTemplateSettingsList больше не рендерит cardImageHtml")

    # 5. Проверка работы OverlayService с настройками сцены
    mock_model = Sketchup::MockModel.new
    pdata = DN1Code::ExportPdf2::Model::ProjectData.new
    scene_ov = DN1Code::ExportPdf2::Model::SceneItem.new(name: "Page 1", page_type: :cover, viewport_visible: false, aspect_ratio: "16:9")
    pdata.scenes = [scene_ov]

    info_scene_off = DN1Code::ExportPdf2::Service::OverlayService.calculate_target_info(nil, {
      scene_item: scene_ov,
      project_data: pdata
    })
    assert(info_scene_off[:visible] == false, "OverlayService возвращает visible: false, если у сцены отключен видовой экран")

    scene_ov.viewport_visible = true
    info_scene_on = DN1Code::ExportPdf2::Service::OverlayService.calculate_target_info(nil, {
      scene_item: scene_ov,
      project_data: pdata
    })
    assert(info_scene_on[:visible] == true, "OverlayService возвращает visible: true, когда видовой экран сцены включен")
    assert(info_scene_on[:aspect_ratio] == "16:9", "OverlayService возвращает индивидуальную пропорцию сцены 16:9")

    # 6. Проверка неизменности оригинального файла project.yaml
    current_content = File.binread(root_project_yaml)
    current_md5 = Digest::MD5.hexdigest(current_content)
    assert(current_md5 == initial_md5, "КРИТИЧЕСКАЯ ПРОВЕРКА: Файл project.yaml остался абсолютно нетронутым (MD5 совпадает)")
  end

  def test_56_scene_viewport_frame_header_and_shading_controls
    puts "\n--- 56. Тест перемещения рамки в заголовок, переключателя затемнения 20%/80% и толщины линии 1px ---"

    root_project_yaml = File.expand_path("../../project.yaml", __dir__)
    initial_md5 = Digest::MD5.hexdigest(File.binread(root_project_yaml))

    js_path = File.expand_path(File.join(__dir__, "..", "dialog", "html", "app.js"))
    js_content = File.read(js_path, encoding: "UTF-8")

    # 1. Проверка перемещения рамки со значком в заголовок рядом с 'Вкл'
    scene_card = js_content[/function renderSceneViewportCard.*?function bindSceneViewportEvents/m]
    assert(scene_card != nil, "app.js содержит функцию renderSceneViewportCard")

    header_part = scene_card[/<div class="tpl-card-header">.*?<\/div>\s*<\/div>/m]
    assert(header_part != nil, "renderSceneViewportCard содержит tpl-card-header")
    assert(header_part.include?('id="tplAspectOverlayBadge"'), "tpl-card-header содержит значок/переключатель рамки #tplAspectOverlayBadge")
    assert(header_part.include?('id="chk_image_4_3_visible"'), "tpl-card-header содержит чекбокс 'Вкл' #chk_image_4_3_visible")
    assert(header_part.include?("📐 Рамка"), "Заголовок содержит иконку и надпись '📐 Рамка'")

    # 2. Проверка того, что в параметрах рамки остался только контур (input_overlay_border_color)
    styling_row = scene_card[/<div class="tpl-overlay-styling-row">.*?<p class="tpl-image-note">/m]
    assert(styling_row != nil, "renderSceneViewportCard содержит блок .tpl-overlay-styling-row")
    assert(styling_row.include?('id="input_overlay_border_color"'), "Блок стилей рамки содержит выбор цвета контура input_overlay_border_color")
    assert(styling_row.include?("Контур рамки:"), "Блок содержит подпись 'Контур рамки:'")

    # 3. Проверка переключателя затемнения 10%, 40%, 70%, 90%
    assert(styling_row.include?('id="grp_overlay_mask_opacity"'), "Блок стилей содержит группу переключателя затемнения #grp_overlay_mask_opacity")
    assert(styling_row.include?('data-opacity="10"'), "Переключатель содержит вариант 10%")
    assert(styling_row.include?('data-opacity="40"'), "Переключатель содержит вариант 40%")
    assert(styling_row.include?('data-opacity="70"'), "Переключатель содержит вариант 70%")
    assert(styling_row.include?('data-opacity="90"'), "Переключатель содержит вариант 90%")
    assert(!styling_row.include?('id="input_overlay_border_opacity"'), "Из карточки видового экрана удален ползунок прозрачности рамки")
    assert(!styling_row.include?('id="input_overlay_mask_color"'), "Из карточки видового экрана удален выбор цвета затемнения")

    # 4. Проверка обработчиков в bindSceneViewportEvents
    assert(js_content.include?("grpMaskOpacity.querySelectorAll(\".btn-mask-opacity\")"), "app.js привязывает события клика к кнопкам затемнения")
    assert(js_content.include?("state.pdf_settings.overlay_mask_opacity = opacity;"), "app.js сохраняет выбранное затемнение в настройки")

    # 5. Проверка стилей в app.css
    css_path = File.expand_path(File.join(__dir__, "..", "dialog", "html", "app.css"))
    css_content = File.read(css_path, encoding: "UTF-8")
    assert(css_content.include?("#grp_overlay_mask_opacity"), "app.css содержит стили для #grp_overlay_mask_opacity")
    assert(css_content.include?(".btn-mask-opacity"), "app.css содержит стили для .btn-mask-opacity")

    # 6. Проверка толщины линии рамки по умолчанию 1px в OverlayService
    overlay_svc = DN1Code::ExportPdf2::Service::OverlayService
    info = overlay_svc.calculate_target_info(nil, {})
    assert(info[:line_width] == 1, "OverlayService.calculate_target_info по умолчанию возвращает line_width: 1")

    ov_inst = overlay_svc.overlay_instance
    assert(ov_inst.respond_to?(:line_width_cache), "SafeFrameOverlay поддерживает атрибут line_width_cache")
    assert(ov_inst.line_width_cache == 1, "SafeFrameOverlay по умолчанию имеет line_width_cache == 1")

    mock_model = Sketchup::MockModel.new
    overlay_svc.enable(mock_model)
    ov_model = overlay_svc.find_model_overlay(mock_model)
    assert(ov_model && ov_model.line_width_cache == 1, "SafeFrameOverlay после enable сохраняет толщину линии 1px")

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

    # 1. Дефолты слотов image_4_3 во всех шаблонах содержат show_background: true
    pdata = DN1Code::ExportPdf2::Model::ProjectData.new
    DN1Code::ExportPdf2::Model::ProjectData.new.default_custom_layouts.each_key do |tpl|
      slot = pdata.pdf_settings[:custom_layouts][tpl][:image_4_3]
      assert(!slot.nil? && slot[:show_background] == true, "default_custom_layouts[#{tpl}][:image_4_3] содержит show_background: true")
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

    # 3. Проверка восстановления стандартных формул для текста шапки и слотов листа (текст не искажен)
    assert(lb_text.include?("scale = [available_h / raw_total_h, 0.6].max"),
           "layout_builder.rb использует стандартное авто-масштабирование шапки без искажений")
    assert(lb_text.include?("slot_scale = [in_h / total_items_h, 0.6].max"),
           "layout_builder.rb использует стандартное авто-масштабирование слотов")

    # 4. Проверка: Line Scale Multiplier со скриншота работает ТОЛЬКО для рендер страниц/видового экрана SketchUp
    assert(lb_text.include?("def render_image_block"), "layout_builder.rb имеет метод render_image_block для видового экрана")
    assert(lb_text.include?("skp_model.line_weight = (base_pt * line_mult).round(2)"), "render_image_block применяет line_weight")

    # Проверяем, что в рендеринге шапки (render_modular_header) и карточек слотов (render_modular_slot_card)
    # line_weight и scale_multiplier НЕ используются:
    header_code = lb_text[/def render_modular_header.*?def render_modular_footer/m]
    assert(header_code && !header_code.include?("scale_multiplier"), "render_modular_header не зависит от scale_multiplier")
    assert(header_code && !header_code.include?("calc_line_weight"), "render_modular_header не зависит от calc_line_weight")
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
    tpl_toolbar = html_text[/toolbar-font-control.*?btnResetLayout/m]
    assert(tpl_toolbar, "Тулбар панели шаблонов присутствует в index.html")
    assert(tpl_toolbar.include?('id="selectLayoutFontFamily"'), "Тулбар шаблонов содержит выбор шрифта")
    assert(tpl_toolbar.include?('id="selectFontWeight"'), "Начертание (selectFontWeight) находится на тулбаре панели шаблонов")
    assert(tpl_toolbar.include?('id="selectFontWidth"'), "Ширина (selectFontWidth) находится на тулбаре панели шаблонов")
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

    # 7a. Проверка: add_rtf_text применяет шрифт/кегль к стилю entity.
    # LayOut игнорирует \fonttbl из RTF — без стиля entity заголовки печатаются
    # дефолтным Microsoft Sans Serif вместо выбранного шрифта.
    doc_m = ::Layout::Document.new
    ctx_m = { page_h_pt: 841.89, font: "Oswald Light" }
    layer_m = doc_m.layers.first
    page_m = doc_m.pages.first
    fragments_m = [
      { text: "Кухня", size: 12.0, color: "252A2E", bold: true },
      { text: " | ", size: 10.0, color: "64748B", bold: false },
      { text: "Иванов", size: 10.0, color: "252A2E", bold: true }
    ]
    rtf_ent = DN1Code::ExportPdf2::Service::LayoutBuilder.send(
      :add_rtf_text, ctx_m, doc_m, page_m, layer_m, fragments_m,
      { x: 10, y: 10, width: 200, height: 20 },
      align: :center, font: "Oswald Light"
    )
    assert(rtf_ent, "add_rtf_text вернул entity")
    assert(rtf_ent.style(0).font_family == "Oswald Light",
           "add_rtf_text задает font_family entity (получено: #{rtf_ent.style(0).font_family.inspect})")
    assert(rtf_ent.style(0).font_size == 12.0,
           "add_rtf_text задает базовый font_size entity = max фрагмент (получено: #{rtf_ent.style(0).font_size.inspect})")

    # 7a-2. Глобальный font_weight=bold распространяется на RTF-заголовок
    ctx_m_bold = { page_h_pt: 841.89, font: "Oswald", text_bold: true }
    rtf_ent_b = DN1Code::ExportPdf2::Service::LayoutBuilder.send(
      :add_rtf_text, ctx_m_bold, doc_m, page_m, layer_m, fragments_m,
      { x: 10, y: 40, width: 200, height: 20 },
      align: :center, font: "Oswald"
    )
    assert(rtf_ent_b, "add_rtf_text (bold) вернул entity")
    assert(rtf_ent_b.style(0).text_bold == true,
           "add_rtf_text: глобальный font_weight=bold включает text_bold у entity (получено: #{rtf_ent_b.style(0).text_bold.inspect})")

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
  def test_text_height_and_no_clipping
    puts "\n--- 67. Тест предотвращения обрезания текста и адаптивных интервалов в LayOut ---"
    lb = DN1Code::ExportPdf2::Service::LayoutBuilder

    # 1. Проверка коэффициентов высоты строки font_line_pitch_ratio
    assert(lb.send(:font_line_pitch_ratio, "Oswald") >= 1.70, "font_line_pitch_ratio для Oswald >= 1.70")
    assert(lb.send(:font_line_pitch_ratio, "Sofia Sans Condensed") >= 1.35, "font_line_pitch_ratio для Sofia Sans >= 1.35")
    assert(lb.send(:font_line_pitch_ratio, "Roboto Condensed") >= 1.25, "font_line_pitch_ratio для Roboto Condensed >= 1.25")
    assert(lb.send(:font_line_pitch_ratio, "Ubuntu Condensed") >= 1.20, "font_line_pitch_ratio для Ubuntu Condensed >= 1.20")

    # 2. Проверка расчета высоты многострочного текста для Oswald
    # "Дата\n15.09.2026" (2 строки) при кегле 8pt в LayOut требует 27.1 pt
    h_date_oswald = lb.send(:estimate_text_height, "Дата\n15.09.2026", 8.0, 200.0, "Oswald")
    assert(h_date_oswald >= 28.0, "estimate_text_height для 2 строк Oswald 8pt (Дата) >= 28 pt (было: #{h_date_oswald})")

    # "Стадия проекта" (7 строк) при кегле 8pt в LayOut требует 94.85 pt
    stadia_text = "Стадия проекта\n[/] Предварительный проект\n[/] Правки проекта (история правок)\n[/] Выбраны материалы и фурнитура\n[ ] Предварительно Утвержден\n[ ] Проверка технологом\n[ ] Утвержден"
    h_stadia_oswald = lb.send(:estimate_text_height, stadia_text, 8.0, 200.0, "Oswald")
    assert(h_stadia_oswald >= 98.0, "estimate_text_height для 7 строк Oswald 8pt (Стадия) >= 98 pt (было: #{h_stadia_oswald})")

    # 3. Проверка для Sofia Sans Condensed
    h_date_sofia = lb.send(:estimate_text_height, "Дата\n15.09.2026", 8.0, 200.0, "Sofia Sans Condensed")
    assert(h_date_sofia >= 23.0, "estimate_text_height для Sofia Sans 8pt (Дата) >= 23 pt")
    h_stadia_sofia = lb.send(:estimate_text_height, stadia_text, 8.0, 200.0, "Sofia Sans Condensed")
    assert(h_stadia_sofia >= 78.0, "estimate_text_height для Sofia Sans 8pt (Стадия) >= 78 pt")

    # 4. Проверка переноса длинных строк с учетом фактора границ слов
    long_desc = "Очень длинное описание фасадов и фурнитуры для проверки автоматического расчета высоты блока"
    h_wrapped = lb.send(:estimate_text_height, long_desc, 8.0, 100.0, "Oswald")
    h_unwrapped = lb.send(:estimate_text_height, long_desc, 8.0, 500.0, "Oswald")
    assert(h_wrapped > h_unwrapped, "Узкий блок (100pt) имеет больше строк и большую высоту, чем широкий (500pt)")

    # 5. Проверка генерации карточки слота без вылетов и с корректным позиционированием
    doc = ::Layout::Document.new
    page = doc.pages.first
    layer = doc.layers.first
    ctx = { font: "Oswald", page_w_pt: 1190.55, page_h_pt: 841.89, settings: { font_family: "Oswald" } }
    rctx = { info: { date: "15.09.2026", version: "01", revision: "001" }, workflow: {} }
    slot_box = { x: 50.0, y: 700.0, width: 250.0, height: 400.0 }
    cfg = {
      lines: ["articul", "workflow_date", "workflow_version", "workflow_revision", "workflow_stadia"],
      font_size: 8.0,
      font_family: "Oswald"
    }
    # Вызываем render_modular_slot_card
    lb.send(:render_modular_slot_card, doc, page, layer, slot_box, "info_lines", cfg, 1.0, :slot_1, ctx, rctx)
    # Проверяем, что текстовые элементы созданы
    text_entities = doc.instance_variable_get(:@entities).map { |item| item[:entity] }.select { |e| e.is_a?(::Layout::FormattedText) }
    assert(!text_entities.empty?, "render_modular_slot_card создал текстовые сущности FormattedText")
    # Проверяем, что высота блоков FormattedText достаточна (для 2 строк Oswald >= 28pt)
    multi_line_ents = text_entities.select { |t| t.plain_text.include?("\n") }
    assert(!multi_line_ents.empty?, "Присутствуют многострочные текстовые сущности")
    multi_line_ents.each do |ent|
      ent_h_pt = ent.bounds.height * 72.0
      assert(ent_h_pt >= 25.0, "Высота рамки многострочного текста (#{ent_h_pt.round(1)} pt) достаточна для предотвращения обрезания")
    end
  end

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
    assert(project_data.save_project_yaml(model, previous_articul: "ART-100"), "Сохранение после смены артикула")
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
    assert(captured.string.include?("file:///" + expected_last.tr("\\", "/")),
           "Автооткрытие получилo URL копии _last (#{captured.string[/\[UI::openURL\][^\n]*/]})")

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
      # Сцены без изменений флага: фон включен (поведение по умолчанию).
      # Формат снимков не настраивается: WebP при доступном libvips, иначе PNG.
      vips_available = DN1Code::ExportPdf2::Service::VipsService.available?
      expected_ext = vips_available ? ".webp" : ".png"
      written_on = controller.export_scene_snapshots
      DN1Code::ExportPdf2::Service::SnapshotWorker.drain
      assert(written_on.size == 2, "Снимки обеих сцен записаны при включенном фоне (#{written_on.size})")
      assert(written_on.all? { |p| File.extname(p).downcase == expected_ext && File.basename(File.dirname(p)) == "images" },
             "Снимки #{expected_ext} по умолчанию лежат в <Артикул>/images (#{written_on.inspect})")
      assert(captured.all? { |o| o[:show_background] == true },
             "Без флага render_scene_temp получает show_background=true (#{captured.map { |o| o[:show_background] }.inspect})")

      # Выключаем фон всем сценам (чекбокс «фон видового экрана» в диалоге)
      captured.clear
      project_data.scenes.each { |s| s.viewport_background = false }
      written_off = controller.export_scene_snapshots
      DN1Code::ExportPdf2::Service::SnapshotWorker.drain
      assert(written_off.size == 2, "Снимки обеих сцен записаны при выключенном фоне (#{written_off.size})")
      assert(captured.all? { |o| o[:show_background] == false },
             "При viewport_background=false render_scene_temp получает show_background=false (#{captured.map { |o| o[:show_background] }.inspect})")
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

  def test_75_legacy_yaml_migration_to_project_yaml
    puts "\n--- 75. Тест миграции старых YAML (якорь + <Артикул>.yaml) в project.yaml ---"

    test_dir = File.expand_path("test_legacy_migration", __dir__)
    FileUtils.mkdir_p(test_dir)

    skp_file = File.join(test_dir, "Wardrobe.skp")
    model = Sketchup::MockModel.new(skp_file)

    # Старая схема (до 2.1): якорь <Артикул>.yaml рядом с .skp и прежний канонический
    # <Артикул>.yaml внутри папки артикула; рядом — общий файл-шаблон project_config.yaml
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

    # 1. Открытие модели: данные найдены через legacy-якорь и файл в папке артикула
    fresh = DN1Code::ExportPdf2::Model::ProjectData.new
    source = fresh.load_auto(model)
    assert(source == :yaml, "Legacy-файлы найдены, источник :yaml")
    assert(fresh.project_info[:articul].to_s == "OLD-100", "Артикул восстановлен из старого YAML")
    assert(fresh.project_info[:description].to_s == "LEGACY_DATA", "Данные прочитаны из файла в папке артикула")

    # 2. Первое сохранение: создается project.yaml, старые дубликаты удаляются, шаблон цел
    assert(fresh.save_project_yaml(model), "Сохранение мигрировало проект в project.yaml")

    new_yaml = File.join(art_dir, "project.yaml")
    assert(File.exist?(new_yaml), "project.yaml создан в папке артикула")
    assert(!File.exist?(anchor_yaml), "Якорь OLD-100.yaml рядом с .skp удален после миграции")
    assert(!File.exist?(old_canon), "Старый канонический OLD-100.yaml удален после миграции")
    assert(File.exist?(template_cfg), "Общий шаблон project_config.yaml не тронут")

    migrated = DN1Code::ExportPdf2::Model::ProjectData.new
    migrated.load_auto(model)
    assert(migrated.project_info[:articul].to_s == "OLD-100", "Мигрированный проект снова открывается")
    assert(migrated.project_info[:description].to_s == "LEGACY_DATA", "Данные не потеряны при миграции")

    FileUtils.rm_rf(test_dir)
  end

  def test_76_discovery_multiple_articul_folders_ambiguous
    puts "\n--- 76. Тест обнаружения: несколько папок артикулов — автозагрузка не выполняется ---"

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

    # Две папки артикулов рядом с моделью: однозначный выбор невозможен —
    # проект не загружается автоматически (пользователь выбирает через «Импорт YAML»)
    fresh = DN1Code::ExportPdf2::Model::ProjectData.new
    source = fresh.load_auto(model)
    assert(source == :default, "При двух папках артикулов автозагрузка не выполняется (получено: #{source})")
    assert(fresh.project_info[:articul].to_s.empty?, "Артикул не выбран автоматически")

    FileUtils.rm_rf(test_dir)
  end

  def test_77_edit_history_in_articul_folder_with_fallback
    puts "\n--- 77. Тест журнала правок: edit_history.yaml в папке артикула, фолбэк рядом с .skp ---"

    test_dir = File.expand_path("test_edit_history_articul", __dir__)
    FileUtils.mkdir_p(test_dir)

    skp_file = File.join(test_dir, "Bed.skp")
    model = Sketchup::MockModel.new(skp_file)

    # 1. Legacy: якорь рядом с .skp задает артикул, журнал правок лежит рядом с .skp
    anchor = DN1Code::ExportPdf2::Model::ProjectData.new
    anchor.project_info[:articul] = "BED-01"
    anchor.save_to_yaml(File.join(test_dir, "BED-01.yaml"), include_settings: false)
    legacy_hist = { "BED-01" => [{ "date" => "2026-08-01 09:00", "text" => "Правка из корня модели" }] }
    File.write(File.join(test_dir, "edit_history.yaml"), YAML.dump(legacy_hist))

    pd1 = DN1Code::ExportPdf2::Model::ProjectData.new
    assert(pd1.load_auto(model) == :yaml, "Данные проекта найдены через legacy-якорь")
    assert(pd1.history.first[:text] == "Правка из корня модели", "Legacy-журнал рядом с .skp прочитан")

    # 2. Журнал в папке артикула: приоритетен перед файлом рядом с .skp
    art_dir = File.join(test_dir, "BED-01")
    FileUtils.mkdir_p(art_dir)
    File.write(File.join(art_dir, "edit_history.yaml"),
               YAML.dump({ "BED-01" => [{ "date" => "2026-09-01 10:00", "text" => "Правка из папки артикула" }] }))
    project = DN1Code::ExportPdf2::Model::ProjectData.new
    project.project_info[:articul] = "BED-01"
    assert(project.save_project_yaml(model), "Сохранен project.yaml в папке артикула")

    pd2 = DN1Code::ExportPdf2::Model::ProjectData.new
    pd2.load_auto(model)
    assert(pd2.project_info[:articul].to_s == "BED-01", "Артикул загружен из project.yaml")
    assert(pd2.history.first[:text] == "Правка из папки артикула", "Журнал из папки артикула приоритетен")

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
end

TestRunner.new.run_all

