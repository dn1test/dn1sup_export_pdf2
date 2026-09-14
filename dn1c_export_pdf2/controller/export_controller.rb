# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require_relative "../service/layout_builder"

module DN1Code
  module ExportPdf2
    module Controller
      # Контроллер экспорта: управляет созданием PDF через SketchUp LayOut Ruby API,
      # сохранением резервных копий и синхронизацией данных проекта.
      class ExportController
        attr_reader :project_data, :model

        def initialize(project_data, model = nil)
          @project_data = project_data
          @model        = model || (defined?(Sketchup) ? Sketchup.active_model : nil)
        end

        # Экспорт документа в PDF через SketchUp LayOut Ruby API
        # @param custom_output_path [String, nil] путь к выходному PDF файлу
        # @param progress_block [Proc, nil] блок обратного вызова прогресса (current, total, message)
        # @return [String] абсолютный путь к созданному PDF
        def export(custom_output_path = nil, &progress_block)
          Service::LayoutBuilder.export(self, custom_output_path, &progress_block)
        end

        # Разрешение пути по умолчанию для результирующего PDF файла
        # @return [String]
        def resolve_default_pdf_path
          model_path = @model&.respond_to?(:path) ? @model.path : ""
          variant_rev = sprintf("v%02d_r%03d", @project_data.project_info[:version] || 1, @project_data.project_info[:revision] || 1)

          if model_path && !model_path.empty?
            model_dir  = File.dirname(model_path.tr("\\", "/"))
            model_base = File.basename(model_path, ".skp")
            File.join(model_dir, "#{model_base}_#{variant_rev}.pdf")
          else
            # Если модель еще не сохранена на диске
            File.join(Dir.tmpdir, "SU_Export_#{variant_rev}.pdf")
          end
        end

        # Резервная копия файла модели (.skp)
        # @return [String, nil]
        def save_skp_backup
          return nil unless @model&.respond_to?(:path)

          model_path = @model.path.to_s
          return nil if model_path.empty?

          model_dir   = File.dirname(model_path.tr("\\", "/"))
          model_base  = File.basename(model_path, ".skp")
          variant_rev = sprintf("v%02d_r%03d", @project_data.project_info[:version] || 1, @project_data.project_info[:revision] || 1)

          backup_dir  = File.join(model_dir, "#{model_base}_backup")
          FileUtils.mkdir_p(backup_dir)
          backup_path = File.join(backup_dir, "#{model_base}_#{variant_rev}.skp")

          if @model.respond_to?(:save_copy)
            @model.save_copy(backup_path)
            backup_path
          end
        end
      end
    end
  end
end
