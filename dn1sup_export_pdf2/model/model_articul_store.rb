# frozen_string_literal: true

module DN1Code
  module ExportPdf2
    module Model
      # Артикул проекта, сохраненный в самом файле модели (.skp) через атрибутный
      # словарь SketchUp. Это единственные данные плагина в .skp: по артикулу
      # определяется папка проекта (<папка .skp>/<Артикул>) при открытии модели
      # (ProjectData#load_auto), даже если рядом с моделью несколько папок
      # артикулов или ни одной. Все остальные данные проекта — только YAML.
      # Запись выполняется в точках, где артикул создается или сохраняется:
      # колбэк createProjectFolder, ProjectData#save_project_yaml,
      # SessionStore.import_project_yaml. set_attribute помечает модель
      # измененной — артикул попадает в файл после сохранения .skp (Ctrl+S),
      # автосохранение модели плагин не выполняет.
      module ModelArticulStore
        # Имя атрибутного словаря и ключ артикула в файле модели
        DICT_NAME   = "DN1SUP_ExportPdf2"
        KEY_ARTICUL = "Articul"

        class << self
          # Записывает артикул в атрибуты модели. Ошибки глушатся с предупреждением:
          # сбой записи не должен ломать создание папки проекта или сохранение YAML.
          # @param model [Sketchup::Model, nil] модель SketchUp
          # @param articul [String] артикул проекта
          # @return [Boolean] true, если атрибут записан
          def write(model, articul)
            value = articul.to_s.strip
            return false if value.empty?
            return false unless model && model.respond_to?(:set_attribute)

            begin
              model.set_attribute(DICT_NAME, KEY_ARTICUL, value)
              true
            rescue StandardError => e
              warn "[DN1SUP Export PDF] Не удалось записать артикул в файл модели: #{e.message}"
              false
            end
          end

          # Читает артикул из атрибутов модели
          # @param model [Sketchup::Model, nil] модель SketchUp
          # @return [String] артикул или пустая строка, если его нет в файле
          def read(model)
            return "" unless model && model.respond_to?(:get_attribute)

            begin
              model.get_attribute(DICT_NAME, KEY_ARTICUL, "").to_s.strip
            rescue StandardError
              ""
            end
          end
        end
      end
    end
  end
end
