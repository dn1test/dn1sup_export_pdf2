# frozen_string_literal: true

module DN1Code
  module ExportPdf2
    module Model
      # Модель сцены проекта SketchUp для экспорта в PDF.
      # Содержит имя сцены, тип шаблона страницы, порядок следования, примечания и статус включения в документ.
      class SceneItem
        # @return [Sketchup::Page, nil] ссылка на нативный объект сцены SketchUp
        attr_accessor :scene_ref
        # @return [String] название сцены
        attr_accessor :name
        # @return [String] исходное имя сцены в SketchUp до редактирования
        attr_accessor :original_name
        # @return [Symbol] тип страницы (:cover, :description, :explain, :visual, :general)
        attr_accessor :page_type
        # @return [String] примечание или текстовое описание к сцене
        attr_accessor :description
        # @return [Integer] порядковый номер сцены в документе
        attr_accessor :order
        # @return [Boolean] флаг включения страницы в итоговый PDF
        attr_accessor :enabled
        # @return [Boolean] флаг включения видового экрана 3D на этой странице
        attr_accessor :viewport_visible
        # @return [Boolean] флаг отображения фона сцены (небо/земля) в видовом экране
        attr_accessor :viewport_background
        # @return [String] пропорции видового экрана ('3:2', '4:3', '16:9', '1:1', 'page')
        attr_accessor :aspect_ratio
        # @return [Integer] процент масштабирования/размещения на листе (60-100)
        attr_accessor :scale_pct

        # Инициализирует новый элемент сцены
        # @param name [String] название сцены
        # @param original_name [String, nil] исходное имя сцены в SketchUp
        # @param scene_ref [Sketchup::Page, nil] ссылка на нативную сцену SketchUp
        # @param page_type [Symbol, String, nil] тип страницы (если nil, определяется автоматически)
        # @param description [String] примечание/описание к сцене
        # @param order [Integer] порядковый индекс сцены
        # @param enabled [Boolean] включена ли сцена в экспорт
        # @param viewport_visible [Boolean] включен ли 3D видовой экран на этой странице
        # @param viewport_background [Boolean] отображать ли фон сцены (небо/земля) в видовом экране (по умолчанию выключен)
        # @param aspect_ratio [String] пропорции кадра (3:2, 4:3, 16:9, 1:1, page)
        # @param scale_pct [Integer] масштаб/размещение кадра на листе в % (60-100)
        def initialize(name:, original_name: nil, scene_ref: nil, page_type: nil, description: "", order: 0, enabled: true, viewport_visible: true, viewport_background: false, aspect_ratio: "4:3", scale_pct: 100)
          @name             = name.to_s
          @original_name    = (original_name || name).to_s
          @scene_ref        = scene_ref
          @description      = description.to_s
          @order            = order.to_i
          @enabled          = enabled
          @viewport_visible = (viewport_visible != false && viewport_visible.to_s != "false" && viewport_visible != 0 && viewport_visible.to_s != "0")
          @viewport_background = (viewport_background == true || viewport_background.to_s == "true")
          @aspect_ratio     = (aspect_ratio || "4:3").to_s.strip
          @scale_pct        = (scale_pct || 100).to_i
          @page_type        = page_type ? page_type.to_sym : detect_page_type(@name)
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
          when /чист|пуст|blank|empty/i
            :blank
          else
            :general
          end
        end

        # Преобразует элемент сцены в Hash для сериализации в JSON/YAML
        # @return [Hash] хэш с параметрами сцены
        def to_h
          {
            name:             @name,
            original_name:    @original_name,
            page_type:        @page_type.to_s,
            description:      @description,
            order:            @order,
            enabled:          @enabled,
            viewport_visible: @viewport_visible,
            viewport_background: @viewport_background,
            aspect_ratio:     @aspect_ratio,
            scale_pct:        @scale_pct
          }
        end

        # Восстанавливает экземпляр SceneItem из хэша
        # @param hash [Hash] хэш с сериализованными данными сцены
        # @param scene_ref [Sketchup::Page, nil] нативная сцена SketchUp
        # @return [SceneItem] восстановленный объект сцены
        def self.from_h(hash, scene_ref = nil)
          new(
            name:             hash[:name] || hash["name"] || "Scene",
            original_name:    hash[:original_name] || hash["original_name"] || hash[:name] || hash["name"],
            scene_ref:        scene_ref,
            page_type:        hash[:page_type] || hash["page_type"],
            description:      hash[:description] || hash["description"] || "",
            order:            hash[:order] || hash["order"] || 0,
            enabled:          hash.fetch(:enabled, hash.fetch("enabled", true)),
            viewport_visible: hash.fetch(:viewport_visible, hash.fetch("viewport_visible", true)),
            viewport_background: hash.fetch(:viewport_background, hash.fetch("viewport_background", false)),
            aspect_ratio:     hash[:aspect_ratio] || hash["aspect_ratio"] || "4:3",
            scale_pct:        hash[:scale_pct] || hash["scale_pct"] || 100
          )
        end
      end
    end
  end
end
