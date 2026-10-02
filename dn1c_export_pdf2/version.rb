# frozen_string_literal: true

# Основное пространство имен расширений DN1Code
module DN1Code
  # Модуль расширения DN1C Export PDF 2 для SketchUp
  module ExportPdf2
    unless const_defined?(:PLUGIN_VERSION)
      # Название плагина
      PLUGIN_NAME        = "DN1C Export PDF 2"
      # Название расширения в реестре SketchUp
      NAME_EXTENSION     = PLUGIN_NAME
      # Подробное описание назначения плагина
      PLUGIN_DESCRIPTION = "Расширение для экспорта сцен SketchUp в многостраничный PDF-документ с шаблонами страниц, метаданными проекта и интерактивным интерфейсом."
      # Текущая версия плагина.
      # Схема: вторая цифра — добавление функций, третья цифра — изменения
      # в дизайне/мелкие правки
      PLUGIN_VERSION     = "2.13.6"
      # Автор и разработчик плагина
      PLUGIN_AUTHOR      = "DN1Code"
      # Имя создателя для регистрации расширения
      NAME_CREATOR       = PLUGIN_AUTHOR
      # Информация об авторских правах
      PLUGIN_COPYRIGHT   = "Copyright 2026 #{PLUGIN_AUTHOR}"
    end
  end
end
