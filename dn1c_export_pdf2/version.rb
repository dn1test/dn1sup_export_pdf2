# frozen_string_literal: true

module DN1Code
  module ExportPdf2
    unless const_defined?(:PLUGIN_VERSION)
      PLUGIN_NAME        = "DN1C Export PDF 2"
      NAME_EXTENSION     = PLUGIN_NAME
      PLUGIN_DESCRIPTION = "Расширение для экспорта сцен SketchUp в многостраничный PDF-документ с шаблонами страниц, метаданными проекта и интерактивным интерфейсом."
      PLUGIN_VERSION     = "2.0.0"
      VERSION            = PLUGIN_VERSION
      PLUGIN_AUTHOR      = "DN1Code"
      NAME_CREATOR       = PLUGIN_AUTHOR
      PLUGIN_COPYRIGHT   = "Copyright 2026 #{PLUGIN_AUTHOR}"
    end
  end
end
