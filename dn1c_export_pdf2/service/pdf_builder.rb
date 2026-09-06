# frozen_string_literal: true

require_relative "gem_loader"
require_relative "font_service"

module DN1Code
  module ExportPdf2
    module Service
      module PdfBuilder
        def self.create_document(project_data, pdf_settings = {})
          GemLoader.ensure_prawn_loaded!

          page_size   = pdf_settings[:page_size] || "A4"
          page_layout = (pdf_settings[:page_layout] || :landscape).to_sym
          margin = if pdf_settings.key?(:margin_mm) && !pdf_settings[:margin_mm].nil?
                     (pdf_settings[:margin_mm].to_f * 72.0 / 25.4).round(1)
                   elsif pdf_settings.key?("margin_mm") && !pdf_settings["margin_mm"].nil?
                     (pdf_settings["margin_mm"].to_f * 72.0 / 25.4).round(1)
                   elsif pdf_settings.key?(:margin) && !pdf_settings[:margin].nil?
                     pdf_settings[:margin].to_f
                   elsif pdf_settings.key?("margin") && !pdf_settings["margin"].nil?
                     pdf_settings["margin"].to_f
                   else
                     15.0
                   end

          project_info = project_data.project_info

          title_str   = "#{project_info[:name_project]} - #{project_info[:articul]}"
          author_str  = project_info[:name_customer].to_s.empty? ? "DN1C Export PDF 2" : project_info[:name_customer]
          subject_str = "Ревизия v#{project_info[:version]}#r#{project_info[:revision]}"

          pdf_doc = Prawn::Document.new(
            page_size:   page_size,
            page_layout: page_layout,
            margin:      margin,
            info: {
              Title:        title_str,
              Author:       author_str,
              Subject:      subject_str,
              Creator:      "DN1C Export PDF 2 (SketchUp 2026)",
              Producer:     "DESTUDIONS",
              CreationDate: Time.now,
              ModDate:      Time.now
            }
          )

          FontService.setup_fonts(pdf_doc)
          pdf_doc
        end
      end
    end
  end
end
