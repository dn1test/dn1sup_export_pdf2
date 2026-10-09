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

        # Синхронизирует открытую панель со сменой активной страницы SketchUp
        # (нативное переключение вкладками сцен): выделение сцены, подписи рамки,
        # состояние переключателя оверлея. info — результат OverlayService.on_page_changed.
        # info == nil значит «страница не изменилась» (дедупликация повторного
        # уведомления) — правильное состояние уже отправлено, пушить нечего.
        # @param info [Hash, nil]
        # @return [void]
        def self.notify_active_scene(info)
          return unless info.is_a?(Hash)

          dlg = @dialog
          return unless dlg && dlg.visible?

          idx = info[:scene_index]
          idx_js = idx.nil? ? "null" : idx.to_i.to_s
          overlay_on = info[:overlay_on] == true && info[:visible] != false

          begin
            dlg.execute_script("window.app && window.app.onActiveSceneChanged && window.app.onActiveSceneChanged(#{idx_js});")
            dlg.execute_script("window.app && window.app.updateAspectInfo && window.app.updateAspectInfo(#{JSON.generate(info)});")
            dlg.execute_script("window.app && window.app.syncOverlayState && window.app.syncOverlayState(#{overlay_on});")
          rescue StandardError => e
            warn "[DN1Sup Export PDF] Не удалось синхронизировать панель со сменой страницы: #{e.message}"
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
            dialog_title:    "#{NAME_EXTENSION} v#{PLUGIN_VERSION}#{Locale.t(:dialog_title_suffix)}",
            preferences_key: "DN1SUP_ExportPdf2_Pref",
            scrollable:      true,
            resizable:       true,
            width:           980,
            height:          700,
            left:            120,
            top:             80,
            # Минимальная ширина = естественная ширина панели вкладок (~856px),
            # чтобы верхнее меню никогда не прокручивалось горизонтально
            min_width:       860,
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

        # Безопасная отправка уведомления в диалог: сообщение проходит через
        # JSON.generate, поэтому апострофы/кавычки/переводы строк в тексте
        # (пути файлов, имена наборов, e.message) не ломают JS-строку
        def self.notify_js(dialog, message, type)
          dialog.execute_script(
            "window.app && window.app.showNotification(#{JSON.generate(message.to_s)}, #{JSON.generate(type.to_s)});"
          )
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
            payload[:plugin_version] = PLUGIN_VERSION
            payload[:plugins_dir] = Service::DevUpdater.resolve_plugins_dir if defined?(Service::DevUpdater)
            payload[:vips_available] = Service::VipsService.available? if defined?(Service::VipsService)
            payload[:template_sets] = project_data.list_template_sets
            json_str = JSON.generate(payload)
            dialog.execute_script("window.app && window.app.loadData(#{json_str});")
          end
          # Переключение рамки кадра в окне SketchUp. Принимает булево (только
          # вкл/выкл оверлея) либо JSON: { enabled, scene_index, all } — тогда
          # перед пересчётом сразу обновляется постраничный флаг frame_overlay
          # в сессии (не дожидаясь автосохранения из диалога).
          dialog.add_action_callback("toggleAspectOverlay") do |_action_context, enabled_val|
            model = Sketchup.active_model
            is_on = enabled_val == true || enabled_val.to_s == "true"

            scope_idx = nil
            apply_all = false
            if enabled_val.is_a?(String) && enabled_val.include?("{")
              parsed = begin
                JSON.parse(enabled_val, symbolize_names: true)
              rescue StandardError
                {}
              end
              is_on = parsed[:enabled] == true || parsed[:enabled].to_s == "true"
              apply_all = parsed[:all] == true
              scope_idx = parsed[:scene_index].to_i if parsed[:scene_index]
            end

            if defined?(Model::SessionStore)
              pdata = Model::SessionStore.data(model)
              if pdata && pdata.scenes
                if apply_all
                  pdata.scenes.each { |sc| sc.frame_overlay = is_on }
                elsif scope_idx && scope_idx >= 0 && scope_idx < pdata.scenes.size
                  pdata.scenes[scope_idx].frame_overlay = is_on
                end
              end
            end

            if defined?(Service::OverlayService)
              if is_on
                info = Service::OverlayService.calculate_target_info(model)
                if info[:visible] == false || info[:overlay_on] == false
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
            rescue StandardError => e
              warn "[DN1Sup Export PDF] Ошибка updateAspectSettings: #{e.class}: #{e.message}"
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
                notify_js(dialog, Locale.t(:create_folder_no_articul), "error")
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
                  notify_js(dialog, Locale.t(:create_folder_save_model), "error")
                else
                  begin
                    FileUtils.mkdir_p(art_dir)
                  rescue StandardError => e
                    warn "[createProjectFolder] mkdir_p: #{e.message}"
                  end
                  yaml_ok = project_data.save_project_yaml(model)
                  dialog.execute_script("window.app && window.app.onProjectFolderCreated(#{JSON.generate(art_dir)}, #{yaml_ok});")
                end
              end
            rescue StandardError => e
              notify_js(dialog, Locale.t(:create_folder_error, msg: e.message), "error")
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
              title:     Locale.t(:select_dir_title),
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
              warn "[getFolderFiles error]: #{e.message}"
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
              warn "[refreshScenes error]: #{e.message}"
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

                # Карты «имя страницы → показывать ли фон / водяные знаки»: эскизы
                # подчиняются тем же глобальным галкам «Фон» и «Водяной знак», что и
                # видовые экраны PDF/экспорта. По умолчанию фон и знаки выключены.
                bg_by_name = {}
                wm_by_name = {}
                if defined?(Model::SessionStore)
                  pd = Model::SessionStore.data(model) rescue nil
                  scenes = pd ? (pd.scenes || []) : []
                  scenes.each do |sc|
                    bg = !(sc.respond_to?(:viewport_background) && sc.viewport_background == false)
                    bg_by_name[sc.original_name] = bg if sc.respond_to?(:original_name)
                    bg_by_name[sc.name] = bg if sc.respond_to?(:name)
                    wm = !(sc.respond_to?(:viewport_watermarks) && sc.viewport_watermarks == false)
                    wm_by_name[sc.original_name] = wm if sc.respond_to?(:original_name)
                    wm_by_name[sc.name] = wm if sc.respond_to?(:name)
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

                    # Гашение фона (небо/земля) и водяных знаков для сцен с выключенными галками
                    show_bg = bg_by_name.fetch(p_name, false)
                    orig_bg = defined?(Service::RenderService) ? Service::RenderService.apply_background_override(ro, show_bg) : {}
                    show_wm = wm_by_name.fetch(p_name, false)
                    orig_wm = defined?(Service::RenderService) ? Service::RenderService.apply_watermark_override(ro, show_wm) : {}

                    tmp = File.join(Dir.tmpdir, "dn1sup_scene_thumb_#{i}_#{Time.now.to_i}.jpg").tr("\\", "/")
                    model.active_view.write_image(filename: tmp, width: 360, height: 240, antialias: false) rescue nil
                    if defined?(Service::RenderService)
                      Service::RenderService.restore_background(ro, orig_bg)
                      Service::RenderService.restore_background(ro, orig_wm)
                    end
                    if File.exist?(tmp)
                      b64 = Base64.strict_encode64(File.binread(tmp)) rescue nil
                      thumbs[p_name] = "data:image/jpeg;base64,#{b64}" if b64
                      File.delete(tmp) rescue nil
                    end
                  end
                ensure
                  if ro
                    {
                      "DisplayDims" => orig_dims,
                      "DisplayText" => orig_text,
                      "DisplaySketchAxes" => orig_axes,
                      "HideConstructionGeometry" => orig_guides,
                      "DisplaySectionPlanes" => orig_sec_planes
                    }.each do |ro_key, ro_val|
                      next if ro_val.nil?

                      begin
                        ro[ro_key] = ro_val
                      rescue StandardError => e
                        warn "[DN1Sup Export PDF] Не удалось восстановить #{ro_key} после эскизов: #{e.message}"
                      end
                    end
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
              warn "[getSceneThumbnails error]: #{e.message}"
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

                # Рамка кадра обновляется под выбранную страницу той же логикой,
                # что и при нативном переключении сцен (OverlayService.on_page_changed)
                if defined?(Service::OverlayService)
                  info = Service::OverlayService.on_page_changed(model)
                  notify_active_scene(info)
                end
              end
            rescue StandardError => e
              warn "[selectScene error]: #{e.message}"
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
                UI.messagebox(Locale.t(:open_folder_missing, path: folder_raw))
              end
            rescue StandardError => e
              warn "[openDirectoryPath error]: #{e.message}"
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
                notify_js(dialog, Locale.t(:save_project_ok, yaml: yaml_name), "success")
                if defined?(Sketchup) && Sketchup.respond_to?(:status_text=)
                  Sketchup.status_text = Locale.t(:save_status_ok, yaml: yaml_name)
                end
              elsif project_data.project_info[:articul].to_s.strip.empty?
                notify_js(dialog, Locale.t(:save_articul_missing), "error")
              else
                notify_js(dialog, Locale.t(:save_no_path), "error")
              end
            rescue StandardError => e
              notify_js(dialog, Locale.t(:save_yaml_error, msg: e.message), "error")
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
                dialog.execute_script("window.app && window.app.onAutoSaved && window.app.onAutoSaved(#{JSON.generate(Locale.t(:save_memory_label))});")
              else
                project_data.sync_with_model_scenes(model) if model
                ok = Model::SessionStore.flush(model) if defined?(Model::SessionStore)
                yaml_name = Model::ProjectData::PROJECT_YAML_NAME
                if ok
                  notify_js(dialog, Locale.t(:save_ok, yaml: yaml_name), "success")
                elsif project_data.project_info[:articul].to_s.strip.empty?
                  notify_js(dialog, Locale.t(:save_articul_missing), "error")
                else
                  notify_js(dialog, Locale.t(:save_no_path), "error")
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
              notify_js(dialog, Locale.t(:save_error, msg: e.message), "error")
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
                last_skp  = controller.respond_to?(:last_skp_path) ? controller.last_skp_path : nil
                escaped_path = JSON.generate(pdf_file)
                new_rev = project_data.project_info[:revision] || 1
                dialog.execute_script("window.app && window.app.onExportSuccess(#{escaped_path}, #{new_rev}, #{JSON.generate(last_pdf)}, #{JSON.generate(last_skp)});")
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

          # Отправка проекта на сервер (вкладка «Отправка»). Подготовка: WebP-снимки
          # включенных сцен в <Артикул>/images/ через export_scene_snapshots.
          # Сетевая отправка будет добавлена позже — пока кнопка только готовит снимки.
          dialog.add_action_callback("startSend") do |_action_context, data_json|
            notify_js(dialog, Locale.t(:send_preparing), "info")

            run_send = lambda do
              begin
                payload = data_json.to_s.empty? ? {} : JSON.parse(data_json, symbolize_names: true)
                model = Sketchup.active_model
                project_data = Model::SessionStore.apply(model, payload)

                project_data.sync_with_model_scenes(model)

                controller = Controller::ExportController.new(project_data, model)

                snapshots = controller.export_scene_snapshots

                Model::SessionStore.flush(model) if defined?(Model::SessionStore)
                notify_js(
                  dialog,
                  Locale.t(:send_done, n: snapshots.size),
                  "success"
                )
              rescue StandardError => e
                notify_js(dialog, Locale.t(:send_error, msg: e.message), "error")
              end
            end

            if defined?(UI) && UI.respond_to?(:start_timer)
              UI.start_timer(0.01, false) { run_send.call }
            else
              # Резерв для окружений без таймера (автономные тесты)
              run_send.call
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
                UI.messagebox(Locale.t(:open_folder_missing, path: clean_path))
              end
            rescue StandardError => e
              warn "[openFolder error]: #{e.message}"
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
                UI.messagebox(Locale.t(:open_file_missing, path: clean_path))
              end
            rescue StandardError => e
              warn "[openFile error]: #{e.message}"
            end
          end

          # Открыть SKP-копию правки из истории. Точный путь (skp_link) фронт открывает
          # через openFile; сюда приходят только ver/rev записи — ищем файл по стандартным
          # местам сохранения копий: <Артикул>/skp/<Артикул>_NN#NNN.skp либо
          # фолбэк <папка модели>/<имя>_backup/<имя>_NN#NNN.skp
          dialog.add_action_callback("openHistorySkp") do |_action_context, data_json|
            begin
              params = JSON.parse(data_json.to_s, symbolize_names: true)
              ver = params[:ver].to_s
              rev = params[:rev].to_s
              if ver.empty? && rev.empty?
                # Запись без версии/ревизии — искать нечего
              else
                model = Sketchup.active_model
                project_data = Model::SessionStore.data(model)
                vrs = format("%02d#%03d", ver.to_i, rev.to_i)
                candidates = []

                art_dir  = project_data.articul_dir_for_model(model)
                art_name = project_data.class.articul_folder_name(project_data.project_info, model)
                candidates << File.join(art_dir, "skp", "#{art_name}_#{vrs}.skp") if art_dir && art_name

                model_path = model.respond_to?(:path) ? model.path.to_s : ""
                unless model_path.empty?
                  model_dir  = File.dirname(model_path.tr("\\", "/"))
                  model_base = File.basename(model_path, ".skp")
                  candidates << File.join(model_dir, "#{model_base}_backup", "#{model_base}_#{vrs}.skp")
                end

                found = candidates.find { |p| File.exist?(p) }
                if found
                  Model::FileOpener.open_path(found)
                else
                  UI.messagebox(Locale.t(:open_skp_not_found, path: candidates.last || vrs))
                end
              end
            rescue StandardError => e
              warn "[openHistorySkp error]: #{e.message}"
            end
          end

          # Экспорт настроек в YAML
          dialog.add_action_callback("exportYaml") do |_action_context, data_json|
            save_path = UI.savepanel(Locale.t(:export_yaml_title), "", "project.yaml")
            if save_path
              begin
                payload = JSON.parse(data_json, symbolize_names: true)
                project_data = Model::ProjectData.new
                populate_project_data(project_data, payload)

                project_data.save_to_yaml(save_path)
                notify_js(dialog, Locale.t(:export_yaml_ok), "success")
              rescue StandardError => e
                notify_js(dialog, Locale.t(:export_yaml_error, msg: e.message), "error")
              end
            end
          end

          # Импорт данных проекта из YAML (в память; запись на диск — принудительным сохранением)
          dialog.add_action_callback("importYaml") do |_action_context|
            yaml_file = UI.openpanel(Locale.t(:import_yaml_title), "", "YAML Files|*.yaml;*.yml||")
            if yaml_file && File.exist?(yaml_file)
              model = Sketchup.active_model
              project_data = Model::SessionStore.import_project_yaml(model, yaml_file) if defined?(Model::SessionStore)
              if project_data
                json_str = JSON.generate(project_data.to_h)
                dialog.execute_script("window.app && window.app.loadData(#{json_str});")
                notify_js(dialog, Locale.t(:import_yaml_ok, file: File.basename(yaml_file.to_s.tr("\\", "/"))), "success")
              else
                notify_js(dialog, Locale.t(:import_yaml_fail, file: File.basename(yaml_file.to_s)), "error")
              end
            end
          end

          # --- Наборы шаблонов (config/layout_sets/*.yaml) -------------------------

          # Список наборов фронтенд получает в payload getData (template_sets);
          # отдельный колбэк не нужен.

          # Сохранить текущие шаблоны как набор: { name, custom_layouts }
          dialog.add_action_callback("saveTemplateSet") do |_action_context, data_json|
            begin
              payload = JSON.parse(data_json, symbolize_names: true)
              name = payload[:name].to_s
              layouts = payload[:custom_layouts]
              if name.strip.empty? || !layouts.is_a?(Hash) || layouts.empty?
                notify_js(dialog, Locale.t(:set_save_no_name), "error")
                next
              end

              model = Sketchup.active_model
              project_data = Model::SessionStore.data(model) if defined?(Model::SessionStore)
              ok = project_data && project_data.save_template_set(name, layouts)
              if ok
                notify_js(dialog, Locale.t(:set_saved, name: name), "success")
              else
                notify_js(dialog, Locale.t(:set_save_failed), "error")
              end
              sets = project_data ? project_data.list_template_sets : []
              json_str = JSON.generate({ sets: sets })
              dialog.execute_script("window.app && window.app.onTemplateSetsUpdated(#{json_str});")
            rescue StandardError => e
              notify_js(dialog, Locale.t(:set_save_error, msg: e.message), "error")
            end
          end

          # Загрузить набор по имени: заменяет все шаблоны содержимым набора
          dialog.add_action_callback("loadTemplateSet") do |_action_context, name_json|
            begin
              name = JSON.parse(name_json.to_s).to_s
              model = Sketchup.active_model
              project_data = Model::SessionStore.data(model) if defined?(Model::SessionStore)
              layouts = project_data && project_data.load_template_set(name)
              if layouts
                json_str = JSON.generate({ custom_layouts: layouts })
                dialog.execute_script("window.app && window.app.onTemplateSetLoaded(#{json_str});")
                notify_js(dialog, Locale.t(:set_loaded, name: name), "success")
              else
                notify_js(dialog, Locale.t(:set_not_found, name: name), "error")
              end
            rescue StandardError => e
              notify_js(dialog, Locale.t(:set_load_error, msg: e.message), "error")
            end
          end

          # Удалить набор по имени
          dialog.add_action_callback("deleteTemplateSet") do |_action_context, name_json|
            begin
              name = JSON.parse(name_json.to_s).to_s
              model = Sketchup.active_model
              project_data = Model::SessionStore.data(model) if defined?(Model::SessionStore)
              ok = project_data && project_data.delete_template_set(name)
              if ok
                notify_js(dialog, Locale.t(:set_deleted, name: name), "success")
              else
                notify_js(dialog, Locale.t(:set_delete_failed), "error")
              end
              sets = project_data ? project_data.list_template_sets : []
              json_str = JSON.generate({ sets: sets })
              dialog.execute_script("window.app && window.app.onTemplateSetsUpdated(#{json_str});")
            rescue StandardError => e
              notify_js(dialog, Locale.t(:set_delete_error, msg: e.message), "error")
            end
          end

          # Сохранить текущий список стадий как список по умолчанию:
          # { stadia: [имена] } — только имена и порядок, без статусов галочек
          dialog.add_action_callback("saveStadiaDefault") do |_action_context, data_json|
            begin
              payload = JSON.parse(data_json.to_s, symbolize_names: true)
              names = payload.is_a?(Hash) ? payload[:stadia] : nil
              saved = names.is_a?(Array) ? Model::ProjectData.set_stadia_default(names) : []
              if saved.empty?
                notify_js(dialog, Locale.t(:stadia_empty), "error")
                next
              end

              model = Sketchup.active_model
              project_data = Model::SessionStore.data(model) if defined?(Model::SessionStore)
              ok = project_data ? project_data.save_program_settings : false
              if ok
                notify_js(dialog, Locale.t(:stadia_saved, n: saved.size), "success")
              else
                notify_js(dialog, Locale.t(:stadia_save_failed), "error")
              end
            rescue StandardError => e
              notify_js(dialog, Locale.t(:stadia_save_error, msg: e.message), "error")
            end
          end

          # Проверка наличия новой версии в dev-папке (путь резолвится в DevUpdater,
          # в интерфейс не передается)
          dialog.add_action_callback("checkForUpdate") do |_action_context|
            res = Service::DevUpdater.check_for_update
            json_res = JSON.generate(res)
            dialog.execute_script("window.app && window.app.onUpdateCheckResult && window.app.onUpdateCheckResult(#{json_res});")
          end

          # Обновление из dev-папки и перезагрузка плагина
          dialog.add_action_callback("updateFromDev") do |_action_context|
            res = Service::DevUpdater.update_and_reload!
            json_res = JSON.generate(res)
            dialog.execute_script("window.app && window.app.onDevUpdateResult && window.app.onDevUpdateResult(#{json_res});")
          end

          # Пульс активности из диалога (мышь/клавиатура/колесо в панели) —
          # отмечает активную работу для трекера статистики
          dialog.add_action_callback("activityPing") do |_action_context|
            Service::StatsTracker.heartbeat if defined?(Service::StatsTracker)
          end

          # Данные статистики работы над проектом для вкладки «Статистика»
          dialog.add_action_callback("getWorkStats") do |_action_context|
            begin
              model = (defined?(Sketchup) && Sketchup.respond_to?(:active_model)) ? Sketchup.active_model : nil
              project_data = model ? Model::SessionStore.data(model) : nil
              payload = build_work_stats_payload(project_data)
              json_res = JSON.generate(payload)
              dialog.execute_script("window.app && window.app.onWorkStats && window.app.onWorkStats(#{json_res});")
            rescue StandardError => e
              warn "[DN1Sup Export PDF] Ошибка получения статистики: #{e.message}"
              dialog.execute_script("window.app && window.app.onWorkStats && window.app.onWorkStats(#{JSON.generate({ error: e.message.to_s })});")
            end
          end

          # Полный сброс статистики работы над проектом (по кнопке с подтверждением)
          dialog.add_action_callback("resetWorkStats") do |_action_context|
            begin
              model = (defined?(Sketchup) && Sketchup.respond_to?(:active_model)) ? Sketchup.active_model : nil
              if model
                project_data = Model::SessionStore.data(model)
                project_data.reset_work_stats!
                Model::SessionStore.mark_dirty!(model)
                Model::SessionStore.flush(model)
              end
              payload = build_work_stats_payload(model ? Model::SessionStore.data(model) : nil)
              json_res = JSON.generate(payload)
              dialog.execute_script("window.app && window.app.onWorkStats && window.app.onWorkStats(#{json_res});")
              notify_js(dialog, Locale.t(:stats_reset), "success")
            rescue StandardError => e
              notify_js(dialog, Locale.t(:stats_reset_error, msg: e.message), "error")
            end
          end
        end

        # Собирает данные статистики для вкладки «Статистика»: отчёт трекера
        # (сводки и серии графиков) + подпись проекта. Перед сбором
        # синхронизирует автозначение «Общей длительности проекта» — открытие
        # «Проекта»/«Статистики» показывает актуальный итог без пересохранения.
        # @param project_data [Model::ProjectData, nil]
        # @return [Hash]
        def self.build_work_stats_payload(project_data)
          now = Time.now
          project_data&.sync_total_duration_from_stats!
          report = project_data ? project_data.work_stats_report(now) : Model::WorkStats.report(Model::WorkStats.blank_data, now)
          {
            articul: project_data ? project_data.project_info[:articul].to_s : "",
            product: project_data ? project_data.project[:product].to_s : "",
            total_duration: project_data ? project_data.workflow[:total_duration].to_s : "",
            report:  report,
            saved_at: now.strftime("%Y-%m-%d %H:%M")
          }
        end
      end
    end
  end
end
