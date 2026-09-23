# frozen_string_literal: true

require "json"
require "fileutils"
require_relative "../model/path_util"
require_relative "../model/project_data"
require_relative "../controller/export_controller"

module DN1Code
  module ExportPdf2
    module Dialog
      class ExportDialog
        @dialog = nil

        def self.refresh_if_open(model = nil)
          if @dialog && @dialog.visible?
            model ||= (defined?(Sketchup) ? Sketchup.active_model : nil)
            return unless model

            Service::ObserverService.handle_model_opened(model, false) if defined?(Service::ObserverService)

            project_data = Model::SessionStore.data(model)

            json_str = JSON.generate(project_data.to_h)
            @dialog.execute_script("window.app && window.app.loadData(#{json_str});")
          end
        end

        def self.show_dialog
          model = (defined?(Sketchup) && Sketchup.respond_to?(:active_model)) ? Sketchup.active_model : nil
          if model && model.respond_to?(:path) && !model.path.to_s.empty?
            Service::ObserverService.handle_model_opened(model, false) if defined?(Service::ObserverService)
          end

          if @dialog && @dialog.visible?
            @dialog.bring_to_front
            refresh_if_open(model)
            return
          end

          options = {
            dialog_title:    "DN1C Export PDF 2 — Экспорт сцен в PDF",
            preferences_key: "DN1C_ExportPdf2_Pref",
            scrollable:      true,
            resizable:       true,
            width:           980,
            height:          700,
            left:            120,
            top:             80,
            min_width:       720,
            min_height:      520,
            style:           UI::HtmlDialog::STYLE_DIALOG
          }

          @dialog = UI::HtmlDialog.new(options)
          html_path = File.join(__dir__, "html", "index.html")
          @dialog.set_file(html_path)

          setup_callbacks(@dialog)
          @dialog.show
        end

        def self.populate_project_data(project_data, payload)
          project_data.apply_payload!(payload)
        end

        def self.setup_callbacks(dialog)
          # Загрузка данных проекта в веб-интерфейс (из сессии памяти, первично YAML рядом с моделью)
          dialog.add_action_callback("getData") do |_action_context|
            model = Sketchup.active_model
            if model && model.respond_to?(:path) && !model.path.to_s.empty?
              Service::ObserverService.handle_model_opened(model, false) if defined?(Service::ObserverService)
            end

            project_data = Model::SessionStore.data(model)
            if defined?(Service::OverlayService)
              project_data.pdf_settings[:show_aspect_overlay] = Service::OverlayService.overlay_active?(model)
            end

            # Формат снимков не настраивается: WebP при доступной libvips, иначе PNG.
            # Флаг передается отдельным ключом верхнего уровня (to_h возвращает живые ссылки —
            # писать внутрь pdf_settings нельзя, иначе ключ уйдёт в settings.yaml).
            payload = project_data.to_h
            payload[:vips_available] = Service::VipsService.available? if defined?(Service::VipsService)
            json_str = JSON.generate(payload)
            dialog.execute_script("window.app && window.app.loadData(#{json_str});")
          end
          # Переключение видимости рамки пропорций кадра через Sketchup::Overlay
          dialog.add_action_callback("toggleAspectOverlay") do |_action_context, enabled_val|
            model = Sketchup.active_model
            is_on = enabled_val == true || enabled_val.to_s == "true"
            if defined?(Service::OverlayService)
              if is_on
                info = Service::OverlayService.calculate_target_info(model)
                if info[:visible] == false
                  Service::OverlayService.disable(model)
                  is_on = false
                else
                  Service::OverlayService.enable(model)
                end
              else
                Service::OverlayService.disable(model)
              end
              Model::SessionStore.update_frame_settings(model, { show_aspect_overlay: is_on }) if defined?(Model::SessionStore)
              active = Service::OverlayService.overlay_active?(model)
              dialog.execute_script("window.app && window.app.syncOverlayState && window.app.syncOverlayState(#{active});")
            end
          end

          # Обновление настроек пропорций кадра и перерисовка окна SketchUp
          dialog.add_action_callback("updateAspectSettings") do |_action_context, params_json|
            begin
              params = params_json.is_a?(Hash) ? params_json : (JSON.parse(params_json.to_s, symbolize_names: true) rescue {})
              model = Sketchup.active_model
              if defined?(Service::OverlayService)
                Service::OverlayService.update_settings(params, model)
                # Параметры рамки — только в память сессии (запись в settings.yaml при flush)
                Model::SessionStore.update_frame_settings(model, params) if defined?(Model::SessionStore)
                info = Service::OverlayService.calculate_target_info(model)
                dialog.execute_script("window.app && window.app.syncOverlayState && window.app.syncOverlayState(true);")
                dialog.execute_script("window.app && window.app.updateAspectInfo && window.app.updateAspectInfo(#{JSON.generate(info)});")
                if defined?(UI) && UI.respond_to?(:start_timer)
                  UI.start_timer(0.02, false) do
                    begin
                      active = Service::OverlayService.overlay_active?(model)
                      dialog.execute_script("window.app && window.app.syncOverlayState && window.app.syncOverlayState(#{active});")
                    rescue StandardError
                    end
                  end
                end
              end
            rescue StandardError
            end
          end

          # Создание папки проекта по артикулу рядом с рабочим файлом .skp и первичная
          # запись project.yaml. Вызывается после выбора типа проекта при открытии панели
          # (см. articulTypeModal): { articul: "CF#..." }
          dialog.add_action_callback("createProjectFolder") do |_action_context, params_json|
            begin
              params = begin
                JSON.parse(params_json.to_s, symbolize_names: true)
              rescue StandardError
                {}
              end
              articul = params[:articul].to_s.strip
              if articul.empty?
                dialog.execute_script("window.app && window.app.showNotification('Артикул не передан — папка проекта не создана', 'error');")
              else
                model = (defined?(Sketchup) && Sketchup.respond_to?(:active_model)) ? Sketchup.active_model : nil
                project_data = Model::SessionStore.data(model)
                project_data.project_info[:articul] = articul if project_data.project_info[:articul].to_s.strip.empty?
                project_data.sync_with_model_scenes(model) if model
                # Артикул сразу пишется в атрибуты модели (.skp): попадает в файл
                # при ближайшем сохранении модели (Ctrl+S) — после этого папка
                # проекта определяется по самому файлу при любом открытии
                Model::ModelArticulStore.write(model, articul) if model

                art_dir = project_data.articul_dir_for_model(model)
                if art_dir.nil? || art_dir.to_s.empty?
                  dialog.execute_script("window.app && window.app.showNotification('Сначала сохраните модель SketchUp (Ctrl+S) — папка проекта создается рядом с рабочим файлом', 'error');")
                else
                  begin
                    FileUtils.mkdir_p(art_dir)
                  rescue StandardError => e
                    puts "[createProjectFolder] mkdir_p: #{e.message}"
                  end
                  yaml_ok = project_data.save_project_yaml(model)
                  dialog.execute_script("window.app && window.app.onProjectFolderCreated(#{JSON.generate(art_dir)}, #{yaml_ok});")
                end
              end
            rescue StandardError => e
              dialog.execute_script("window.app && window.app.showNotification('Ошибка создания папки проекта: #{e.message}', 'error');")
            end
          end

          # Генератор идентификатора заказчика (CUST-...)
          dialog.add_action_callback("generateCustomerId") do |_action_context, name|
            cid = Model::ProjectData.generate_customer_id(name: name)
            dialog.execute_script("window.app && window.app.onCustomerIdGenerated(#{JSON.generate(cid)});")
          end

          # Интерактивный диалог выбора папки проекта в проводнике
          dialog.add_action_callback("selectDirectory") do |_action_context, row_index|
            model = Sketchup.active_model
            default_dir = ""
            if model && model.respond_to?(:path) && !model.path.to_s.empty?
              default_dir = File.dirname(model.path)
            end

            chosen_folder = UI.select_directory(
              title:     "Выберите рабочую папку проекта",
              directory: default_dir
            )

            if chosen_folder && !chosen_folder.to_s.empty?
              rel_path = chosen_folder
              if !default_dir.empty?
                model_dir_norm = File.expand_path(default_dir).tr("\\", "/")
                chosen_norm    = File.expand_path(chosen_folder).tr("\\", "/")
                if chosen_norm.start_with?(model_dir_norm + "/")
                  rel_path = chosen_norm.sub(model_dir_norm + "/", "")
                elsif chosen_norm == model_dir_norm
                  rel_path = "./"
                end
              end

              idx = row_index.to_i
              dialog.execute_script("window.app && window.app.onDirectorySelected(#{idx}, #{JSON.generate(rel_path)});")
            end
          end

          # Получить список файлов и превью для заданной папки
          dialog.add_action_callback("getFolderFiles") do |_action_context, params_json|
            idx = 0
            folder_raw = ""
            begin
              params = if params_json.is_a?(Hash)
                         params_json
                       elsif params_json.is_a?(String)
                         (JSON.parse(params_json.to_s.force_encoding("UTF-8"), symbolize_names: true) rescue {})
                       else
                         {}
                       end
              idx = (params[:index] || params["index"] || 0).to_i
              folder_raw = (params[:path] || params["path"] || "").to_s.strip
              folder_rel = folder_raw.tr("\\", "/")

              model = Sketchup.active_model
              model_dir = ""
              if model && model.respond_to?(:path) && !model.path.to_s.empty?
                model_dir = File.dirname(model.path.to_s.tr("\\", "/"))
              end

              candidates = []
              candidates << folder_rel if File.directory?(folder_rel)
              candidates << File.expand_path(folder_rel) if File.directory?(File.expand_path(folder_rel))
              if !model_dir.empty?
                c_model = File.expand_path(File.join(model_dir, folder_rel))
                candidates << c_model if File.directory?(c_model)
              end
              c_pwd = File.expand_path(File.join(Dir.pwd, folder_rel))
              candidates << c_pwd if File.directory?(c_pwd)

              parent_dir = File.expand_path(File.join(__dir__, "../../.."))
              c_parent = File.expand_path(File.join(parent_dir, folder_rel))
              candidates << c_parent if File.directory?(c_parent)

              folder_abs = candidates.find { |p| Dir.exist?(p) }
              files_list = []
              exists = !folder_abs.nil?

              if exists
                require "base64" unless defined?(Base64)
                entries = begin
                            Dir.children(folder_abs)
                          rescue StandardError
                            Dir.entries(folder_abs).reject { |n| n == "." || n == ".." }
                          end

                total_b64_bytes = 0
                max_total_b64 = 4_500_000 # 4.5 MB base64 safety limit per folder to avoid CEF IPC stall

                entries.sort.each do |fname|
                  next if fname.start_with?(".") || fname.start_with?("~")
                  f = File.join(folder_abs, fname)
                  next unless File.file?(f)
                  ext = File.extname(f).downcase
                  is_img = %w[.jpg .jpeg .png .webp .bmp .gif].include?(ext)
                  norm_path = f.tr("\\", "/")
                  f_size = begin
                             File.size(f)
                           rescue StandardError
                             0
                           end

                  data_url = nil
                  if is_img && f_size > 0 && f_size <= 2_000_000 && (total_b64_bytes + f_size) <= max_total_b64
                    begin
                      mime = case ext
                             when ".jpg", ".jpeg" then "image/jpeg"
                             when ".png"          then "image/png"
                             when ".webp"         then "image/webp"
                             when ".gif"          then "image/gif"
                             when ".bmp"          then "image/bmp"
                             else "image/jpeg"
                             end
                      b64 = Base64.strict_encode64(File.binread(f))
                      total_b64_bytes += b64.bytesize
                      data_url = "data:#{mime};base64,#{b64}"
                    rescue StandardError
                      data_url = nil
                    end
                  end

                  files_list << {
                    name:     fname,
                    path:     norm_path,
                    url:      data_url || ("file:///" + norm_path),
                    size:     f_size,
                    ext:      ext.sub(/^\./, "").upcase,
                    is_image: is_img
                  }

                  break if files_list.size >= 50 # Limit preview cards to 50 items
                end
              end

              resp = {
                index:     idx,
                path:      folder_raw,
                exists:    exists,
                full_path: folder_abs ? folder_abs.tr("\\", "/") : "",
                files:     files_list
              }
              json_payload = JSON.generate(resp)
              dialog.execute_script("window.app && window.app.onFolderFilesLoaded(#{json_payload});")
            rescue StandardError => e
              puts "[getFolderFiles error]: #{e.message}"
              fallback = { index: idx || 0, path: folder_raw || "", exists: false, full_path: "", files: [], error: e.message }
              dialog.execute_script("window.app && window.app.onFolderFilesLoaded(#{JSON.generate(fallback)});") rescue nil
            end
          end

          # Актуализация списка сцен при открытии вкладки «Страницы»:
          # добавляет новые страницы модели, убирает удалённые и возвращает
          # актуальный список в UI (без записи на диск — как автосейв)
          dialog.add_action_callback("refreshScenes") do |_action_context|
            begin
              model = Sketchup.active_model
              project_data = Model::SessionStore.data(model)
              project_data.sync_with_model_scenes(model) if model && model.respond_to?(:pages)
              scenes_json = JSON.generate(project_data.scenes.map(&:to_h))
              dialog.execute_script("window.app && window.app.onScenesRefreshed && window.app.onScenesRefreshed(#{scenes_json});")
            rescue StandardError => e
              puts "[refreshScenes error]: #{e.message}"
            end
          end

          # Получить быстрые мини-превью (thumbnails) для сцен модели SketchUp
          dialog.add_action_callback("getSceneThumbnails") do |_action_context|
            begin
              model = Sketchup.active_model
              thumbs = {}
              if model && model.respond_to?(:pages) && model.pages.count > 0 && model.respond_to?(:active_view) && model.active_view
                require "base64" unless defined?(Base64)
                cur_page = model.pages.selected_page rescue nil
                orig_tt = nil
                if model.respond_to?(:options) && model.options["PageOptions"]
                  orig_tt = model.options["PageOptions"]["TransitionTime"] rescue nil
                  model.options["PageOptions"]["TransitionTime"] = 0 rescue nil
                end

                ro = model.respond_to?(:rendering_options) ? model.rendering_options : nil
                orig_dims = ro ? (ro["DisplayDims"] rescue nil) : nil
                orig_text = ro ? (ro["DisplayText"] rescue nil) : nil
                orig_axes = ro ? (ro["DisplaySketchAxes"] rescue nil) : nil
                orig_guides = ro ? (ro["HideConstructionGeometry"] rescue nil) : nil
                orig_sec_planes = ro ? (ro["DisplaySectionPlanes"] rescue nil) : nil

                # Карта «имя страницы → показывать ли фон»: эскизы подчиняются той же
                # глобальной галке «Фон», что и видовые экраны PDF/экспорта.
                # По умолчанию фон выключен.
                bg_by_name = {}
                if defined?(Model::SessionStore)
                  pd = Model::SessionStore.data(model) rescue nil
                  scenes = pd ? (pd.scenes || []) : []
                  scenes.each do |sc|
                    bg = !(sc.respond_to?(:viewport_background) && sc.viewport_background == false)
                    bg_by_name[sc.original_name] = bg if sc.respond_to?(:original_name)
                    bg_by_name[sc.name] = bg if sc.respond_to?(:name)
                  end
                end

                begin
                  model.pages.each_with_index do |p, i|
                    p_name = p.respond_to?(:name) ? p.name : p.to_s
                    if model.pages.respond_to?(:selected_page=)
                      model.pages.selected_page = p rescue nil
                    end

                    # Отключаем размеры, текстовые метки, оси и направляющие, чтобы они не перекрывали мини-эскиз
                    if ro
                      ro["DisplayDims"] = false rescue nil
                      ro["DisplayText"] = false rescue nil
                      ro["DisplaySketchAxes"] = false rescue nil
                      ro["HideConstructionGeometry"] = true rescue nil
                      ro["DisplaySectionPlanes"] = false rescue nil
                    end

                    # Гашение фона (небо/земля/водяные знаки) для сцен с выключенной галкой
                    show_bg = bg_by_name.fetch(p_name, false)
                    orig_bg = defined?(Service::RenderService) ? Service::RenderService.apply_background_override(ro, show_bg) : {}

                    tmp = File.join(Dir.tmpdir, "dn1c_scene_thumb_#{i}_#{Time.now.to_i}.jpg").tr("\\", "/")
                    model.active_view.write_image(filename: tmp, width: 360, height: 240, antialias: false) rescue nil
                    Service::RenderService.restore_background(ro, orig_bg) if defined?(Service::RenderService)
                    if File.exist?(tmp)
                      b64 = Base64.strict_encode64(File.binread(tmp)) rescue nil
                      thumbs[p_name] = "data:image/jpeg;base64,#{b64}" if b64
                      File.delete(tmp) rescue nil
                    end
                  end
                ensure
                  if ro
                    ro["DisplayDims"] = orig_dims unless orig_dims.nil? rescue nil
                    ro["DisplayText"] = orig_text unless orig_text.nil? rescue nil
                    ro["DisplaySketchAxes"] = orig_axes unless orig_axes.nil? rescue nil
                    ro["HideConstructionGeometry"] = orig_guides unless orig_guides.nil? rescue nil
                    ro["DisplaySectionPlanes"] = orig_sec_planes unless orig_sec_planes.nil? rescue nil
                  end
                  if cur_page && model.pages.respond_to?(:selected_page=)
                    model.pages.selected_page = cur_page rescue nil
                  end
                  if orig_tt && model.respond_to?(:options) && model.options["PageOptions"]
                    model.options["PageOptions"]["TransitionTime"] = orig_tt rescue nil
                  end
                end
              end
              dialog.execute_script("window.app && window.app.onSceneThumbnailsLoaded && window.app.onSceneThumbnailsLoaded(#{JSON.generate(thumbs)});")
            rescue StandardError => e
              puts "[getSceneThumbnails error]: #{e.message}"
              # Обязательно снимаем флаг ожидания в UI, иначе эскизы больше не запросятся
              dialog.execute_script("window.app && window.app.onSceneThumbnailsLoaded && window.app.onSceneThumbnailsLoaded({});") rescue nil
            end
          end

          # Переключить активную сцену в SketchUp по выбору из веб-интерфейса
          dialog.add_action_callback("selectScene") do |_action_context, param_json|
            begin
              model = Sketchup.active_model
              next unless model && model.respond_to?(:pages) && model.pages.count > 0

              params = if param_json.is_a?(Hash)
                         param_json
                       elsif param_json.is_a?(String)
                         (JSON.parse(param_json.to_s.force_encoding("UTF-8"), symbolize_names: true) rescue { name: param_json.to_s })
                       else
                         { index: param_json.to_i }
                       end

              orig_name = (params[:original_name] || params["original_name"]).to_s.strip
              cur_name  = (params[:name] || params["name"]).to_s.strip
              idx       = params[:index] || params["index"]

              page = nil
              page = model.pages[orig_name] unless orig_name.empty?
              page = model.pages[cur_name] if page.nil? && !cur_name.empty?
              if page.nil? && !idx.nil?
                idx_i = idx.to_i
                page = model.pages[idx_i] if idx_i >= 0 && idx_i < model.pages.count
              end

              if page && model.pages.respond_to?(:selected_page=)
                model.pages.selected_page = page

                # Если активен Overlay безопасной рамки кадра, обновляем его под пропорции выбранной сцены
                if defined?(Service::OverlayService)
                  info = Service::OverlayService.calculate_target_info(model)
                  if info[:visible] == false
                    Service::OverlayService.disable(model)
                    dialog.execute_script("window.app && window.app.syncOverlayState && window.app.syncOverlayState(false);") rescue nil
                  elsif Service::OverlayService.overlay_active?(model)
                    Service::OverlayService.refresh(model)
                    dialog.execute_script("window.app && window.app.updateAspectInfo && window.app.updateAspectInfo(#{JSON.generate(info)});") rescue nil
                  end
                end
              end
            rescue StandardError => e
              puts "[selectScene error]: #{e.message}"
            end
          end

          # Открыть папку на диске через проводник
          dialog.add_action_callback("openDirectoryPath") do |_action_context, folder_raw|
            begin
              folder_rel = folder_raw.to_s.strip.tr("\\", "/")
              model = Sketchup.active_model
              model_dir = ""
              if model && model.respond_to?(:path) && !model.path.to_s.empty?
                model_dir = File.dirname(model.path.to_s.tr("\\", "/"))
              end

              candidates = []
              candidates << folder_rel if File.directory?(folder_rel)
              candidates << File.expand_path(folder_rel) if File.directory?(File.expand_path(folder_rel))
              if !model_dir.empty?
                c_model = File.expand_path(File.join(model_dir, folder_rel))
                candidates << c_model if File.directory?(c_model)
              end
              c_pwd = File.expand_path(File.join(Dir.pwd, folder_rel))
              candidates << c_pwd if File.directory?(c_pwd)

              parent_dir = File.expand_path(File.join(__dir__, "../../.."))
              c_parent = File.expand_path(File.join(parent_dir, folder_rel))
              candidates << c_parent if File.directory?(c_parent)

              folder_abs = candidates.find { |p| Dir.exist?(p) }

              if folder_abs && File.exist?(folder_abs)
                Model::FileOpener.open_path(folder_abs)
              else
                UI.messagebox("Папка не найдена на диске:\n#{folder_raw}")
              end
            rescue StandardError => e
              puts "[openDirectoryPath error]: #{e.message}"
            end
          end

          # Применить данные формы к сессии в памяти (без записи на диск)
          # Кнопка «Обновить» удалена: изменения формы применяются автосохранением

          # Принудительное сохранение: YAML проекта рядом с .skp + настройки PDF и шаблоны
          # в YAML файлы расширения (settings.yaml + layout.yaml)
          dialog.add_action_callback("saveProjectYaml") do |_action_context, data_json|
            begin
              payload = JSON.parse(data_json, symbolize_names: true)
              model = (defined?(Sketchup) && Sketchup.respond_to?(:active_model)) ? Sketchup.active_model : nil
              project_data = Model::SessionStore.apply(model, payload)
              project_data.sync_with_model_scenes(model) if model

              ok = Model::SessionStore.flush(model) if defined?(Model::SessionStore)

              if ok
                yaml_name = Model::ProjectData::PROJECT_YAML_NAME
                dialog.execute_script("window.app && window.app.showNotification('Сохранено: YAML проекта (#{yaml_name}) + настройки PDF и шаблоны расширения', 'success');")
                if defined?(Sketchup) && Sketchup.respond_to?(:status_text=)
                  Sketchup.status_text = "DN1C Export PDF: Данные сохранены (#{yaml_name} + settings.yaml + layout.yaml)"
                end
              elsif project_data.project_info[:articul].to_s.strip.empty?
                dialog.execute_script("window.app && window.app.showNotification('Артикул не указан — данные проекта не сохранены. Создайте артикул и повторите сохранение.', 'error');")
              else
                dialog.execute_script("window.app && window.app.showNotification('Не удалось сохранить: сохраните модель SketchUp (Ctrl+S), чтобы появился путь для YAML', 'error');")
              end
            rescue StandardError => e
              dialog.execute_script("window.app && window.app.showNotification('Ошибка сохранения YAML: #{e.message}', 'error');")
            end
          end

          # Сохранение настроек из веб-интерфейса.
          # Автосейв (is_auto_save/silent) применяет данные только к сессии в памяти.
          # Явное сохранение пишет YAML проекта + настройки/шаблоны расширения.
          save_handler = lambda do |_action_context, data_json|
            begin
              payload = JSON.parse(data_json, symbolize_names: true)
              model = (defined?(Sketchup) && Sketchup.respond_to?(:active_model)) ? Sketchup.active_model : nil
              project_data = Model::SessionStore.apply(model, payload)

              is_auto = payload[:silent] == true || payload[:is_auto_save] == true

              if is_auto
                # Автосейв: данные живут в памяти до flush (кнопка/экспорт/закрытие)
                dialog.execute_script("window.app && window.app.onAutoSaved && window.app.onAutoSaved(#{JSON.generate("в память")});")
              else
                project_data.sync_with_model_scenes(model) if model
                ok = Model::SessionStore.flush(model) if defined?(Model::SessionStore)
                yaml_name = Model::ProjectData::PROJECT_YAML_NAME
                if ok
                  dialog.execute_script("window.app && window.app.showNotification('Сохранено в YAML (#{yaml_name}) + настройки расширения', 'success');")
                elsif project_data.project_info[:articul].to_s.strip.empty?
                  dialog.execute_script("window.app && window.app.showNotification('Артикул не указан — данные проекта не сохранены. Создайте артикул и повторите сохранение.', 'error');")
                else
                  dialog.execute_script("window.app && window.app.showNotification('Не удалось сохранить: сохраните модель SketchUp (Ctrl+S), чтобы появился путь для YAML', 'error');")
                end
              end

              if defined?(Service::OverlayService) && model
                info = Service::OverlayService.calculate_target_info(model)
                if info[:visible] == false && Service::OverlayService.overlay_active?(model)
                  Service::OverlayService.disable(model)
                  dialog.execute_script("window.app && window.app.syncOverlayState && window.app.syncOverlayState(false);") rescue nil
                end
              end
            rescue StandardError => e
              dialog.execute_script("window.app && window.app.showNotification('Ошибка сохранения: #{e.message}', 'error');")
            end
          end

          dialog.add_action_callback("saveData", &save_handler)

          # Запуск экспорта в PDF
          dialog.add_action_callback("startExport") do |_action_context, data_json|
            # Экспорт выполняется отложенно через таймер: колбэк CEF завершается сразу,
            # диалог не блокируется и прогресс-бар перерисовывается в реальном времени
            run_export = lambda do
              begin
                payload = JSON.parse(data_json, symbolize_names: true)
                model = Sketchup.active_model
                project_data = Model::SessionStore.apply(model, payload)

                project_data.sync_with_model_scenes(model)
                # Принудительная запись на диск перед экспортом (защита от потери данных)
                Model::SessionStore.flush(model) if defined?(Model::SessionStore)

                controller = Controller::ExportController.new(project_data, model)

                pdf_file = controller.export do |curr, total, msg|
                  percent = (curr.to_f / total * 100).round
                  dialog.execute_script("window.app && window.app.updateProgress(#{percent}, #{JSON.generate(msg)});")
                end

                # Привязываем PDF этого экспорта к самой свежей записи истории изменений
                if project_data.respond_to?(:stamp_history_pdf_link!) && project_data.stamp_history_pdf_link!(pdf_file.to_s)
                  Model::SessionStore.flush(model) if defined?(Model::SessionStore)
                end

                last_pdf  = controller.respond_to?(:last_pdf_path) ? controller.last_pdf_path : nil
                escaped_path = JSON.generate(pdf_file)
                new_rev = project_data.project_info[:revision] || 1
                dialog.execute_script("window.app && window.app.onExportSuccess(#{escaped_path}, #{new_rev}, #{JSON.generate(last_pdf)});")
              rescue StandardError => e
                dialog.execute_script("window.app && window.app.onExportError(#{JSON.generate(e.message)});")
              end
            end

            if defined?(UI) && UI.respond_to?(:start_timer)
              UI.start_timer(0.01, false) { run_export.call }
            else
              # Резерв для окружений без таймера (автономные тесты)
              run_export.call
            end
          end

          # Открыть папку с PDF
          dialog.add_action_callback("openFolder") do |_action_context, file_path|
            begin
              clean_path = file_path.to_s.strip.tr("\\", "/")
              if clean_path.empty?
                # Пустая ссылка — открывать нечего
              elsif File.exist?(clean_path)
                Model::FileOpener.open_path(File.dirname(clean_path))
              else
                UI.messagebox("Папка не найдена на диске:\n#{clean_path}")
              end
            rescue StandardError => e
              puts "[openFolder error]: #{e.message}"
            end
          end

          # Открыть файл (изображение, документ, чертеж, текст) системной программой по умолчанию
          dialog.add_action_callback("openFile") do |_action_context, file_path|
            begin
              clean_path = file_path.to_s.strip.tr("\\", "/")
              if clean_path.empty?
                # Пустая ссылка — открывать нечего
              elsif File.exist?(clean_path)
                Model::FileOpener.open_path(clean_path)
              else
                UI.messagebox("Файл не найден на диске:\n#{clean_path}")
              end
            rescue StandardError => e
              puts "[openFile error]: #{e.message}"
            end
          end

          # Экспорт настроек в YAML
          dialog.add_action_callback("exportYaml") do |_action_context, data_json|
            save_path = UI.savepanel("Экспортировать настройки в YAML", "", "project.yaml")
            if save_path
              begin
                payload = JSON.parse(data_json, symbolize_names: true)
                project_data = Model::ProjectData.new
                populate_project_data(project_data, payload)

                project_data.save_to_yaml(save_path)
                dialog.execute_script("window.app && window.app.showNotification('YAML успешно сохранен', 'success');")
              rescue StandardError => e
                dialog.execute_script("window.app && window.app.showNotification('Ошибка: #{e.message}', 'error');")
              end
            end
          end

          # Импорт данных проекта из YAML (в память; запись на диск — принудительным сохранением)
          dialog.add_action_callback("importYaml") do |_action_context|
            yaml_file = UI.openpanel("Открыть файл YAML конфигурации", "", "YAML Files|*.yaml;*.yml||")
            if yaml_file && File.exist?(yaml_file)
              model = Sketchup.active_model
              project_data = Model::SessionStore.import_project_yaml(model, yaml_file) if defined?(Model::SessionStore)
              if project_data
                json_str = JSON.generate(project_data.to_h)
                dialog.execute_script("window.app && window.app.loadData(#{json_str});")
                dialog.execute_script("window.app && window.app.showNotification('Данные проекта импортированы в память из #{File.basename(yaml_file.to_s.tr("\\", "/"))}. Запись на диск — кнопкой «Принудительно сохранить»', 'success');")
              else
                dialog.execute_script("window.app && window.app.showNotification('Не удалось прочитать YAML файл: #{File.basename(yaml_file.to_s)}', 'error');")
              end
            end
          end
        end
      end
    end
  end
end
