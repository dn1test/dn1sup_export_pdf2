# frozen_string_literal: true

module DN1Code
  module ExportPdf2
    module Model
      # Модель сцены проекта SketchUp для экспорта в PDF.
      # Содержит имя сцены, тип шаблона страницы, порядок следования, примечания и статус включения в документ.
      class SceneItem
        # Поддерживаемые типы страниц в документе
        PAGE_TYPES = %i[cover description explain visual general].freeze

        # @return [Sketchup::Page, nil] ссылка на нативный объект сцены SketchUp
        attr_accessor :scene_ref
        # @return [String] название сцены
        attr_accessor :name
        # @return [Symbol] тип страницы (:cover, :description, :explain, :visual, :general)
        attr_accessor :page_type
        # @return [String] примечание или текстовое описание к сцене
        attr_accessor :description
        # @return [Integer] порядковый номер сцены в документе
        attr_accessor :order
        # @return [Boolean] флаг включения страницы в итоговый PDF
        attr_accessor :enabled
        # @return [String, nil] путь к кастомному изображению для подмены рендера (опционально)
        attr_accessor :image_override

        # Инициализирует новый элемент сцены
        # @param name [String] название сцены
        # @param scene_ref [Sketchup::Page, nil] ссылка на нативную сцену SketchUp
        # @param page_type [Symbol, String, nil] тип страницы (если nil, определяется автоматически)
        # @param description [String] примечание/описание к сцене
        # @param order [Integer] порядковый индекс сцены
        # @param enabled [Boolean] включена ли сцена в экспорт
        def initialize(name:, scene_ref: nil, page_type: nil, description: "", order: 0, enabled: true)
          @name           = name.to_s
          @scene_ref      = scene_ref
          @description    = description.to_s
          @order          = order.to_i
          @enabled        = enabled
          @image_override = nil
          @page_type      = page_type ? page_type.to_sym : detect_page_type(@name)
        end

        # Автоматически определяет подходящий тип шаблона страницы на основе имени сцены
        # @param scene_name [String] имя сцены
        # @return [Symbol] определенный тип страницы (:cover, :explain, :description, :visual или :general)
        def detect_page_type(scene_name)
          lower = scene_name.downcase.strip
          case lower
          when /обложк|cover|титул/i
            :cover
          when /пояснен|содержан|оглавлен|explain|toc/i
            :explain
          when /описан|специфик|материал|фурнитур|электрик|подсветк|description|spec/i
            :description
          when /визуал|visual|рендер|render|перспектив/i
            :visual
          else
            :general
          end
        end

        # Преобразует элемент сцены в Hash для сериализации в JSON/YAML
        # @return [Hash] хэш с параметрами сцены
        def to_h
          {
            name:        @name,
            page_type:   @page_type.to_s,
            description: @description,
            order:       @order,
            enabled:     @enabled
          }
        end

        # Восстанавливает экземпляр SceneItem из хэша
        # @param hash [Hash] хэш с сериализованными данными сцены
        # @param scene_ref [Sketchup::Page, nil] нативная сцена SketchUp
        # @return [SceneItem] восстановленный объект сцены
        def self.from_h(hash, scene_ref = nil)
          new(
            name:        hash[:name] || hash["name"] || "Scene",
            scene_ref:   scene_ref,
            page_type:   hash[:page_type] || hash["page_type"],
            description: hash[:description] || hash["description"] || "",
            order:       hash[:order] || hash["order"] || 0,
            enabled:     hash.fetch(:enabled, hash.fetch("enabled", true))
          )
        end
      end
    end
  end
end
