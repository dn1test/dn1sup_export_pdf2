# frozen_string_literal: true

# -------------------------------------------------------------------------------
# Extension Loader: DN1Sup Export PDF 2 for SketchUp 2026
# Developer: DN1Sup <dn1codegen@gmail.com>
# License: MIT
# Description: Generates multi-page high-resolution PDF documents from SketchUp scenes.
# -------------------------------------------------------------------------------

begin
  require "sketchup.rb"
  require "extensions.rb"
rescue LoadError
  # Резервная реализация методов SketchUp для работы в автономных тестовых средах

  # Проверяет, был ли файл уже загружен
  # @param file [String] путь к файлу
  # @return [Boolean] true, если файл уже загружен
  def file_loaded?(file)
    $LOADED_EXT_FILES ||= []
    $LOADED_EXT_FILES.include?(file)
  end

  # Помечает файл как загруженный
  # @param file [String] путь к файлу
  # @return [Array<String>] обновленный список загруженных файлов
  def file_loaded(file)
    $LOADED_EXT_FILES ||= []
    $LOADED_EXT_FILES << file
  end
end

require_relative "dn1sup_export_pdf2/version"

# Основное пространство имен расширений DN1Code
module DN1Code
  # Модуль расширения DN1Sup Export PDF 2 для SketchUp
  module ExportPdf2
    unless file_loaded?(__FILE__)
      # Регистрация плагина в диспетчере расширений SketchUp
      extension_path = File.join(__dir__, "dn1sup_export_pdf2", "main")
      ex = SketchupExtension.new(NAME_EXTENSION, extension_path)
      ex.description = PLUGIN_DESCRIPTION
      ex.version     = PLUGIN_VERSION
      ex.copyright   = PLUGIN_COPYRIGHT
      ex.creator     = NAME_CREATOR
      ex.id          = 'dn1sup_export_pdf2' if ex.respond_to?(:id=)

      Sketchup.register_extension(ex, true)
      file_loaded(__FILE__)
    end
  end
end
