# frozen_string_literal: true

module DN1Code
  module ExportPdf2
    module Model
      class SceneItem
        PAGE_TYPES = %i[cover description explain visual general].freeze

        attr_accessor :scene_ref, :name, :page_type, :description, :order, :enabled, :image_override

        def initialize(name:, scene_ref: nil, page_type: nil, description: "", order: 0, enabled: true)
          @name           = name.to_s
          @scene_ref      = scene_ref
          @description    = description.to_s
          @order          = order.to_i
          @enabled        = enabled
          @image_override = nil
          @page_type      = page_type ? page_type.to_sym : detect_page_type(@name)
        end

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

        def to_h
          {
            name:        @name,
            page_type:   @page_type.to_s,
            description: @description,
            order:       @order,
            enabled:     @enabled
          }
        end

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
