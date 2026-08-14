# frozen_string_literal: true

require "yaml"
require "json"
require "time"
require "fileutils"

module DN1Code
  module ExportPdf2
    module Model
      # Модель данных проекта: хранит информацию о проекте, сценах, истории ревизий и параметрах PDF.
      # Поддерживает двухуровневую синхронизацию: первичный источник — YAML файл рядом с SKP,
      # вторичный источник — библиотека модели (Attribute Dictionaries SketchUp).
      class ProjectData
        # Имя словаря атрибутов SketchUp для хранения данных
        ATTR_DICT = "DN1C_ExportPDF"

        # @return [Hash] метаданные и реквизиты проекта (название, заказчик, артикул, ревизия и т.д.)
        attr_accessor :project_info
        # @return [Array<SceneItem>] список сцен модели и их параметров экспорта
        attr_accessor :scenes
        # @return [Array<Hash>] история изменений и ревизий проекта
        attr_accessor :history
        # @return [Hash] параметры экспорта PDF (размер листа, поля, штамп, движок, макеты)
        attr_accessor :pdf_settings

        # Инициализирует новый экземпляр ProjectData со значениями по умолчанию
        def initialize
          @project_info = default_project_info
          @pdf_settings = default_pdf_settings
          @scenes       = []
          @history      = []
        end

        # Возвращает структуру метаданных проекта по умолчанию с пустыми полями
        # @return [Hash] хэш с параметрами проекта
        def default_project_info
          {
            room_name:        "",
            furniture_name:   "",
            name_project:     "",
            description:      "",
            name_customer:    "",
            phone:            "",
            email:            "",
            address:          "",
            articul:          "",
            version:          1,
            revision:         1,
            status:           "В РАБОТЕ",
            task_description: "",
            task_dimensions:  "",
            task_wishes:      "",
            materials:        "",
            appliances:       "",
            lighting:         "",
            notes:            "",
            edit:             ""
          }
        end

        # Возвращает конфигурацию визуальных блоков макета страниц по умолчанию (в процентах)
        # @return [Hash] хэш с координатами и свойствами блоков для каждого типа страницы
        def default_custom_layouts
          {
            cover: {
              cover_accent_bar:   { x: 0.0, y: 0.0, w: 100.0, h: 1.5, visible: true },
              cover_articul:      { x: 65.0, y: 2.5, w: 35.0, h: 4.0, visible: true, align: "right" },
              cover_title:        { x: 0.0, y: 3.5, w: 65.0, h: 8.0, visible: true, align: "left" },
              cover_subtitle:     { x: 0.0, y: 11.5, w: 100.0, h: 5.0, visible: true, align: "left" },
              cover_divider:      { x: 0.0, y: 16.5, w: 100.0, h: 0.5, visible: true },
              cover_hero_image:   { x: 0.0, y: 19.0, w: 56.0, h: 76.0, visible: true },
              cover_project_card: { x: 59.0, y: 19.0, w: 41.0, h: 46.0, visible: true },
              cover_history_card: { x: 59.0, y: 67.0, w: 41.0, h: 28.0, visible: true },
              footer:             { x: 0.0, y: 96.0, w: 100.0, h: 4.0, visible: true }
            },
            description: {
              desc_header:     { x: 0.0, y: 0.0, w: 100.0, h: 7.0, visible: true },
              desc_materials:  { x: 0.0, y: 9.0, w: 52.0, h: 20.0, visible: true },
              desc_appliances: { x: 0.0, y: 31.0, w: 52.0, h: 20.0, visible: true },
              desc_lighting:   { x: 0.0, y: 53.0, w: 52.0, h: 20.0, visible: true },
              desc_notes:      { x: 0.0, y: 75.0, w: 52.0, h: 20.0, visible: true },
              desc_image:      { x: 55.0, y: 9.0, w: 45.0, h: 86.0, visible: true },
              footer:          { x: 0.0, y: 96.0, w: 100.0, h: 4.0, visible: true }
            },
            explain: {
              explain_header: { x: 0.0, y: 0.0, w: 100.0, h: 7.0, visible: true },
              explain_toc:    { x: 0.0, y: 9.0, w: 48.0, h: 86.0, visible: true },
              explain_specs:  { x: 52.0, y: 9.0, w: 48.0, h: 35.0, visible: true },
              explain_image:  { x: 52.0, y: 47.0, w: 48.0, h: 48.0, visible: true },
              footer:         { x: 0.0, y: 96.0, w: 100.0, h: 4.0, visible: true }
            },
            general: {
              general_header: { x: 0.0, y: 0.0, w: 100.0, h: 7.0, visible: true },
              general_image:  { x: 0.0, y: 9.0, w: 100.0, h: 73.0, visible: true },
              general_note:   { x: 0.0, y: 84.0, w: 100.0, h: 11.0, visible: true },
              footer:         { x: 0.0, y: 96.0, w: 100.0, h: 4.0, visible: true }
            },
            visual: {
              visual_header: { x: 0.0, y: 0.0, w: 100.0, h: 6.0, visible: true },
              visual_image:  { x: 0.0, y: 7.0, w: 100.0, h: 88.0, visible: true },
              footer:        { x: 0.0, y: 96.0, w: 100.0, h: 4.0, visible: true }
            }
          }
        end

        # Возвращает базовые настройки экспорта PDF по умолчанию
        # @return [Hash] хэш с параметрами PDF (размер листа, ориентация, цвета, штамп и т.д.)
        def default_pdf_settings
          {
            export_engine:      "prawn",
            layout_render_mode: "raster",
            save_layout_file:   true,
            page_size:          "A4",
            page_layout:        "landscape",
            margin:             15,
            image_width:        2400,
            scale_factor:       2.0,
            antialias:          true,
            stamp_type:         "draft",
            stamp_custom:       "НЕ УТВЕРЖДЕН",
            auto_open_pdf:      true,
            save_skp_backup:    true,
            primary_color:      "005EB0",
            secondary_color:    "64748B",
            stamp_color:        "D32F2F",
            custom_layouts:     default_custom_layouts
          }
        end

        # Очищает строку имени от запрещенных символов файловой системы
        # @param name [String, Object] исходное имя файла
        # @return [String] безопасное для файловой системы имя
        def self.sanitize_filename(name)
          name.to_s.gsub(/[\\\/:\*\?"<>\|]/, "_").strip
        end

        # Определяет имя YAML файла на основе артикула или имени файла модели
        # @param project_info [Hash] метаданные проекта
        # @param model [Sketchup::Model, nil] экземпляр модели SketchUp
        # @return [String] имя файла YAML (например, "ART-100.yaml" или "ModelName.yaml")
        def self.resolve_yaml_filename(project_info, model = nil)
          articul = project_info && project_info[:articul] ? project_info[:articul].to_s.strip : ""
          if !articul.empty?
            clean_name = sanitize_filename(articul)
            return "#{clean_name}.yaml" unless clean_name.empty?
          end

          if model && model.respond_to?(:path) && !model.path.to_s.empty?
            clean_path = model.path.to_s.tr("\\", "/")
            base_name = File.basename(clean_path, ".*")
            clean_base = sanitize_filename(base_name)
            return "#{clean_base}.yaml" unless clean_base.empty?
          end

          "project_config.yaml"
        end

        # Ищет существующий YAML файл конфигурации рядом с файлом модели SketchUp
        # @param model [Sketchup::Model] модель SketchUp
        # @return [String, nil] абсолютный путь к существующему YAML файлу или nil
        def self.find_yaml_path_for_model(model)
          return nil unless model && model.respond_to?(:path) && !model.path.to_s.empty?

          clean_path = model.path.to_s.tr("\\", "/")
          dir = File.dirname(clean_path)
          base_name = File.basename(clean_path, ".*")

          # 1. Проверяем артикул из атрибутов модели
          raw_info = model.get_attribute(ATTR_DICT, "project_info", nil) rescue nil
          if raw_info
            begin
              info = JSON.parse(raw_info, symbolize_names: true)
              articul = info[:articul].to_s.strip
              if !articul.empty?
                art_yaml = File.join(dir, "#{sanitize_filename(articul)}.yaml")
                return art_yaml if File.exist?(art_yaml)

                art_yml = File.join(dir, "#{sanitize_filename(articul)}.yml")
                return art_yml if File.exist?(art_yml)
              end
            rescue StandardError
              # Ignore
            end
          end

          # 2. Проверяем имя файла модели <model_basename>.yaml / .yml
          model_yaml = File.join(dir, "#{base_name}.yaml")
          return model_yaml if File.exist?(model_yaml)

          model_yml = File.join(dir, "#{base_name}.yml")
          return model_yml if File.exist?(model_yml)

          # 3. Проверяем project_config.yaml / .yml
          cfg_yaml = File.join(dir, "project_config.yaml")
          return cfg_yaml if File.exist?(cfg_yaml)

          cfg_yml = File.join(dir, "project_config.yml")
          return cfg_yml if File.exist?(cfg_yml)

          # 4. Если в модели вообще нет атрибутов, сканируем папку модели на наличие YAML файла конфигурации проекта
          if raw_info.nil?
            all_yamls = Dir.glob(File.join(dir, "*.{yaml,yml}")).reject do |f|
              File.basename(f).start_with?("~", ".")
            end

            if all_yamls.size == 1
              return all_yamls.first
            elsif all_yamls.size > 1
              # Ищем файл, содержащий project_info
              matching = all_yamls.find do |f|
                File.read(f, 500, encoding: "utf-8").include?("project_info") rescue false
              end
              return matching if matching
            end
          end

          nil
        end

        # Возвращает целевое имя YAML файла для текущего экземпляра проекта
        # @param model [Sketchup::Model, nil] модель SketchUp
        # @return [String] имя файла YAML
        def yaml_filename(model = nil)
          self.class.resolve_yaml_filename(@project_info, model)
        end

        # Возвращает полный путь к целевому YAML файлу рядом с файлом модели SketchUp
        # @param model [Sketchup::Model] модель SketchUp
        # @return [String, nil] путь к файлу YAML или nil, если модель не сохранена
        def yaml_path_for_model(model)
          return nil unless model && model.respond_to?(:path) && !model.path.to_s.empty?

          clean_path = model.path.to_s.tr("\\", "/")
          dir = File.dirname(clean_path)
          File.join(dir, yaml_filename(model))
        end

        # Автоматическая загрузка данных с приоритетом:
        # 1. ПЕРВИЧНО: YAML файл рядом с файлом SketchUp (.skp)
        # 2. ВТОРИЧНО: Библиотека файла (атрибуты модели SketchUp)
        # @param model [Sketchup::Model, nil] модель SketchUp
        # @return [Symbol] источник загрузки (:yaml, :model или :default)
        def load_auto(model)
          loaded_from = nil

          # 1. ПЕРВИЧНО: Ищем и загружаем YAML файл рядом с .skp
          yaml_file = self.class.find_yaml_path_for_model(model)
          if yaml_file && File.exist?(yaml_file)
            if load_from_yaml(yaml_file)
              loaded_from = :yaml
              # Синхронизируем прочитанные данные в библиотеку модели
              save_to_model(model) if model
            end
          end

          # 2. ВТОРИЧНО: Если YAML не найден, читаем из библиотеки модели (атрибутов)
          if loaded_from.nil? && model
            if load_from_model(model)
              loaded_from = :model
            end
          end

          # Синхронизация списка сцен из модели
          sync_with_model_scenes(model) if model

          loaded_from || :default
        end

        # Автоматическое сохранение данных проекта:
        # 1. В библиотеку модели (Attribute Dictionaries)
        # 2. В файл YAML рядом с файлом SketchUp (с автоматическим удалением старого файла при смене артикула)
        # @param model [Sketchup::Model] модель SketchUp
        # @return [Boolean] true в случае успешного сохранения
        def save_auto(model)
          return false unless model

          # 1. Находим текущий существующий YAML файл до обновления атрибутов модели
          old_yaml = self.class.find_yaml_path_for_model(model)

          # 2. Сохранение в библиотеку модели (атрибуты)
          save_to_model(model)

          # 3. Сохранение в YAML файл рядом с .skp
          if model.respond_to?(:path) && !model.path.to_s.empty?
            target_yaml = yaml_path_for_model(model)
            if target_yaml
              if save_to_yaml(target_yaml)
                # Если имя YAML файла изменилось (например, при смене или очистке артикула),
                # удаляем старый YAML файл во избежание дубликатов
                if old_yaml && File.exist?(old_yaml)
                  old_norm = File.expand_path(old_yaml).tr("\\", "/").downcase
                  target_norm = File.expand_path(target_yaml).tr("\\", "/").downcase
                  if old_norm != target_norm
                    File.delete(old_yaml) rescue nil
                  end
                end
              end
            end
          end

          true
        end

        # Синхронизирует список сцен с активной моделью SketchUp, сохраняя настроенные параметры
        # @param model [Sketchup::Model] модель SketchUp
        # @return [void]
        def sync_with_model_scenes(model)
          return unless model && model.respond_to?(:pages)

          existing_scenes_map = @scenes.each_with_object({}) { |s, h| h[s.name] = s }
          new_scenes = []

          model.pages.each_with_index do |page, idx|
            if existing_scenes_map.key?(page.name)
              item = existing_scenes_map[page.name]
              item.scene_ref = page
              item.order = idx if item.order.zero?
              new_scenes << item
            else
              # Новая сцена
              included = page.respond_to?(:include_in_animation?) ? page.include_in_animation? : true
              item = SceneItem.new(
                name:        page.name,
                scene_ref:   page,
                description: page.respond_to?(:description) ? page.description.to_s : "",
                order:       idx,
                enabled:     included
              )
              new_scenes << item
            end
          end

          @scenes = new_scenes
        end

        # Читает данные проекта из словарей атрибутов модели SketchUp (библиотека модели)
        # @param model [Sketchup::Model] модель SketchUp
        # @return [Boolean] true, если данные были успешно прочитаны
        def load_from_model(model)
          return false unless model && model.respond_to?(:get_attribute)

          raw_info = model.get_attribute(ATTR_DICT, "project_info", nil)
          has_data = false

          if raw_info
            begin
              parsed = JSON.parse(raw_info, symbolize_names: true)
              @project_info.merge!(parsed)
              has_data = true
            rescue StandardError
              # Ignore JSON parse errors
            end
          end

          raw_settings = model.get_attribute(ATTR_DICT, "pdf_settings", nil)
          if raw_settings
            begin
              parsed = JSON.parse(raw_settings, symbolize_names: true)
              @pdf_settings.merge!(parsed)
              has_data = true
            rescue StandardError
              # Ignore
            end
          end

          raw_history = model.get_attribute(ATTR_DICT, "history", nil)
          if raw_history
            begin
              parsed = JSON.parse(raw_history, symbolize_names: true)
              if parsed.is_a?(Array)
                @history = parsed
                has_data = true
              end
            rescue StandardError
              # Ignore
            end
          end

          raw_scenes = model.get_attribute(ATTR_DICT, "scenes", nil)
          if raw_scenes
            begin
              parsed = JSON.parse(raw_scenes, symbolize_names: true)
              if parsed.is_a?(Array) && !parsed.empty?
                @scenes = parsed.map { |h| SceneItem.from_h(h) }
                has_data = true
              end
            rescue StandardError
              # Ignore
            end
          end

          sync_with_model_scenes(model)
          has_data
        end

        # Сохраняет данные проекта в словарь атрибутов модели SketchUp (библиотека модели)
        # @param model [Sketchup::Model] модель SketchUp
        # @return [Boolean] true в случае успешного сохранения
        def save_to_model(model)
          return false unless model && model.respond_to?(:set_attribute)

          model.set_attribute(ATTR_DICT, "project_info", JSON.generate(@project_info))
          model.set_attribute(ATTR_DICT, "pdf_settings", JSON.generate(@pdf_settings))
          model.set_attribute(ATTR_DICT, "history", JSON.generate(@history))

          scenes_data = @scenes.map(&:to_h)
          model.set_attribute(ATTR_DICT, "scenes", JSON.generate(scenes_data))
          true
        end

        # Рекурсивно преобразует строковые ключи вложенных хэшей и массивов в Symbol
        # @param obj [Object] исходный объект (Hash, Array или примитив)
        # @return [Object] объект с символьными ключами
        def self.deep_symbolize_keys(obj)
          case obj
          when Hash
            obj.each_with_object({}) do |(k, v), result|
              result[k.to_s.to_sym] = deep_symbolize_keys(v)
            end
          when Array
            obj.map { |e| deep_symbolize_keys(e) }
          else
            obj
          end
        end

        # Загружает данные проекта из файла YAML (поддерживает однодокументный и потоковый форматы)
        # @param file_path [String] путь к YAML файлу
        # @return [Boolean] true в случае успешной загрузки
        def load_from_yaml(file_path)
          return false unless File.exist?(file_path)

          begin
            content = File.read(file_path, encoding: "utf-8")
            raw_docs = begin
                         YAML.load_stream(content, symbolize_names: true)
                       rescue ArgumentError
                         YAML.load_stream(content)
                       end
            return false if raw_docs.nil? || raw_docs.empty?

            docs = raw_docs.map { |d| self.class.deep_symbolize_keys(d) }

            # Вариант 1: Структурированный одиночный хэш { project_info: ..., pdf_settings: ..., scenes: ..., history: ... }
            if docs.size == 1 && docs[0].is_a?(Hash) && (docs[0].key?(:project_info) || docs[0].key?(:pdf_settings) || docs[0].key?(:scenes) || docs[0].key?(:history))
              root = docs[0]
              @project_info.merge!(root[:project_info]) if root[:project_info].is_a?(Hash)
              @pdf_settings.merge!(root[:pdf_settings]) if root[:pdf_settings].is_a?(Hash)
              if root[:scenes].is_a?(Array)
                @scenes = root[:scenes].map { |h| SceneItem.from_h(h) }
              end
              if root[:history].is_a?(Array)
                @history = root[:history]
              end
              return true
            end

            # Вариант 2: Многодокументный потоковый формат
            if docs[0].is_a?(Hash)
              @project_info.merge!(docs[0])
            end
            if docs[1].is_a?(Array)
              @scenes = docs[1].map { |h| SceneItem.from_h(h) }
            end
            if docs[2].is_a?(Array)
              @history = docs[2]
            end
            if docs[3].is_a?(Hash)
              @pdf_settings.merge!(docs[3])
            end
            true
          rescue StandardError => e
            warn "Ошибка загрузки YAML (#{file_path}): #{e.message}"
            false
          end
        end

        # Сохраняет данные проекта в YAML файл
        # @param file_path [String] путь к сохраняемому YAML файлу
        # @return [Boolean] true в случае успешного сохранения
        def save_to_yaml(file_path)
          FileUtils.mkdir_p(File.dirname(file_path))
          data = {
            project_info: @project_info,
            pdf_settings: @pdf_settings,
            scenes:       @scenes.map(&:to_h),
            history:      @history
          }
          File.open(file_path, "w:utf-8") do |f|
            f.write data.to_yaml
          end
          true
        end

        # Увеличивает номер ревизии проекта (+1) и добавляет запись с таймштампом в историю
        # @param description [String] текстовое описание причины создания новой ревизии
        # @return [void]
        def increment_revision!(description = "Экспорт в PDF")
          @project_info[:revision] = (@project_info[:revision] || 0) + 1
          @history << {
            date:        Time.now.strftime("%Y.%m.%d %H:%M"),
            description: "#{description} (rev. #{@project_info[:revision]})"
          }
        end

        # Преобразует все данные проекта в стандартный Ruby Hash
        # @return [Hash] хэш со всеми полями проекта, настройками, сценами и историей
        def to_h
          {
            project_info: @project_info,
            pdf_settings: @pdf_settings,
            scenes:       @scenes.map(&:to_h),
            history:      @history
          }
        end
      end
    end
  end
end
