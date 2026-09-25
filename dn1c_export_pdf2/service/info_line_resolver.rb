# frozen_string_literal: true

module DN1Code
  module ExportPdf2
    module Service
      # Разрешение источника параметра шаблона в значение для отображения на листе.
      # Источник — строка вида "project.articul", "customer.phone", "workflow.price",
      # "dir.<индекс>.line" (заголовок папки на своей строке, описание — на
      # следующей; прежние отдельные "dir.<индекс>.title" и
      # "dir.<индекс>.description" тоже поддерживаются),
      # "scene.name", "page.number_total".
      # Возвращает «сырое» значение БЕЗ заголовка-префикса: заголовок задаётся
      # настройкой самого параметра (label/show_label в конфиге шаблона).
      # Пустое значение — nil: параметр не выводится на лист (без заглушек).
      module InfoLineResolver
        module_function

        # Имя или описание сцены: из scene_item (приоритет — scene_ref), затем из info.
        # Возвращает nil, если значения нет нигде.
        def scene_value(context, kind)
          scene_item = context[:scene_item]
          info = context[:info] || {}
          val = ""
          if scene_item
            ref = scene_item.respond_to?(:scene_ref) ? scene_item.scene_ref : nil
            if kind == :name
              val = ref.name.to_s.strip if ref && ref.respond_to?(:name)
              val = scene_item.name.to_s.strip if val.empty?
            else
              val = ref.description.to_s.strip if ref && ref.respond_to?(:description)
              val = scene_item.description.to_s.strip if val.empty?
            end
          end
          fallback = kind == :name ? (info[:scene_name] || info[:name_scene]) : (info[:scene_description] || info[:scene_desc])
          val = fallback.to_s.strip if val.empty?
          val.empty? ? nil : val
        end

        # Каталог источников параметров: source-ключ → человекочитаемое название.
        # Используется для валидации и подсказок; динамические папки добавляются отдельно.
        def param_source_labels
          {
            "project.articul"         => "Артикул проекта",
            "project.furniture_name"  => "Изделие",
            "project.room_name"       => "Помещение / Место установки",
            "project.address"         => "Адрес установки",
            "project.company"         => "Название компании",
            "project.description"     => "Описание проекта",
            "customer.id"             => "ID заказчика",
            "customer.name"           => "Заказчик (контактное лицо)",
            "customer.phone"          => "Телефон",
            "customer.email"          => "Email",
            "workflow.author"         => "Автор / Конструктор",
            "workflow.price"          => "Стоимость проекта",
            "workflow.start_date"     => "Дата начала",
            "workflow.end_date"       => "Дата сдачи",
            "workflow.duration"       => "Длительность / Трудозатраты",
            "workflow.version"        => "Версия",
            "workflow.revision"       => "Ревизия",
            "workflow.date"           => "Дата",
            "workflow.status"         => "Статус",
            "workflow.stadia"         => "Стадии проекта",
            "workflow.last_edit"      => "Последние изменения",
            "workflow.history"        => "История правок",
            "scene.name"              => "Название сцены",
            "scene.description"       => "Описание сцены",
            "page.number_total"       => "Страница | Страниц",
            "page.toc"                => "Содержание (список страниц)"
          }
        end

        # Разрешает источник параметра в текст значения.
        # @param context [Hash] { info:, workflow:, project_data:, scene_item:, page_index:, total_pages: }
        # @param source [String, Symbol] источник параметра, напр. "project.room_name"
        # @return [String, nil]
        def resolve_param(context, source)
          info     = context[:info] || {}
          workflow = context[:workflow] || {}
          src      = source.to_s.strip
          return nil if src.empty?

          case src
          when "project.articul"        then non_blank(info[:articul])
          when "project.furniture_name" then non_blank(info[:furniture_name] || info[:name_product] || info[:name_project])
          when "project.room_name"      then non_blank(info[:room_name] || info[:name_place])
          when "project.address"        then non_blank(info[:address] || info[:adress])
          when "project.company"        then non_blank(info[:company] || info[:name_company])
          when "project.description"    then non_blank(info[:project_description] || info[:description])
          when "customer.id"            then non_blank(info[:customer_id] || info[:id])
          when "customer.name"          then non_blank(info[:name_customer] || info[:customer])
          when "customer.phone"         then non_blank(info[:phone])
          when "customer.email"         then non_blank(info[:email])
          when "workflow.author"        then non_blank(workflow[:author] || info[:author])
          when "workflow.price"
            v = non_blank(info[:price])
            v && "#{v} руб."
          when "workflow.start_date"    then non_blank(info[:start_date])
          when "workflow.end_date"      then non_blank(info[:end_date])
          when "workflow.duration"
            v = non_blank(info[:total_duration])
            v && (v.match?(/дн|день|час/i) ? v : "#{v} дн.")
          when "workflow.version"       then "v#{non_blank(workflow[:version] || info[:version]) || '01'}"
          when "workflow.revision"      then "#r#{non_blank(workflow[:revision] || info[:revision]) || '001'}"
          when "workflow.date"          then non_blank(workflow[:date_order] || info[:date]) || Time.now.strftime("%d.%m.%Y")
          when "workflow.status"        then non_blank(workflow[:status] || info[:status])
          when "workflow.stadia"        then stadia_value(workflow, info)
          when "workflow.last_edit"     then last_edit_value(workflow, info)
          when "workflow.history"       then history_value(workflow, info)
          when /^dir\.(\d+)\.title$/
            idx = Regexp.last_match(1).to_i
            non_blank(dir_field(context, idx, :title))
          when /^dir\.(\d+)\.description$/
            idx = Regexp.last_match(1).to_i
            non_blank(dir_field(context, idx, :description))
          when /^dir\.(\d+)\.line$/
            idx = Regexp.last_match(1).to_i
            parts = [non_blank(dir_field(context, idx, :title)),
                     non_blank(dir_field(context, idx, :description))].compact
            parts.empty? ? nil : parts.join("\n")
          when "scene.name"        then scene_value(context, :name)
          when "scene.description" then scene_value(context, :description)
          when "page.number_total"
            pi = context[:page_index]
            tp = context[:total_pages]
            return nil if pi.nil? && tp.nil?

            "Страница #{pi || 1} | #{tp || pi || 1}"
          when "page.toc" then toc_value(context)
          else nil
          end
        end

        # ------------------------------------------------------------------
        # Внутренние помощники
        # ------------------------------------------------------------------

        def non_blank(val)
          s = val.to_s.strip
          s.empty? ? nil : s
        end

        def directories_of(context)
          pd = context[:project_data]
          if pd.respond_to?(:directories) && pd.directories
            pd.directories
          else
            context[:directories]
          end
        end

        def dir_field(context, idx, field)
          dirs = directories_of(context)
          return nil unless dirs.is_a?(Array) && dirs[idx]

          d = dirs[idx]
          d[field] || d[field.to_s]
        end

        # Стадии проекта: чек-лист "[✓] Название" построчно (без префикса-заголовка).
        def stadia_value(workflow, info)
          stadia = workflow[:stadia] || info[:stadia]
          if stadia.is_a?(Array) && !stadia.empty?
            lines_arr = stadia.map do |st|
              if st.is_a?(Hash)
                done = (st[:status] == true || st["status"] == true || st[:status].to_s == "true" || st["status"].to_s == "true")
                title = (st[:name] || st["name"] || st[:title] || st["title"]).to_s.strip
                "#{done ? '[✓]' : '[ ]'} #{title}".strip
              elsif st.is_a?(Array)
                done = (st[1] == true || st[1] == "true")
                title = st[2].to_s.strip
                "#{done ? '[✓]' : '[ ]'} #{title}".strip
              else
                st.to_s.strip
              end
            end.reject(&:empty?)
            lines_arr.empty? ? nil : lines_arr.join("\n")
          else
            non_blank(workflow[:status] || info[:status])
          end
        end

        # Последние изменения: первая (самая свежая) запись истории либо last_edit.
        def last_edit_value(workflow, info)
          hist = workflow[:history_edit] || info[:history_edit]
          if hist.is_a?(Array) && !hist.empty?
            entry = hist.first
            if entry.is_a?(Array)
              non_blank("#{entry[0]} #{entry[1]}")
            elsif entry.is_a?(Hash)
              d = entry[:data] || entry[:date] || entry["data"] || entry["date"]
              t = entry[:edit] || entry[:text] || entry["edit"] || entry["text"]
              non_blank("#{d} #{t}")
            else
              non_blank(entry)
            end
          else
            non_blank(workflow[:last_edit] || info[:last_edit])
          end
        end

        # Полная история правок: построчно (без префикса-заголовка).
        def history_value(workflow, info)
          hist = workflow[:history_edit] || info[:history_edit]
          return non_blank(workflow[:last_edit] || info[:last_edit]) unless hist.is_a?(Array) && !hist.empty?

          lines_arr = hist.map do |entry|
            if entry.is_a?(Array)
              date, desc = entry[0].to_s.strip, entry[1].to_s.strip
              desc.empty? ? date : "#{date} — #{desc}"
            elsif entry.is_a?(Hash)
              d = (entry[:data] || entry[:date] || entry["data"] || entry["date"]).to_s.strip
              desc = (entry[:edit] || entry[:text] || entry["edit"] || entry["text"] || entry[:description] || entry["description"]).to_s.strip
              desc.empty? ? d : "#{d} — #{desc}"
            else
              entry.to_s.strip
            end
          end.reject(&:empty?)
          lines_arr.empty? ? nil : lines_arr.join("\n")
        end

        # Содержание: нумерованный список включённых сцен построчно (без заголовка).
        def toc_value(context)
          project_data = context[:project_data]
          scenes = if project_data.respond_to?(:scenes) && project_data.scenes
                     project_data.scenes.select(&:enabled)
                   else
                     []
                   end
          return nil if scenes.empty?

          scenes.each_with_index.map { |s, idx| "#{idx + 1}. #{s.name}" }.join("\n")
        end
      end
    end
  end
end
