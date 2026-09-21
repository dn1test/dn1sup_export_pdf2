# frozen_string_literal: true

require_relative "project_data"

module DN1Code
  module ExportPdf2
    module Model
      # Хранилище сессий: держит экземпляр ProjectData в памяти для каждой открытой
      # модели SketchUp на всё время работы программы. Все правки пользователя
      # применяются к объекту в памяти; запись на диск (YAML) выполняется только
      # в трех точках: принудительное сохранение (кнопка), экспорт PDF и
      # закрытие SketchUp (flush_all). Библиотека модели (атрибуты .skp) не используется.
      module SessionStore
        @sessions = {}

        class << self
          # Возвращает объект данных проекта для модели из памяти.
          # При первом обращении данные загружаются из project.yaml в папке артикула.
          # @param model [Sketchup::Model, nil]
          # @return [Model::ProjectData]
          def data(model)
            key = key_for(model)
            entry = @sessions[key]
            unless entry
              project_data = ProjectData.new
              project_data.load_auto(model)
              entry = {
                data:           project_data,
                model:          model,
                model_path:     model_path_of(model),
                articul_before: project_data.project[:articul].to_s.dup,
                dirty:          false
              }
              @sessions[key] = entry
            end
            entry[:model] = model if model
            p = model_path_of(model)
            entry[:model_path] = p unless p.empty?
            entry[:data]
          end

          # Обработка открытия модели: если для пути есть чистая (несохраненная)
          # сессия — сбрасываем и перечитываем данные из YAML с диска.
          # Грязная сессия (несохраненные правки) сохраняется намеренно.
          # @param model [Sketchup::Model, nil]
          # @return [Model::ProjectData]
          def on_model_opened(model)
            key = key_for(model)
            entry = @sessions[key]
            @sessions.delete(key) if entry && !entry[:dirty]
            data(model)
          end

          # Применяет данные формы к объекту в памяти (без записи на диск)
          # @param model [Sketchup::Model, nil]
          # @param payload [Hash]
          # @return [Model::ProjectData]
          def apply(model, payload)
            pd = data(model)
            pd.apply_payload!(payload)
            entry = @sessions[key_for(model)]
            entry[:dirty] = true if entry
            pd
          end

          # Обновляет параметры рамки кадра в памяти (без записи на диск)
          # @param model [Sketchup::Model, nil]
          # @param params [Hash]
          # @return [Model::ProjectData]
          def update_frame_settings(model, params)
            pd = data(model)
            pd.update_frame_settings(params)
            entry = @sessions[key_for(model)]
            entry[:dirty] = true if entry
            pd
          end

          # Записывает на диск сессию модели: project.yaml в папке артикула
          # (без артикула проект не пишется) + settings.yaml + layout.yaml расширения.
          # @param model [Sketchup::Model, nil]
          # @return [Boolean]
          def flush(model)
            entry = @sessions[key_for(model)]
            flush_model_entry(entry, model)
          end

          # Записывает все измененные сессии (вызывается при закрытии SketchUp).
          # @return [Integer] количество успешно записанных сессий
          def flush_all
            saved = 0
            @sessions.each_value do |entry|
              next unless entry[:dirty]

              saved += 1 if flush_model_entry(entry, entry[:model])
            end
            saved
          end

          # Сбрасывает сессию модели и перечитывает данные из YAML с диска
          # @param model [Sketchup::Model, nil]
          # @return [Model::ProjectData]
          def reload(model)
            @sessions.delete(key_for(model))
            data(model)
          end

          # Импорт данных проекта из YAML файла: заменяет данные сессии в памяти.
          # Секция pdf_settings из файла игнорируется (глобальные настройки — settings.yaml).
          # Запись на диск не выполняется.
          # @param model [Sketchup::Model, nil]
          # @param file_path [String]
          # @return [Model::ProjectData, nil]
          def import_project_yaml(model, file_path)
            return nil unless file_path && File.exist?(file_path)

            pd = ProjectData.new
            return nil unless pd.load_from_yaml(file_path, include_settings: false)

            pd.sync_with_model_scenes(model) if model
            @sessions[key_for(model)] = {
              data:           pd,
              model:          model,
              model_path:     model_path_of(model),
              articul_before: pd.project[:articul].to_s.dup,
              dirty:          true
            }
            pd
          rescue StandardError => e
            warn "[DN1C Export PDF] Ошибка импорта YAML: #{e.message}"
            nil
          end

          # Есть ли несохраненные изменения у модели
          # @param model [Sketchup::Model, nil]
          # @return [Boolean]
          def dirty?(model)
            entry = @sessions[key_for(model)]
            entry ? entry[:dirty] : false
          end

          private

          def flush_model_entry(entry, model)
            return false unless entry

            pd = entry[:data]
            m = model || entry[:model]
            pd.sync_with_model_scenes(m) if m
            ok_yaml = pd.save_project_yaml(m, previous_articul: entry[:articul_before])
            ok_cfg  = pd.save_program_settings
            entry[:articul_before] = pd.project[:articul].to_s.dup
            entry[:dirty] = false
            ok_yaml || ok_cfg
          rescue StandardError => e
            warn "[DN1C Export PDF] Ошибка сохранения сессии: #{e.message}"
            false
          end

          def key_for(model)
            p = model_path_of(model)
            p.empty? ? "obj:#{model ? model.object_id : :none}" : "path:#{p}"
          end

          def model_path_of(model)
            return "" unless model && model.respond_to?(:path)

            model.path.to_s.tr("\\", "/").downcase
          end
        end
      end
    end
  end
end
