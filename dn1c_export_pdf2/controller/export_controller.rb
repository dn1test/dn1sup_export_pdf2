# frozen_string_literal: true

require "fileutils"
require_relative "cover_page"
require_relative "description_page"
require_relative "explain_page"
require_relative "visual_page"
require_relative "general_page"
require_relative "../service/layout_builder"
require_relative "../service/gem_loader"

module DN1Code
  module ExportPdf2
    module Controller
      class ExportController
        PAGE_CONTROLLERS = {
          cover:       CoverPage,
          description: DescriptionPage,
          explain:     ExplainPage,
          visual:      VisualPage,
          general:     GeneralPage
        }.freeze

        attr_reader :project_data, :model

        def initialize(project_data, model = nil)
          @project_data = project_data
          @model        = model || (defined?(Sketchup) ? Sketchup.active_model : nil)
        end

        def export(custom_output_path = nil, &progress_block)
          settings = @project_data.pdf_settings
          engine   = settings[:export_engine].to_s.downcase

          if engine == "layout"
            # Генерация страниц и экспорт через SketchUp LayOut Ruby API
            return Service::LayoutBuilder.export(self, custom_output_path, &progress_block)
          end

          # По умолчанию: Генерация через автономный Prawn PDF движок
          Service::GemLoader.ensure_prawn_loaded!

          enabled_scenes = @project_data.scenes.select { |s| s.enabled && s.page_type != :skip }

          if enabled_scenes.empty?
            raise "Не выбрано ни одной сцены для экспорта в PDF!"
          end

          # Определение выходного пути для PDF
          pdf_path = custom_output_path || resolve_default_pdf_path
          FileUtils.mkdir_p(File.dirname(pdf_path))

          # Инициализация документа Prawn
          pdf_doc = Service::PdfBuilder.create_document(@project_data, settings)
          total_pages = enabled_scenes.size
          created_temp_files = []

          render_opts = {
            image_width:  settings[:image_width] || 2400,
            scale_factor: settings[:scale_factor] || 2.0,
            antialias:    settings.fetch(:antialias, true)
          }

          begin
            enabled_scenes.each_with_index do |scene_item, idx|
              page_index = idx + 1
              progress_block&.call(page_index, total_pages, "Рендеринг сцены #{page_index}/#{total_pages}: #{scene_item.name}")

              ctrl_class = PAGE_CONTROLLERS[scene_item.page_type] || GeneralPage

              image_for_page = if scene_item.image_override && File.exist?(scene_item.image_override)
                                 scene_item.image_override
                               else
                                 temp_img = Service::RenderService.render_scene_temp(@model, scene_item.scene_ref, render_opts)
                                 created_temp_files << temp_img
                                 temp_img
                               end

              page_ctrl = ctrl_class.new(
                pdf_doc,
                @project_data,
                scene_item,
                page_index:  page_index,
                total_pages: total_pages,
                image_path:  image_for_page
              )
              page_ctrl.render

              pdf_doc.start_new_page if page_index < total_pages
            end

            progress_block&.call(total_pages, total_pages, "Сохранение PDF документа...")

            # Сохранение готового PDF
            pdf_doc.render_file(pdf_path)

            # Резервная копия .skp
            if settings[:save_skp_backup] && @model && @model.respond_to?(:path) && !@model.path.empty?
              save_skp_backup
            end

            # Сохранение атрибутов и YAML (история правок формируется только пользователем)
            @project_data.save_auto(@model) if @model

            progress_block&.call(total_pages, total_pages, "Экспорт успешно завершен!")

            # Открытие PDF файла
            if settings[:auto_open_pdf] && defined?(UI) && UI.respond_to?(:openURL)
              UI.openURL(pdf_path)
            end

            pdf_path
          ensure
            # Безопасная очистка временных файлов после того, как PDF полностью сохранен
            Service::RenderService.safe_cleanup_files(created_temp_files)
          end
        end

        private

        def resolve_default_pdf_path
          model_path = @model&.respond_to?(:path) ? @model.path : ""
          variant_rev = sprintf("v%02d_r%03d", @project_data.project_info[:version] || 1, @project_data.project_info[:revision] || 1)

          if model_path && !model_path.empty?
            model_dir  = File.dirname(model_path.tr("\\", "/"))
            model_base = File.basename(model_path, ".skp")
            File.join(model_dir, "#{model_base}_#{variant_rev}.pdf")
          else
            # Если модель еще не сохранена
            File.join(Dir.tmpdir, "SU_Export_#{variant_rev}.pdf")
          end
        end

        def save_skp_backup
          model_path = @model.path
          return if model_path.empty?

          model_dir   = File.dirname(model_path.tr("\\", "/"))
          model_base  = File.basename(model_path, ".skp")
          variant_rev = sprintf("v%02d_r%03d", @project_data.project_info[:version] || 1, @project_data.project_info[:revision] || 1)

          backup_dir  = File.join(model_dir, model_base, "_backup")
          FileUtils.mkdir_p(backup_dir)
          backup_path = File.join(backup_dir, "#{model_base}_#{variant_rev}.skp")

          if @model.respond_to?(:save_copy)
            @model.save_copy(backup_path)
          end
        end
      end
    end
  end
end
