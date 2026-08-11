# frozen_string_literal: true

require "yaml"
require "json"
require "time"

module DN1Code
  module ExportPdf2
    module Model
      class ProjectData
        ATTR_DICT = "DN1C_ExportPDF"

        attr_accessor :project_info, :scenes, :history, :pdf_settings

        def initialize
          @project_info = default_project_info
          @pdf_settings = default_pdf_settings
          @scenes       = []
          @history      = [
            { date: Time.now.strftime("%Y.%m.%d"), description: "Инициализация проекта" }
          ]
        end

        def default_project_info
          {
            room_name:      "Кухня-гостиная",
            furniture_name: "Кухонный гарнитур",
            name_project:   "Кухня-гостиная — Кухонный гарнитур",
            description:    "Концептуальный дизайн-проект и спецификации",
            name_customer:  "Заказчик",
            phone:          "+7 (000) 000-00-00",
            email:          "info@example.com",
            address:        "г. Москва, ул. Примерная, д. 1",
            articul:        "PRJ-001",
            version:        1,
            revision:       1,
            status:           "В РАБОТЕ",
            task_description: "Разработка полного комплекта чертежей и 3D визуализаций изделия согласно габаритам помещения и пожеланиям заказчика.",
            task_dimensions:  "Монтажный проем: 3200 x 2650 x 600 мм. Привязка розеток фартука по схеме развертки стен.",
            task_wishes:      "Предусмотреть интеграцию встроенного холодильника, посудомоечной машины 60см и скрытую вытяжку.",
            materials:        "Фасады: МДФ эмаль матовая, корпус: ЛДСП Egger 18мм, фурнитура: Blum Legrabox / Aventos HF.",
            appliances:       "Встроенный духовой шкаф, индукционная варочная панель 60см, вытяжка полновстраиваемая, посудомоечная машина 60см, холодильник встроенный.",
            lighting:         "Светодиодная лента 3000K CRI>95 в алюминиевом профиле, блок питания 24V с запасом 30%, сенсорный выключатель.",
            notes:            "Монтаж производить после завершения чистовой отделки стен и укладки напольного покрытия. Выводы электрики согласно схеме.",
            edit:             "Правки не внесены"
          }
        end

        def default_pdf_settings
          {
            page_size:       "A4",
            page_layout:     "landscape",
            margin:          15,
            image_width:     2400,
            scale_factor:    2.0,
            antialias:       true,
            stamp_type:      "draft",
            stamp_custom:    "НЕ УТВЕРЖДЕН",
            auto_open_pdf:   true,
            save_skp_backup: true,
            primary_color:   "005EB0",
            secondary_color: "64748B",
            stamp_color:     "D32F2F"
          }
        end

        # Синхронизация сцен из активной модели SketchUp
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

        # Чтение данных из атрибутов модели SketchUp
        def load_from_model(model)
          return false unless model && model.respond_to?(:get_attribute)

          raw_info = model.get_attribute(ATTR_DICT, "project_info", nil)
          if raw_info
            begin
              parsed = JSON.parse(raw_info, symbolize_names: true)
              @project_info.merge!(parsed)
            rescue StandardError
              # Ignore JSON parse errors
            end
          end

          raw_settings = model.get_attribute(ATTR_DICT, "pdf_settings", nil)
          if raw_settings
            begin
              parsed = JSON.parse(raw_settings, symbolize_names: true)
              @pdf_settings.merge!(parsed)
            rescue StandardError
              # Ignore
            end
          end

          raw_history = model.get_attribute(ATTR_DICT, "history", nil)
          if raw_history
            begin
              parsed = JSON.parse(raw_history, symbolize_names: true)
              @history = parsed if parsed.is_a?(Array) && !parsed.empty?
            rescue StandardError
              # Ignore
            end
          end

          raw_scenes = model.get_attribute(ATTR_DICT, "scenes", nil)
          if raw_scenes
            begin
              parsed = JSON.parse(raw_scenes, symbolize_names: true)
              if parsed.is_a?(Array)
                @scenes = parsed.map { |h| SceneItem.from_h(h) }
              end
            rescue StandardError
              # Ignore
            end
          end

          sync_with_model_scenes(model)
          true
        end

        # Сохранение данных в атрибуты модели SketchUp
        def save_to_model(model)
          return false unless model && model.respond_to?(:set_attribute)

          model.set_attribute(ATTR_DICT, "project_info", JSON.generate(@project_info))
          model.set_attribute(ATTR_DICT, "pdf_settings", JSON.generate(@pdf_settings))
          model.set_attribute(ATTR_DICT, "history", JSON.generate(@history))
          
          scenes_data = @scenes.map(&:to_h)
          model.set_attribute(ATTR_DICT, "scenes", JSON.generate(scenes_data))
          true
        end

        # Загрузка из YAML-файла
        def load_from_yaml(file_path)
          return false unless File.exist?(file_path)

          begin
            docs = YAML.load_stream(File.read(file_path), symbolize_names: true)
            if docs[0].is_a?(Hash)
              @project_info.merge!(docs[0])
            end
            if docs[1].is_a?(Array)
              @scenes = docs[1].map { |h| SceneItem.from_h(h) }
            end
            if docs[2].is_a?(Array)
              @history = docs[2]
            end
            true
          rescue StandardError => e
            warn "Ошибка загрузки YAML: #{e.message}"
            false
          end
        end

        # Сохранение в YAML-файл
        def save_to_yaml(file_path)
          FileUtils.mkdir_p(File.dirname(file_path))
          File.open(file_path, "w:utf-8") do |f|
            f.write @project_info.to_yaml
            f.write @scenes.map(&:to_h).to_yaml
            f.write @history.to_yaml
          end
          true
        end

        # Увеличение номера ревизии и добавление записи в историю
        def increment_revision!(description = "Экспорт в PDF")
          @project_info[:revision] = (@project_info[:revision] || 0) + 1
          @history << {
            date:        Time.now.strftime("%Y.%m.%d %H:%M"),
            description: "#{description} (rev. #{@project_info[:revision]})"
          }
        end

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
