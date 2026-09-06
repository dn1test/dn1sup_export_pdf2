# frozen_string_literal: true

require "fileutils"
require "tmpdir"

module DN1Code
  module ExportPdf2
    module Service
      module LayoutBuilder
        extend self

        PAGE_SIZES_INCHES = {
          "A4"     => { w: 11.6929, h: 8.2677 },
          "A3"     => { w: 16.5354, h: 11.6929 },
          "A2"     => { w: 23.3858, h: 16.5354 },
          "LETTER" => { w: 11.0,    h: 8.5 }
        }.freeze

        # Проверка доступности LayOut Ruby API в текущем окружении
        def available?
          defined?(::Layout) && defined?(::Layout::Document)
        end

        # Основной метод экспорта через LayOut API
        def export(controller, custom_output_path = nil, &progress_block)
          unless available?
            raise "LayOut Ruby API не доступен в текущей версии SketchUp.\n" \
                  "Убедитесь, что используется SketchUp Pro с установленным модулем LayOut."
          end

          project_data = controller.project_data
          model        = controller.model
          settings     = project_data.pdf_settings
          info         = project_data.project_info

          enabled_scenes = project_data.scenes.select { |s| s.enabled && s.page_type != :skip }
          if enabled_scenes.empty?
            raise "Не выбрано ни одной сцены для экспорта в LayOut / PDF!"
          end

          pdf_path = custom_output_path || controller.send(:resolve_default_pdf_path)
          FileUtils.mkdir_p(File.dirname(pdf_path))

          # Подготовка файла модели (.skp) для вставки в видовые экраны LayOut
          temp_skp_path = nil
          skp_file_for_layout = prepare_skp_file(model)
          if skp_file_for_layout.is_a?(Array)
            skp_file_for_layout, temp_skp_path = skp_file_for_layout
          end

          begin
            total_pages = enabled_scenes.size
            progress_block&.call(0, total_pages, "Инициализация документа LayOut...")

            # 1. Создание нового документа LayOut
            doc = ::Layout::Document.new

            # 2. Настройка параметров листа
            page_dim = get_page_dimensions(settings)
            page_w = page_dim[:w]
            page_h = page_dim[:h]
            margin = if settings.key?(:margin_mm) && !settings[:margin_mm].nil?
                       settings[:margin_mm].to_f / 25.4
                     elsif settings.key?("margin_mm") && !settings["margin_mm"].nil?
                       settings["margin_mm"].to_f / 25.4
                     elsif settings.key?(:margin) && !settings[:margin].nil?
                       settings[:margin].to_f / 72.0
                     elsif settings.key?("margin") && !settings["margin"].nil?
                       settings["margin"].to_f / 72.0
                     else
                       15.0 / 72.0
                     end

            if doc.respond_to?(:page_info) && doc.page_info
              page_info = doc.page_info
              page_info.width = page_w if page_info.respond_to?(:width=)
              page_info.height = page_h if page_info.respond_to?(:height=)
              page_info.left_margin = margin if page_info.respond_to?(:left_margin=)
              page_info.right_margin = margin if page_info.respond_to?(:right_margin=)
              page_info.top_margin = margin if page_info.respond_to?(:top_margin=)
              page_info.bottom_margin = margin if page_info.respond_to?(:bottom_margin=)
              page_info.display_margins = false if page_info.respond_to?(:display_margins=)
            end

            layer = doc.layers.first rescue nil
            layer ||= doc.layers.add("DN1C_Export") rescue nil

            # 3. Построение страниц
            enabled_scenes.each_with_index do |scene_item, idx|
              page_index = idx + 1
              progress_block&.call(page_index, total_pages, "Построение страницы LayOut #{page_index}/#{total_pages}: #{scene_item.name}")

              page = if idx.zero?
                       (doc.pages.respond_to?(:initial) ? doc.pages.initial : doc.pages.first) || doc.pages.add(scene_item.name)
                     else
                       doc.pages.add(scene_item.name)
                     end
              page.name = scene_item.name if page.respond_to?(:name=)

              # Добавление видового экрана и элементов в зависимости от типа страницы
              build_layout_page(doc, page, layer, skp_file_for_layout, scene_item, page_index, total_pages, page_w, page_h, margin, project_data)
            end

            progress_block&.call(total_pages, total_pages, "Экспорт документа LayOut в PDF...")

            # 4. Экспорт в PDF
            doc.export(pdf_path)

            # 5. Сохранение файла .layout если включено
            if settings[:save_layout_file]
              layout_path = pdf_path.sub(/\.pdf$/i, ".layout")
              doc.save(layout_path) rescue nil
            end

            # 6. Резервная копия .skp
            if settings[:save_skp_backup] && model && model.respond_to?(:path) && !model.path.empty?
              controller.send(:save_skp_backup)
            end

            # 7. Увеличение ревизии и сохранение атрибутов
            project_data.increment_revision!("Экспорт LayOut PDF (#{File.basename(pdf_path)})")
            project_data.save_auto(model) if model

            progress_block&.call(total_pages, total_pages, "Экспорт через LayOut API успешно завершен!")

            # 8. Открытие PDF файла
            if settings[:auto_open_pdf] && defined?(UI) && UI.respond_to?(:openURL)
              UI.openURL(pdf_path)
            end

            pdf_path
          ensure
            # Удаление временного .skp файла если он создавался
            if temp_skp_path && File.exist?(temp_skp_path)
              File.delete(temp_skp_path) rescue nil
            end
          end
        end

        private

        # Определение физических размеров листа в дюймах
        def get_page_dimensions(settings)
          size_key = (settings[:page_size] || "A4").to_s.upcase
          base = PAGE_SIZES_INCHES[size_key] || PAGE_SIZES_INCHES["A4"]

          is_portrait = settings[:page_layout].to_s.downcase == "portrait"
          w = is_portrait ? [base[:w], base[:h]].min : [base[:w], base[:h]].max
          h = is_portrait ? [base[:w], base[:h]].max : [base[:w], base[:h]].min

          { w: w, h: h }
        end

        # Подготовка пути к файлу SketchUp
        def prepare_skp_file(model)
          if model && model.respond_to?(:path) && !model.path.to_s.empty? && File.exist?(model.path)
            if model.respond_to?(:modified?) && model.modified?
              # Модель изменена, сохраняем временную копию с текущей геометрией
              temp_skp = File.join(Dir.tmpdir, "dn1c_su_temp_#{Time.now.to_i}_#{rand(1000)}.skp")
              model.save_copy(temp_skp) rescue nil
              return [temp_skp, temp_skp] if File.exist?(temp_skp)
            end
            return [model.path, nil]
          end

          # Если модель еще не сохранена на диск
          temp_skp = File.join(Dir.tmpdir, "dn1c_su_temp_#{Time.now.to_i}_#{rand(1000)}.skp")
          if model && model.respond_to?(:save_copy)
            model.save_copy(temp_skp) rescue nil
          end
          [temp_skp, temp_skp]
        end

        # Построение элементов страницы LayOut
        def build_layout_page(doc, page, layer, skp_path, scene_item, page_index, total_pages, page_w, page_h, margin, project_data)
          settings = project_data.pdf_settings
          info     = project_data.project_info

          content_left = margin
          content_top  = margin
          content_w    = page_w - (margin * 2)
          content_h    = page_h - (margin * 2)

          header_h = 0.55
          footer_h = 0.35

          case scene_item.page_type
          when :cover
            build_cover_page(doc, page, layer, skp_path, scene_item, page_index, total_pages, content_left, content_top, content_w, content_h, header_h, footer_h, project_data)
          when :description
            build_description_page(doc, page, layer, skp_path, scene_item, page_index, total_pages, content_left, content_top, content_w, content_h, header_h, footer_h, project_data)
          when :explain
            build_explain_page(doc, page, layer, skp_path, scene_item, page_index, total_pages, content_left, content_top, content_w, content_h, header_h, footer_h, project_data)
          when :visual
            build_visual_page(doc, page, layer, skp_path, scene_item, page_index, total_pages, content_left, content_top, content_w, content_h, header_h, footer_h, project_data)
          else
            build_general_page(doc, page, layer, skp_path, scene_item, page_index, total_pages, content_left, content_top, content_w, content_h, header_h, footer_h, project_data)
          end

          # Отрисовка стандартного штампа/водяного знака если требуется
          draw_layout_stamp(doc, page, layer, content_left, content_top, content_w, content_h, settings)
        end

        # 1. Титульный лист (Cover)
        def build_cover_page(doc, page, layer, skp_path, scene_item, page_index, total_pages, cl, ct, cw, ch, hh, fh, project_data)
          info = project_data.project_info

          # Верхний заголовок проекта
          title_text = info[:name_project].to_s.strip
          if title_text.empty?
            title_text = [info[:room_name], info[:furniture_name]].map { |s| s.to_s.strip }.reject(&:empty?).join(" — ")
          end
          title_text = "ДИЗАЙН-ПРОЕКТ" if title_text.empty?

          sub_text = [
            info[:name_customer].to_s.empty? ? nil : "Заказчик: #{info[:name_customer]}",
            info[:address].to_s.empty? ? nil : "Адрес: #{info[:address]}",
            info[:articul].to_s.empty? ? nil : "Арт: #{info[:articul]}"
          ].compact.join("   •   ")

          header_bounds = create_bounds(cl, ct, cw, hh)
          add_text(doc, page, layer, "#{title_text}\n#{sub_text}", header_bounds, 16.0, true)

          # Разделение рабочей области: Левая часть - модель (56%), Правая часть - данные проекта (40%)
          body_top = ct + hh + 0.1
          body_h   = ch - hh - fh - 0.15
          left_w   = cw * 0.56
          gap      = cw * 0.04
          right_w  = cw * 0.40
          right_x  = cl + left_w + gap

          # Видовой экран модели
          vp_bounds = create_bounds(cl, body_top, left_w, body_h)
          add_model_viewport(doc, page, layer, skp_path, scene_item, vp_bounds, project_data.pdf_settings)

          # Правая колонка: Карточка реквизитов и ревизий
          place = (info[:name_place] || info[:room_name]).to_s.strip
          product = (info[:name_product] || info[:furniture_name]).to_s.strip
          customer = (info[:customer] || info[:name_customer]).to_s.strip
          company = info[:company].to_s.strip
          last_edit = (info[:last_edit] || info[:edit]).to_s.strip

          card_lines = [
            "ДАННЫЕ ПРОЕКТА",
            "----------------------------------------"
          ]
          card_lines << "Помещение: #{place}" unless place.empty?
          card_lines << "Изделие: #{product}" unless product.empty?
          card_lines << "Заказчик: #{customer}" unless customer.empty?
          card_lines << "Компания: #{company}" unless company.empty?
          contacts = [info[:phone], info[:email]].map { |s| s.to_s.strip }.reject(&:empty?).join(" | ")
          card_lines << "Контакты: #{contacts}" unless contacts.empty?
          card_lines << "Статус: #{info[:status]}"
          card_lines << "Ревизия: v#{info[:version]}#r#{info[:revision]}"
          card_lines << "Последняя правка: #{last_edit}" unless last_edit.empty?
          card_lines << "Дата: #{Time.now.strftime('%d.%m.%Y')}"
          card_lines << ""
          card_lines << "ИСТОРИЯ ИЗМЕНЕНИЙ:"
          card_lines << "----------------------------------------"

          history_items = project_data.history.first(4)
          history_items.each do |h|
            date_str = h[:date] || h["date"] || ""
            desc_str = h[:text] || h["text"] || h[:description] || h["description"] || ""
            card_lines << "#{date_str}: #{desc_str}"
          end

          card_bounds = create_bounds(right_x, body_top, right_w, body_h)
          add_text(doc, page, layer, card_lines.join("\n"), card_bounds, 9.5)

          # Нижний колонтитул
          draw_standard_footer(doc, page, layer, cl, ct + ch - fh, cw, fh, info, page_index, total_pages)
        end

        # 2. Описание и спецификации (Description)
        def build_description_page(doc, page, layer, skp_path, scene_item, page_index, total_pages, cl, ct, cw, ch, hh, fh, project_data)
          info = project_data.project_info

          # Верхний колонтитул из параметров сцены
          s_name = (scene_item.respond_to?(:scene_ref) && scene_item.scene_ref && scene_item.scene_ref.respond_to?(:name) && !scene_item.scene_ref.name.to_s.strip.empty?) ? scene_item.scene_ref.name.to_s.strip : scene_item.name.to_s.strip
          s_desc = (scene_item.respond_to?(:scene_ref) && scene_item.scene_ref && scene_item.scene_ref.respond_to?(:description) && !scene_item.scene_ref.description.to_s.strip.empty?) ? scene_item.scene_ref.description.to_s.strip : scene_item.description.to_s.strip
          draw_standard_header(doc, page, layer, cl, ct, cw, hh, info, s_name, s_desc)

          body_top = ct + hh + 0.1
          body_h   = ch - hh - fh - 0.15

          # Левая колонка: Спецификации (52%), Правая колонка: Видовой экран модели (45%)
          left_w  = cw * 0.52
          gap     = cw * 0.03
          right_w = cw * 0.45
          right_x = cl + left_w + gap

          spec_text = [
            "1. МАТЕРИАЛЫ И ФУРНИТУРА:",
            info[:materials].to_s.empty? ? "Согласно утвержденному проекту." : info[:materials].to_s,
            "",
            "2. ТЕХНИКА И ОБОРУДОВАНИЕ:",
            info[:appliances].to_s.empty? ? "Встраиваемая техника по спецификации." : info[:appliances].to_s,
            "",
            "3. ПОДСВЕТКА И ЭЛЕКТРИКА:",
            info[:lighting].to_s.empty? ? "LED подсветка и коммуникации согласно схеме." : info[:lighting].to_s,
            "",
            "4. ПОЯСНИТЕЛЬНАЯ ЗАПИСКА:",
            info[:notes].to_s.empty? ? "Монтаж производить согласно стандартам качества." : info[:notes].to_s
          ].join("\n")

          spec_bounds = create_bounds(cl, body_top, left_w, body_h)
          add_text(doc, page, layer, spec_text, spec_bounds, 9.5)

          # Видовой экран модели справа
          vp_bounds = create_bounds(right_x, body_top, right_w, body_h)
          add_model_viewport(doc, page, layer, skp_path, scene_item, vp_bounds, project_data.pdf_settings)

          # Нижний колонтитул
          draw_standard_footer(doc, page, layer, cl, ct + ch - fh, cw, fh, info, page_index, total_pages)
        end

        # 3. Содержание и ведомость (Explain)
        def build_explain_page(doc, page, layer, skp_path, scene_item, page_index, total_pages, cl, ct, cw, ch, hh, fh, project_data)
          info = project_data.project_info

          s_name = (scene_item.respond_to?(:scene_ref) && scene_item.scene_ref && scene_item.scene_ref.respond_to?(:name) && !scene_item.scene_ref.name.to_s.strip.empty?) ? scene_item.scene_ref.name.to_s.strip : scene_item.name.to_s.strip
          s_name = "СОДЕРЖАНИЕ И ПОЯСНИТЕЛЬНАЯ ЗАПИСКА" if s_name.empty?
          s_desc = (scene_item.respond_to?(:scene_ref) && scene_item.scene_ref && scene_item.scene_ref.respond_to?(:description) && !scene_item.scene_ref.description.to_s.strip.empty?) ? scene_item.scene_ref.description.to_s.strip : scene_item.description.to_s.strip
          draw_standard_header(doc, page, layer, cl, ct, cw, hh, info, s_name, s_desc)

          body_top = ct + hh + 0.1
          body_h   = ch - hh - fh - 0.15

          col_w   = (cw - 0.3) / 2.0
          right_x = cl + col_w + 0.3

          # Левая колонка: Содержание проекта
          enabled_scenes = project_data.scenes.select { |s| s.enabled && s.page_type.to_s != "skip" }
          total_count = total_pages || enabled_scenes.size
          toc_lines = ["СОДЕРЖАНИЕ ПРОЕКТА (всего страниц: #{total_count}):", "----------------------------------------"]
          enabled_scenes.each_with_index do |sc, idx|
            toc_lines << sprintf("%02d. %s", idx + 1, sc.name)
          end

          toc_bounds = create_bounds(cl, body_top, col_w, body_h)
          add_text(doc, page, layer, toc_lines.join("\n"), toc_bounds, 10.0)

          # Правая колонка: Спецификации + Видовой экран
          notes_h = [1.5, body_h * 0.4].min
          notes_text = "СПЕЦИФИКАЦИИ И ТРЕБОВАНИЯ:\n----------------------------------------\n" +
                       (info[:notes].to_s.empty? ? "Монтаж изделия согласно схеме." : info[:notes].to_s)
          notes_bounds = create_bounds(right_x, body_top, col_w, notes_h)
          add_text(doc, page, layer, notes_text, notes_bounds, 9.5)

          vp_top = body_top + notes_h + 0.1
          vp_h   = body_h - notes_h - 0.1
          if vp_h > 1.0
            vp_bounds = create_bounds(right_x, vp_top, col_w, vp_h)
            add_model_viewport(doc, page, layer, skp_path, scene_item, vp_bounds, project_data.pdf_settings)
          end

          draw_standard_footer(doc, page, layer, cl, ct + ch - fh, cw, fh, info, page_index, total_pages)
        end

        # 4. Визуализация (Visual)
        def build_visual_page(doc, page, layer, skp_path, scene_item, page_index, total_pages, cl, ct, cw, ch, hh, fh, project_data)
          info = project_data.project_info

          # Компактный заголовок из параметров сцены
          compact_h = 0.35
          s_name = (scene_item.respond_to?(:scene_ref) && scene_item.scene_ref && scene_item.scene_ref.respond_to?(:name) && !scene_item.scene_ref.name.to_s.strip.empty?) ? scene_item.scene_ref.name.to_s.strip : scene_item.name.to_s.strip
          s_desc = (scene_item.respond_to?(:scene_ref) && scene_item.scene_ref && scene_item.scene_ref.respond_to?(:description) && !scene_item.scene_ref.description.to_s.strip.empty?) ? scene_item.scene_ref.description.to_s.strip : scene_item.description.to_s.strip
          draw_standard_header(doc, page, layer, cl, ct, cw, compact_h, info, s_name, s_desc)

          body_top = ct + compact_h + 0.05
          body_h   = ch - compact_h - fh - 0.1

          vp_bounds = create_bounds(cl, body_top, cw, body_h)
          add_model_viewport(doc, page, layer, skp_path, scene_item, vp_bounds, project_data.pdf_settings)

          draw_standard_footer(doc, page, layer, cl, ct + ch - fh, cw, fh, info, page_index, total_pages)
        end

        # 5. Общий вид (General)
        def build_general_page(doc, page, layer, skp_path, scene_item, page_index, total_pages, cl, ct, cw, ch, hh, fh, project_data)
          info = project_data.project_info
          s_name = (scene_item.respond_to?(:scene_ref) && scene_item.scene_ref && scene_item.scene_ref.respond_to?(:name) && !scene_item.scene_ref.name.to_s.strip.empty?) ? scene_item.scene_ref.name.to_s.strip : scene_item.name.to_s.strip
          s_desc = (scene_item.respond_to?(:scene_ref) && scene_item.scene_ref && scene_item.scene_ref.respond_to?(:description) && !scene_item.scene_ref.description.to_s.strip.empty?) ? scene_item.scene_ref.description.to_s.strip : scene_item.description.to_s.strip
          draw_standard_header(doc, page, layer, cl, ct, cw, hh, info, s_name, s_desc)

          desc = scene_item.description.to_s.strip
          body_top = ct + hh + 0.08
          available_h = ch - hh - fh - 0.12

          if desc.empty?
            # Вся область под модель
            vp_bounds = create_bounds(cl, body_top, cw, available_h)
            add_model_viewport(doc, page, layer, skp_path, scene_item, vp_bounds, project_data.pdf_settings)
          else
            card_h = [0.6, available_h * 0.2].min
            vp_h   = available_h - card_h - 0.08

            vp_bounds = create_bounds(cl, body_top, cw, vp_h)
            add_model_viewport(doc, page, layer, skp_path, scene_item, vp_bounds, project_data.pdf_settings)

            desc_bounds = create_bounds(cl, body_top + vp_h + 0.08, cw, card_h)
            add_text(doc, page, layer, "ПРИМЕЧАНИЕ: #{desc}", desc_bounds, 9.5)
          end

          draw_standard_footer(doc, page, layer, cl, ct + ch - fh, cw, fh, info, page_index, total_pages)
        end

        # Добавление видового экрана SketchUp в LayOut
        def add_model_viewport(doc, page, layer, skp_path, scene_item, bounds, settings)
          return unless skp_path && File.exist?(skp_path)

          begin
            viewport = ::Layout::SketchUpModel.new(skp_path, bounds)

            # Настройка сцены
            if viewport.respond_to?(:scenes)
              available_scenes = viewport.scenes rescue []
              if available_scenes.is_a?(Array) && !available_scenes.empty?
                idx = available_scenes.index(scene_item.name)
                if idx
                  viewport.current_scene = idx if viewport.respond_to?(:current_scene=)
                elsif scene_item.order && scene_item.order >= 0
                  # Смещение на 1 для Last Saved View
                  scene_target = [scene_item.order + 1, available_scenes.size - 1].min
                  viewport.current_scene = scene_target if viewport.respond_to?(:current_scene=)
                end
              end
            end

            # Настройка режима рендеринга видового экрана LayOut
            mode_str = settings[:layout_render_mode].to_s.downcase
            if defined?(::Layout::SketchUpModel)
              case mode_str
              when "vector"
                if defined?(::Layout::SketchUpModel::VECTOR_RENDER)
                  viewport.render_mode = ::Layout::SketchUpModel::VECTOR_RENDER rescue nil
                end
              when "hybrid"
                if defined?(::Layout::SketchUpModel::HYBRID_RENDER)
                  viewport.render_mode = ::Layout::SketchUpModel::HYBRID_RENDER rescue nil
                end
              else
                if defined?(::Layout::SketchUpModel::RASTER_RENDER)
                  viewport.render_mode = ::Layout::SketchUpModel::RASTER_RENDER rescue nil
                end
              end
            end

            # Рендеринг видового экрана
            if viewport.respond_to?(:render_needed?) && viewport.render_needed?
              viewport.render rescue nil
            end

            doc.add_entity(viewport, layer, page)
          rescue StandardError => e
            warn "Ошибка вставки видового экрана LayOut: #{e.message}"
          end
        end

        # Добавление текстового блока в LayOut
        def add_text(doc, page, layer, text_str, bounds, font_size = 10.0, is_bold = false)
          return if text_str.to_s.empty?

          begin
            if defined?(::Layout::FormattedText)
              text_ent = ::Layout::FormattedText.new(text_str.to_s, bounds)
              if text_ent.respond_to?(:style) && text_ent.style
                style = text_ent.style
                style.font_size = font_size if style.respond_to?(:font_size=)
                text_ent.style = style if text_ent.respond_to?(:style=)
              end
              doc.add_entity(text_ent, layer, page)
            end
          rescue StandardError => e
            warn "Ошибка добавления текста LayOut: #{e.message}"
          end
        end

        # Отрисовка стандартного верхнего колонтитула
        def draw_standard_header(doc, page, layer, x, y, w, h, info, scene_title, scene_desc = nil)
          project_text = "#{info[:name_project]}  |  #{info[:address]}".strip
          art_text     = info[:articul].to_s.empty? ? "" : "АРТ: #{info[:articul]}"
          first_line   = [project_text, art_text].reject(&:empty?).join("    ")

          lines = [first_line]
          lines << scene_title.to_s.strip unless scene_title.to_s.strip.empty?
          lines << scene_desc.to_s.strip unless scene_desc.to_s.strip.empty?
          header_str = lines.reject(&:empty?).join("\n")

          bounds = create_bounds(x, y, w, h)
          add_text(doc, page, layer, header_str, bounds, 11.0, true)
        end

        # Отрисовка стандартного нижнего колонтитула
        def draw_standard_footer(doc, page, layer, x, y, w, h, info, page_idx, total_pages)
          footer_str = "Ревизия v#{info[:version]}#r#{info[:revision]}  •  Дата: #{Time.now.strftime('%d.%m.%Y')}                     Лист #{page_idx} из #{total_pages}"
          bounds = create_bounds(x, y, w, h)
          add_text(doc, page, layer, footer_str, bounds, 9.0)
        end

        # Отрисовка штампа/водяного знака
        def draw_layout_stamp(doc, page, layer, cl, ct, cw, ch, settings)
          stamp_type = settings[:stamp_type].to_s
          return if stamp_type == "none" || stamp_type.empty?

          stamp_text = case stamp_type
                       when "draft" then settings[:stamp_custom] || "НЕ УТВЕРЖДЕН"
                       when "approved" then "В ПРОИЗВОДСТВО"
                       else settings[:stamp_custom] || "КОНЦЕПТ"
                       end

          stamp_str = "— #{stamp_text.upcase} —"
          stamp_bounds = create_bounds(cl + cw - 3.2, ct + ch - 0.8, 3.0, 0.4)
          add_text(doc, page, layer, stamp_str, stamp_bounds, 13.0, true)
        end

        # Создание объекта Bounds2d
        def create_bounds(x, y, w, h)
          if defined?(::Geom::Bounds2d)
            ::Geom::Bounds2d.new(x.to_f, y.to_f, w.to_f, h.to_f)
          elsif defined?(::Geom::Point2d)
            p1 = ::Geom::Point2d.new(x.to_f, y.to_f)
            p2 = ::Geom::Point2d.new((x + w).to_f, (y + h).to_f)
            ::Geom::Bounds2d.new(p1, p2) rescue [x, y, w, h]
          else
            [x.to_f, y.to_f, w.to_f, h.to_f]
          end
        end
      end
    end
  end
end
