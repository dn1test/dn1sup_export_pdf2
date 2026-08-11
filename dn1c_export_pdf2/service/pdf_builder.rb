# frozen_string_literal: true

module DN1Code
  module ExportPdf2
    module Service
      module PdfBuilder
        def self.create_document(project_data, pdf_settings = {})
          GemLoader.ensure_prawn_loaded!

          page_size   = pdf_settings[:page_size] || "A4"
          page_layout = (pdf_settings[:page_layout] || :landscape).to_sym
          margin      = pdf_settings[:margin] || 15

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
