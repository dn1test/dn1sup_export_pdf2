# frozen_string_literal: true

module DN1Code
  module ExportPdf2
    module Service
      # Общий сервис разрешения строковых ключей информации в текст для отображения на листе.
      # Используется генератором LayoutBuilder для формирования страниц в LayOut Ruby API.
      module InfoLineResolver
        module_function

        # Разрешает элемент заголовка в «сырое» значение без префиксов
        def resolve_header_item(context, key)
          info = context[:info] || {}
          scene_item = context[:scene_item]

          case key.to_s
          when "furniture_name"
            furn = (info[:furniture_name] || info[:name_product] || info[:name_project]).to_s.strip
            furn = "ПРОЕКТ МЕБЕЛИ" if furn.empty?
            furn
          when "place_address"
            room = (info[:room_name] || info[:name_place]).to_s.strip
            addr = (info[:address] || info[:adress]).to_s.strip
            place_addr = [room, addr].reject(&:empty?).join(" | ")
            place_addr = "Место установки | Адрес не указан" if place_addr.empty?
            place_addr
          when "customer_or_company"
            cust = (info[:name_customer] || info[:customer]).to_s.strip
            comp = (info[:company] || info[:name_company]).to_s.strip
            cust_comp = [cust, comp].reject(&:empty?).join(" | ")
            cust_comp = "Заказчик не указан" if cust_comp.empty?
            cust_comp
          when "scene_name", "name", "name_scene"
            s_name = ""
            if scene_item
              if scene_item.respond_to?(:scene_ref) && scene_item.scene_ref && scene_item.scene_ref.respond_to?(:name) && !scene_item.scene_ref.name.to_s.strip.empty?
                s_name = scene_item.scene_ref.name.to_s.strip
              elsif !scene_item.name.to_s.strip.empty?
                s_name = scene_item.name.to_s.strip
              end
            end
            s_name = (info[:scene_name] || info[:name_scene] || "") if s_name.strip.empty?
            s_name.to_s.strip
          when "scene_description", "description", "scene_desc", "desc"
            s_desc = ""
            if scene_item
              if scene_item.respond_to?(:scene_ref) && scene_item.scene_ref && scene_item.scene_ref.respond_to?(:description) && !scene_item.scene_ref.description.to_s.strip.empty?
                s_desc = scene_item.scene_ref.description.to_s.strip
              elsif !scene_item.description.to_s.strip.empty?
                s_desc = scene_item.description.to_s.strip
              end
            end
            s_desc = (info[:scene_description] || info[:scene_desc] || "") if s_desc.strip.empty?
            s_desc.to_s.strip
          else
            resolve(context, key)
          end
        end

        # Разрешает строковый ключ информации в текст.
        # @param context [Hash] { info:, workflow:, project_data:, scene_item:, page_index:, total_pages: }
        # @param key [String, Symbol] ключ строки
        # @return [String, nil]
        def resolve(context, key)
          info        = context[:info] || {}
          workflow    = context[:workflow] || {}
          project_data = context[:project_data]
          scene_item  = context[:scene_item]
          page_index  = context[:page_index]
          total_pages = context[:total_pages]

          k_str = key.to_s
          case k_str
          when "toc_pages", "toc"
            scenes = if project_data.respond_to?(:scenes) && project_data.scenes
                       project_data.scenes.select { |s| s.enabled && s.page_type.to_s != "skip" }
                     else
                       []
                     end
            total_count = (total_pages && total_pages.to_i > 0) ? total_pages.to_i : scenes.size
            if !scenes.empty?
              lines_list = scenes.each_with_index.map { |s, idx| "#{idx + 1}. #{s.name}" }
              "Содержание (всего страниц: #{total_count}):\n" + lines_list.join("\n")
            else
              "Содержание: Список страниц проекта"
            end
          when "place_address"
            room = (info[:room_name] || info[:name_place]).to_s.strip
            addr = (info[:address] || info[:adress]).to_s.strip
            val = [room, addr].reject(&:empty?).join(" | ")
            val.empty? ? "Место | Адрес" : val
          when "customer_or_company"
            cust = (info[:name_customer] || info[:customer]).to_s.strip
            comp = (info[:company] || info[:name_company]).to_s.strip
            val = [cust, comp].reject(&:empty?).join(" | ")
            val.empty? ? "Имя заказчика / Компания" : val
          when "general_notes"
            val = (info[:project_description] || info[:description] || info[:notes]).to_s.strip
            val.empty? ? "Общие пояснения: —" : "Общие пояснения: #{val}"
          when "workflow_history", "history_table"
            hist = workflow[:history_edit] || info[:history_edit]
            if hist.is_a?(Array) && !hist.empty?
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
              lines_arr.empty? ? "История правок: нет записей" : ("История правок:\n" + lines_arr.join("\n"))
            else
              val = (workflow[:last_edit] || info[:last_edit]).to_s.strip
              val.empty? ? "История правок: —" : "История правок: #{val}"
            end
          when "workflow_stadia"
            stadia = workflow[:stadia] || info[:stadia]
            if stadia.is_a?(Array) && !stadia.empty?
              lines_arr = stadia.map do |st|
                if st.is_a?(Hash)
                  done = (st[:status] == true || st["status"] == true || st[:status].to_s == "true" || st["status"].to_s == "true")
                  title = (st[:name] || st["name"] || st[:title] || st["title"]).to_s.strip
                  mark = done ? "[✓]" : "[ ]"
                  "#{mark} #{title}"
                elsif st.is_a?(Array)
                  done = (st[1] == true || st[1] == "true")
                  title = st[2].to_s.strip
                  mark = done ? "[✓]" : "[ ]"
                  "#{mark} #{title}"
                else
                  st.to_s.strip
                end
              end.reject(&:empty?)
              lines_arr.empty? ? "Стадия проекта: В работе" : ("Стадия проекта:\n" + lines_arr.join("\n"))
            else
              st = (workflow[:status] || info[:status]).to_s.strip
              st.empty? ? "Стадия проекта: Предварительный проект" : "Стадия проекта: #{st}"
            end
          when "footer_last_edit"
            hist = workflow[:history_edit] || info[:history_edit]
            last = if hist.is_a?(Array) && !hist.empty?
                     # Канонический порядок истории: новые сверху, свежая запись — первая
                     entry = hist.first
                     if entry.is_a?(Array)
                       "#{entry[0]} #{entry[1]}"
                     elsif entry.is_a?(Hash)
                       d = entry[:data] || entry[:date] || entry["data"] || entry["date"]
                       t = entry[:edit] || entry[:text] || entry["edit"] || entry["text"]
                       "#{d} #{t}".strip
                     else
                       entry.to_s
                     end
                   else
                     (workflow[:last_edit] || info[:last_edit]).to_s
                   end
            last = last.strip
            last.empty? ? "Последние изменения: —" : (last.downcase.start_with?("последние") ? last : "Последние изменения: #{last}")
          when "footer_ver_rev"
            rev = workflow[:revision] || info[:revision] || "001"
            ver = workflow[:version] || info[:version] || "01"
            "Версия #{ver} # Ревизия #{rev}"
          when "footer_articul"
            art = (info[:articul] || "").to_s.strip
            art = "CF##{info[:id] || 'PRJ'}" if art.empty?
            art.downcase.start_with?("артикул") ? art : "Артикул: #{art}"
          when "footer_date"
            d = workflow[:last_edit_date] || info[:date]
            d = d.to_s.strip
            d = Time.now.strftime("%d.%m.%Y") if d.empty?
            d.downcase.start_with?("дата") ? d : "Дата: #{d}"
          when "footer_rev_ver_date"
            rev = workflow[:revision] || info[:revision] || "001"
            ver = workflow[:version] || info[:version] || "01"
            art = (info[:articul] || "").to_s.strip
            art = "CF##{info[:id] || 'PRJ'}" if art.empty?
            date = Time.now.strftime("%d.%m.%Y")
            "Ревизия #{rev} # Версия #{ver} | #{art} | #{date}"
          when "footer_page_total"
            "Страница #{page_index} | #{total_pages}"
          when "workflow_date", "date"
            d = workflow[:last_edit_date] || info[:date]
            d ? "Дата: #{d}" : "Дата: #{Time.now.strftime('%d.%m.%Y')}"
          when "room_name"
            val = (info[:room_name] || info[:name_place]).to_s.strip
            val.empty? ? "Помещение: —" : "Помещение: #{val}"
          when "furniture_name"
            val = (info[:furniture_name] || info[:name_product]).to_s.strip
            val.empty? ? "Изделие: —" : "Изделие: #{val}"
          when "trade_type"
            val = (info[:trade] == 1 || info[:trade] == "1") ? "Коммерческий (CF#)" : "Бытовой (HF#)"
            "Тип: #{val}"
          when "articul"
            val = info[:articul].to_s.strip
            val.empty? ? "Артикул: —" : "Артикул: #{val}"
          when "address"
            val = (info[:address] || info[:adress]).to_s.strip
            val.empty? ? "Адрес: —" : "Адрес: #{val}"
          when "project_desc"
            val = (info[:project_description] || info[:description]).to_s.strip
            val.empty? ? "Описание: —" : "Описание: #{val}"
          when "customer_name"
            val = (info[:name_customer] || info[:customer]).to_s.strip
            val.empty? ? "Заказчик: —" : "Заказчик: #{val}"
          when "customer_id"
            val = (info[:customer_id] || info[:id]).to_s.strip
            val.empty? ? "ID клиента: —" : "ID клиента: #{val}"
          when "customer_company"
            val = (info[:company] || info[:name_company]).to_s.strip
            val.empty? ? "Компания: —" : "Компания: #{val}"
          when "customer_phone"
            val = info[:phone].to_s.strip
            val.empty? ? "Тел: —" : "Тел: #{val}"
          when "customer_email"
            val = info[:email].to_s.strip
            val.empty? ? "Email: —" : "Email: #{val}"
          when "scene_name", "name_scene"
            s_name = ""
            if scene_item
              if scene_item.respond_to?(:scene_ref) && scene_item.scene_ref && scene_item.scene_ref.respond_to?(:name) && !scene_item.scene_ref.name.to_s.strip.empty?
                s_name = scene_item.scene_ref.name.to_s.strip
              elsif !scene_item.name.to_s.strip.empty?
                s_name = scene_item.name.to_s.strip
              end
            end
            s_name = (info[:scene_name] || info[:name_scene] || "") if s_name.strip.empty?
            s_name = s_name.to_s.strip
            s_name.empty? ? "Сцена: —" : "Сцена: #{s_name}"
          when "scene_description", "scene_desc"
            s_desc = ""
            if scene_item
              if scene_item.respond_to?(:scene_ref) && scene_item.scene_ref && scene_item.scene_ref.respond_to?(:description) && !scene_item.scene_ref.description.to_s.strip.empty?
                s_desc = scene_item.scene_ref.description.to_s.strip
              elsif !scene_item.description.to_s.strip.empty?
                s_desc = scene_item.description.to_s.strip
              end
            end
            s_desc = (info[:scene_description] || info[:scene_desc] || "") if s_desc.strip.empty?
            s_desc = s_desc.to_s.strip
            s_desc.empty? ? "Описание сцены: —" : "Описание сцены: #{s_desc}"
          when "workflow_status"
            val = (workflow[:status] || info[:status]).to_s.strip
            val.empty? ? "Статус: —" : "Статус: #{val}"
          when "workflow_version"
            ver = workflow[:version] || info[:version] || 1
            "Версия: v#{ver}"
          when "workflow_revision"
            rev = workflow[:revision] || info[:revision] || "001"
            "Ревизия: #r#{rev}"
          when "workflow_dates"
            s = info[:start_date].to_s.strip
            e = info[:end_date].to_s.strip
            (s.empty? && e.empty?) ? "Сроки: —" : "Сроки: #{s.empty? ? '—' : s} → #{e.empty? ? '—' : e}"
          when "workflow_duration"
            val = info[:total_duration].to_s.strip
            val.empty? ? "Длительность: —" : "Длительность: #{val} дн."
          when "workflow_price"
            val = info[:price].to_s.strip
            val.empty? ? "Стоимость: —" : "Стоимость: #{val} руб."
          when "workflow_author"
            val = (workflow[:author] || info[:author]).to_s.strip
            val.empty? ? "Автор: —" : "Автор: #{val}"
          when "workflow_edit"
            val = (workflow[:last_edit] || info[:last_edit]).to_s.strip
            val.empty? ? "Правка: —" : "Правка: #{val}"
          when "spec_materials"
            val = info[:materials].to_s.strip
            val.empty? ? "Материалы: Фасады МДФ, ЛДСП, Blum..." : "Материалы: #{val}"
          when "spec_appliances"
            app = info[:appliances].to_s.strip
            lig = info[:lighting].to_s.strip
            combined = [app, lig].uniq.reject(&:empty?).join("; ")
            combined.empty? ? "Техника и подсветка: Встраиваемая техника, LED 3000K..." : "Техника и подсветка: #{combined}"
          when "spec_lighting"
            val = info[:lighting].to_s.strip
            val.empty? ? "Подсветка: LED 3000K 24V..." : "Подсветка: #{val}"
          when "scene_notes"
            desc = (scene_item ? scene_item.description : nil)
            val = (desc && !desc.empty?) ? desc : info[:notes].to_s.strip
            val.empty? ? "Примечание: Габаритные размеры..." : "Примечание: #{val}"
          when "system_date"
            "Дата: #{Time.now.strftime('%d.%m.%Y')}"
          when "system_page"
            "Лист #{page_index} из #{total_pages}"
          when /^dir_desc_(\d+)$/
            idx = Regexp.last_match(1).to_i
            dirs = nil
            if project_data.respond_to?(:directories) && project_data.directories
              dirs = project_data.directories
            elsif context[:directories]
              dirs = context[:directories]
            end
            if dirs.is_a?(Array) && dirs[idx]
              d = dirs[idx]
              t = (d[:title] || d["title"]).to_s.strip
              desc = (d[:description] || d["description"]).to_s.strip
              t = "Раздел ##{idx + 1}" if t.empty?
              desc.empty? ? "#{t}: —" : "#{t}: #{desc}"
            else
              nil
            end
          when "dir_specs", "directories_spec"
            dirs = nil
            if project_data.respond_to?(:directories) && project_data.directories
              dirs = project_data.directories
            elsif context[:directories]
              dirs = context[:directories]
            end
            if dirs.is_a?(Array) && !dirs.empty?
              lines_arr = dirs.map.with_index do |d, i|
                t = (d[:title] || d["title"]).to_s.strip
                desc = (d[:description] || d["description"]).to_s.strip
                next if desc.empty? && t.empty?
                t = "Раздел ##{i + 1}" if t.empty?
                desc.empty? ? "#{t}: —" : "#{t}: #{desc}"
              end.compact
              lines_arr.empty? ? "Спецификации папок: —" : lines_arr.join("\n")
            else
              nil
            end
          else
            nil
          end
        end

        # Возвращает пару [заголовок, описание/значение] для строкового ключа
        def resolve_parts(context, key)
          project_data = context[:project_data]
          info         = context[:info] || context[:project_info] || (project_data.respond_to?(:info) ? project_data.info : {}) || {}
          workflow     = context[:workflow] || (project_data.respond_to?(:workflow) ? project_data.workflow : {}) || {}
          scene_item   = context[:scene_item]

          k_str = key.to_s
          case k_str
          when "spec_materials"
            val = (info[:materials] || info["materials"]).to_s.strip
            val = "Фасады МДФ, ЛДСП, Blum..." if val.empty?
            ["Материалы и фурнитура", val]
          when "spec_appliances"
            app = (info[:appliances] || info["appliances"]).to_s.strip
            lig = (info[:lighting] || info["lighting"]).to_s.strip
            combined = [app, lig].uniq.reject(&:empty?).join("; ")
            combined = "Встраиваемая техника, LED 3000K..." if combined.empty?
            ["Техника и подсветка", combined]
          when "spec_lighting"
            val = (info[:lighting] || info["lighting"]).to_s.strip
            val = "LED 3000K 24V..." if val.empty?
            ["Подсветка", val]
          when "general_notes"
            val = (info[:project_description] || info["project_description"] || info[:description] || info["description"] || info[:notes] || info["notes"]).to_s.strip
            val = "Замеры выполнены по факту" if val.empty?
            ["Общие пояснения", val]
          when "scene_notes"
            desc = (scene_item ? scene_item.description : nil)
            val = (desc && !desc.empty?) ? desc : (info[:notes] || info["notes"]).to_s.strip
            val = "Габаритные размеры..." if val.empty?
            ["Примечание", val]
          when /^dir_desc_(\d+)$/
            idx = Regexp.last_match(1).to_i
            dirs = nil
            if project_data.respond_to?(:directories) && project_data.directories
              dirs = project_data.directories
            elsif context[:directories]
              dirs = context[:directories]
            end
            if dirs.is_a?(Array) && dirs[idx]
              d = dirs[idx]
              t = (d[:title] || d["title"]).to_s.strip
              desc = (d[:description] || d["description"]).to_s.strip
              t = "Раздел ##{idx + 1}" if t.empty?
              [t, desc.empty? ? "—" : desc]
            else
              nil
            end
          when "dir_specs", "directories_spec"
            dirs = nil
            if project_data.respond_to?(:directories) && project_data.directories
              dirs = project_data.directories
            elsif context[:directories]
              dirs = context[:directories]
            end
            if dirs.is_a?(Array) && !dirs.empty?
              lines_arr = dirs.map.with_index do |d, i|
                t = (d[:title] || d["title"]).to_s.strip
                desc = (d[:description] || d["description"]).to_s.strip
                next if desc.empty? && t.empty?
                t = "Раздел ##{i + 1}" if t.empty?
                desc.empty? ? t : "#{t}: #{desc}"
              end.compact
              ["Спецификации папок", lines_arr.empty? ? "—" : lines_arr.join("\n")]
            else
              nil
            end
          when "workflow_history", "history_table"
            hist = workflow[:history_edit] || info[:history_edit]
            if hist.is_a?(Array) && !hist.empty?
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
              ["История правок", lines_arr.empty? ? "нет записей" : lines_arr.join("\n")]
            else
              val = (workflow[:last_edit] || info[:last_edit]).to_s.strip
              ["История правок", val.empty? ? "—" : val]
            end
          when "workflow_stadia"
            stadia = workflow[:stadia] || info[:stadia]
            if stadia.is_a?(Array) && !stadia.empty?
              lines_arr = stadia.map do |st|
                if st.is_a?(Hash)
                  done = (st[:status] == true || st["status"] == true || st[:status].to_s == "true" || st["status"].to_s == "true")
                  title = (st[:name] || st["name"] || st[:title] || st["title"]).to_s.strip
                  mark = done ? "[✓]" : "[ ]"
                  "#{mark} #{title}"
                elsif st.is_a?(Array)
                  done = (st[1] == true || st[1] == "true")
                  title = st[2].to_s.strip
                  mark = done ? "[✓]" : "[ ]"
                  "#{mark} #{title}"
                else
                  st.to_s.strip
                end
              end.reject(&:empty?)
              ["Стадия проекта", lines_arr.empty? ? "В работе" : lines_arr.join("\n")]
            else
              st = (workflow[:status] || info[:status]).to_s.strip
              ["Стадия проекта", st.empty? ? "Предварительный проект" : st]
            end
          when "workflow_revision"
            val = (workflow[:revision] || info[:revision]).to_s.strip
            ["Ревизия", val.empty? ? "001" : val]
          when "workflow_version"
            val = (workflow[:version] || info[:version]).to_s.strip
            ["Версия", val.empty? ? "01" : val]
          when "workflow_date"
            val = (workflow[:date_order] || info[:date]).to_s.strip
            val = Time.now.strftime("%d.%m.%Y") if val.empty?
            ["Дата", val]
          when "toc_pages", "toc"
            raw = resolve(context, key)
            if raw && raw.include?(":\n")
              parts = raw.split(":\n", 2)
              [parts[0], parts[1]]
            elsif raw && raw.include?(": ")
              parts = raw.split(": ", 2)
              [parts[0], parts[1]]
            else
              ["Содержание", raw]
            end
          when "room_name"
            val = (info[:room_name] || info[:name_place]).to_s.strip
            ["Помещение", val.empty? ? "—" : val]
          when "furniture_name"
            val = (info[:furniture_name] || info[:name_product]).to_s.strip
            ["Изделие", val.empty? ? "—" : val]
          when "articul"
            val = info[:articul].to_s.strip
            ["Артикул", val.empty? ? "—" : val]
          when "address"
            val = (info[:address] || info[:adress]).to_s.strip
            ["Адрес", val.empty? ? "—" : val]
          when "customer_name"
            val = (info[:name_customer] || info[:customer]).to_s.strip
            ["Заказчик", val.empty? ? "—" : val]
          else
            raw = resolve(context, key)
            return nil if raw.nil? || raw.to_s.empty?
            if raw.include?(":\n")
              parts = raw.split(":\n", 2)
              [parts[0], parts[1]]
            elsif raw.include?(": ")
              parts = raw.split(": ", 2)
              [parts[0], parts[1]]
            else
              [nil, raw]
            end
          end
        end

        # Разрешает ключ с учетом настроек показа заголовка на отдельной строке
        def resolve_formatted(context, key, show_title: true)
          parts = resolve_parts(context, key)
          if parts
            title, desc = parts
            if show_title && title && !title.to_s.strip.empty?
              desc && !desc.to_s.strip.empty? ? "#{title}\n#{desc}" : title
            else
              desc.to_s
            end
          else
            resolve(context, key)
          end
        end

        # Строки карточки "Данные проекта" по умолчанию
        def default_project_card_lines(context)
          info = context[:info] || {}
          items = []
          room = (info[:room_name] || info[:name_place]).to_s.strip
          furn = (info[:furniture_name] || info[:name_product]).to_s.strip
          cust = (info[:name_customer] || info[:customer]).to_s.strip
          stat = info[:status].to_s.strip

          items << "Помещение: #{room}" unless room.empty?
          items << "Изделие: #{furn}" unless furn.empty?
          items << "Заказчик: #{cust}" unless cust.empty?
          items << "Статус: #{stat}" unless stat.empty?
          items << "Стоимость: #{info[:price]} руб." unless info[:price].to_s.strip.empty?
          items
        end

        # Строки карточки заказчика по умолчанию
        def default_customer_card_lines(context)
          info = context[:info] || {}
          items = []
          cust = (info[:name_customer] || info[:customer]).to_s.strip
          phone = info[:phone].to_s.strip
          email = info[:email].to_s.strip
          addr = (info[:address] || info[:adress]).to_s.strip
          comp = info[:company].to_s.strip

          items << "Имя: #{cust}" unless cust.empty?
          items << "Компания: #{comp}" unless comp.empty?
          items << "Тел: #{phone}" unless phone.empty?
          items << "Email: #{email}" unless email.empty?
          items << "Адрес: #{addr}" unless addr.empty?
          items
        end

        # Строки статуса workflow по умолчанию
        def default_workflow_status_lines(context)
          info = context[:info] || {}
          items = []
          items << "Версия: v#{info[:version]} #r#{info[:revision]}"
          items << "Статус: #{info[:status] || 'В РАБОТЕ'}"
          items << "Сроки: #{info[:start_date]} - #{info[:end_date]}" if info[:start_date] && info[:end_date]
          items << "Длительность: #{info[:total_duration]} дн." unless info[:total_duration].to_s.strip.empty?
          items << "Дата проекта: #{Time.now.strftime('%d.%m.%Y')}"
          items
        end

        # Строки истории изменений по умолчанию
        def default_history_lines(context)
          project_data = context[:project_data]
          info = context[:info] || {}
          wf = (project_data.respond_to?(:workflow) ? project_data.workflow : nil) || {}
          hist = wf[:history_edit] || []
          items = []

          if hist.is_a?(Array) && !hist.empty?
            # Канонический порядок истории: новые сверху — берем первые (самые свежие) записи
            hist.first(3).each do |entry|
              if entry.is_a?(Array)
                items << "#{entry[0]}: #{entry[1]}"
              elsif entry.is_a?(Hash)
                items << "#{entry[:date] || entry['date']}: #{entry[:text] || entry['text'] || entry[:description]}"
              end
            end
          else
            items << "v#{info[:version]}#r#{info[:revision]}: Начальная редакция"
          end
          items.map { |i| "• #{i}" }
        end
      end
    end
  end
end
