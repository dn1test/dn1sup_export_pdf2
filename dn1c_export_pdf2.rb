# frozen_string_literal: true

# -------------------------------------------------------------------------------
# Extension Loader: DN1C Export PDF 2 for SketchUp 2026
# Developer: DN1Code / DESTUDIONS
# Description: Generates multi-page high-resolution PDF documents from SketchUp scenes.
# -------------------------------------------------------------------------------

begin
  require "sketchup.rb"
  require "extensions.rb"
rescue LoadError
  # Fallback for standalone test environments
  def file_loaded?(file)
    $LOADED_EXT_FILES ||= []
    $LOADED_EXT_FILES.include?(file)
  end

  def file_loaded(file)
    $LOADED_EXT_FILES ||= []
    $LOADED_EXT_FILES << file
  end
end

require_relative "dn1c_export_pdf2/version"

module DN1Code
  module ExportPdf2
    unless file_loaded?(__FILE__)
      extension_path = File.join(__dir__, "dn1c_export_pdf2", "main")
      ex = SketchupExtension.new(NAME_EXTENSION, extension_path)
      ex.description = PLUGIN_DESCRIPTION
      ex.version     = VERSION
      ex.copyright   = PLUGIN_COPYRIGHT
      ex.creator     = NAME_CREATOR

      Sketchup.register_extension(ex, true)
      file_loaded(__FILE__)
    end
  end
end
