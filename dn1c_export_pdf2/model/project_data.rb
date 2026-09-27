# frozen_string_literal: true

require "yaml"
require "json"
require "time"
require "date"
require "fileutils"
require_relative "scene_item"
require_relative "../service/font_service"

module DN1Code
  module ExportPdf2
    module Model
      # Модель данных проекта: хранит информацию о проекте, сценах, истории ревизий и параметрах PDF.
      # Единственный источник данных — YAML файлы: данные проекта — только внутри папки артикула
      # (<папка .skp>/<Артикул>/project.yaml), настройки PDF и шаблоны страниц —
      # в системных файлах YAML внутри расширения (settings.yaml + layout.yaml).
      # В одной папке может быть несколько проектов — у каждого свой артикул и своя
      # папка проекта; папку проекта для модели определяет артикул из самого .skp
      # (ModelArticulStore). Сохранение без артикула запрещено: save_project_yaml
      # не пишет данные на диск.
      class ProjectData
        # Пути к глобальным настройкам программы (хранятся внутри плагина)
        PLUGIN_CONFIG_DIR     = File.expand_path("../config", __dir__)
        PROGRAM_SETTINGS_FILE = File.join(PLUGIN_CONFIG_DIR, "settings.yaml")
        PROGRAM_LAYOUT_FILE   = File.join(PLUGIN_CONFIG_DIR, "layout.yaml")

        # Имя файла данных проекта внутри папки артикула
        PROJECT_YAML_NAME     = "project.yaml"

        # Допустимые пропорции кадра в настройках плагина
        VALID_ASPECT_RATIOS   = %w[page 16:9 4:3 3:2 5:4 4:5 1:1 custom].freeze

        # Метаданные шаблона, которые переносятся через layout.yaml
        # (имя, описание, база, иконка) — см. load_from_layout_yaml
        TEMPLATE_META_KEYS    = %w[name _name description _description _base_type _icon].freeze

        # Прокси-хэш для фасада @project_info: перенаправляет изменения напрямую
        # в модульные структуры (@project, @customer, @workflow) и синхронизирует синонимы полей
        class ProjectInfoProxy < Hash
          attr_accessor :owner

          def initialize(owner = nil)
            super()
            @owner = owner
          end

          def []=(key, val)
            k_sym = key.to_s.to_sym
            super(k_sym, val)
            return val unless @owner

            case k_sym
            when :articul
              val_s = val.to_s
              @owner.project[:articul] = val_s
              if val_s.start_with?("CF#")
                @owner.project[:commercial] = true
                super(:commercial, true)
                super(:trade, "1")
              elsif val_s.start_with?("HF#")
                @owner.project[:commercial] = false
                super(:commercial, false)
                super(:trade, "0")
              end
            when :articul_locked
              is_l = val == true || val.to_s == "true"
              @owner.project[:articul_locked] = is_l
              super(:articul_locked, is_l)
            when :name_project
              super(:name_project, val.to_s)
            when :product, :name_product, :furniture_name, :product_tags
              tags_arr = if val.is_a?(Array)
                           val.map(&:to_s).map(&:strip).reject(&:empty?)
                         else
                           val.to_s.split(",").map(&:strip).reject(&:empty?)
                         end
              prod_str = val.is_a?(Array) ? tags_arr.join(", ") : val.to_s
              @owner.project[:product_tags] = tags_arr
              @owner.project[:product] = prod_str
              super(:product_tags, tags_arr)
              super(:product, prod_str)
              super(:name_product, prod_str)
              super(:furniture_name, prod_str)
            when :place, :name_place, :room_name
              @owner.project[:place] = val.to_s
              super(:place, val.to_s)
              super(:name_place, val.to_s)
              super(:room_name, val.to_s)
            when :adress, :address
              @owner.project[:adress] = val.to_s
              super(:adress, val.to_s)
              super(:address, val.to_s)
            when :description, :task_description
              @owner.project[:description] = val.to_s
              super(:description, val.to_s)
              super(:task_description, val.to_s)
            when :tags
              tags_arr = val.is_a?(String) ? val.split(",").map(&:strip).reject(&:empty?) : (val || [])
              @owner.project[:tags] = tags_arr
              super(:tags, tags_arr)
            when :commercial
              is_c = val == true || val.to_s == "true" || val.to_s == "1"
              @owner.project[:commercial] = is_c
              super(:commercial, is_c)
              super(:trade, is_c ? "1" : "0")
            when :trade
              is_c = val.to_s == "1"
              @owner.project[:commercial] = is_c
              super(:commercial, is_c)
              super(:trade, val.to_s)
            when :customer, :name_customer, :name
              @owner.customer[:name] = val.to_s
              super(:customer, val.to_s)
              super(:name_customer, val.to_s)
              super(:name, val.to_s)
            when :customer_id, :id
              @owner.customer[:id] = val.to_s
              super(:customer_id, val.to_s)
              super(:id, val.to_s)
            when :company, :name_company
              @owner.customer[:company] = val.to_s
              @owner.project[:name_company] = val.to_s
              super(:company, val.to_s)
              super(:name_company, val.to_s)
            when :phone
              @owner.customer[:phone] = val.to_s
              super(:phone, val.to_s)
            when :email
              @owner.customer[:email] = val.to_s
              super(:email, val.to_s)
            when :author
              @owner.workflow[:author] = val.to_s
              super(:author, val.to_s)
            when :price
              @owner.workflow[:price] = val
              super(:price, val)
            when :start_date
              @owner.workflow[:start_date] = val.to_s
              super(:start_date, val.to_s)
            when :end_date
              @owner.workflow[:end_date] = val.to_s
              super(:end_date, val.to_s)
            when :total_duration
              @owner.workflow[:total_duration] = val.to_s
              super(:total_duration, val.to_s)
            when :rate
              @owner.workflow[:rate] = val.to_s
              super(:rate, val.to_s)
            when :status
              @owner.workflow[:status] = val.to_s
              super(:status, val.to_s)
            when :stadia
              norm = @owner.normalize_stadia(val)
              @owner.workflow[:stadia] = norm
              super(:stadia, norm)
            when :version
              v_int = val.to_i rescue 1
              v_int = 1 if v_int <= 0
              @owner.workflow[:version] = sprintf("%02d", v_int)
              super(:version, v_int)
            when :revision
              r_int = val.to_i rescue 1
              r_int = 1 if r_int <= 0
              @owner.workflow[:revision] = sprintf("%03d", r_int)
              super(:revision, r_int)
            when :last_edit, :edit
              @owner.workflow[:last_edit] = val.to_s
              super(:last_edit, val.to_s)
              super(:edit, val.to_s)
            when :history_edit
              @owner.workflow[:history_edit] = val
              super(:history_edit, val)
            when :notes, :materials, :appliances, :lighting, :task_dimensions, :task_wishes
              @owner.project[k_sym] = val if @owner.project.is_a?(Hash)
              super(k_sym, val)
            end

            # Обновляем составное имя проекта
            if [:product, :name_product, :furniture_name, :place, :name_place, :room_name].include?(k_sym)
              parts = [@owner.project[:place], @owner.project[:product]].map(&:to_s).map(&:strip).reject(&:empty?)
              p_title = parts.empty? ? "" : parts.join(" — ")
              super(:name_project, p_title) unless p_title.empty?
            end

            val
          end

          def merge!(other)
            return self unless other.is_a?(Hash)
            other.each { |k, v| self[k] = v }
            self
          end
        end

        # @return [Hash] паспорт объекта (articul, product, place, adress, description, tags, commercial, name_company)
        attr_accessor :project
        # @return [Hash] карточка заказчика (id, name, phone, email, company)
        attr_accessor :customer
        # @return [Hash] ход работы и жизненный цикл (author, price, start_date, end_date, total_duration, rate, status, version, revision, history_edit)
        attr_accessor :workflow
        # @return [Hash] метаданные и реквизиты проекта для обратной совместимости
        attr_accessor :project_info
        # @return [Array<SceneItem>] список сцен модели и их параметров экспорта
        attr_accessor :scenes
        # @return [Array<Hash>] история изменений и ревизий проекта
        attr_accessor :history
        # @return [Hash] параметры экспорта PDF (размер листа, поля, штамп, движок, макеты)
        attr_accessor :pdf_settings
        # @return [Array<String>] адресаты API веб-интеграции
        attr_accessor :api_targets
        # @return [Array<Hash>, Hash] каталоги проекта и настройки их отображения
        attr_accessor :directories

        # @return [Hash] конфигурация макетов страниц (прокси к @pdf_settings[:custom_layouts])
        def custom_layouts
          @pdf_settings ||= {}
          @pdf_settings[:custom_layouts] ||= default_custom_layouts
        end

        # Инициализирует новый экземпляр ProjectData со значениями по умолчанию
        def initialize
          @project      = default_project
          @customer     = default_customer
          @workflow     = default_workflow
          @project_info = ProjectInfoProxy.new(self)
          @project_info.merge!(default_project_info)
          @pdf_settings = default_pdf_settings
          @api_targets  = default_api_targets
          @directories  = []
          @scenes       = []
          @history      = []

          sync_project_fields!

          # Загружаем глобальные настройки программы из плагина
          load_program_settings
        end

        # Загружает глобальные настройки программы из файлов конфигурации плагина:
        # 1. settings.yaml -> параметры рендера PDF (@pdf_settings)
        # 2. layout.yaml -> макеты страниц (@pdf_settings[:custom_layouts])
        # @return [void]
        def load_program_settings
          # 1. Загрузка параметров PDF
          settings_file = PROGRAM_SETTINGS_FILE
          settings_file = File.join(PLUGIN_CONFIG_DIR, "default_settings.yaml") unless File.exist?(settings_file)
          if File.exist?(settings_file)
            begin
              content = File.read(settings_file, encoding: "utf-8")
              raw = begin
                      YAML.safe_load(content, permitted_classes: [Date, Time, Symbol])
                    rescue ArgumentError
                      YAML.load(content)
                    end
              if raw.is_a?(Hash)
                data = self.class.deep_symbolize_keys(raw)
                if data[:api_targets].is_a?(Array)
                  @api_targets = data[:api_targets].map(&:to_s).map(&:strip).reject(&:empty?)
                end
                pdf_cfg = data[:pdf_settings] || data
                if pdf_cfg.is_a?(Hash)
                  layouts_backup = @pdf_settings ? @pdf_settings[:custom_layouts] : nil
                  @pdf_settings ||= {}
                  @pdf_settings.merge!(pdf_cfg)
                  @pdf_settings[:custom_layouts] = layouts_backup if layouts_backup && !pdf_cfg.key?(:custom_layouts)
                  ratio_str = @pdf_settings[:image_aspect_ratio].to_s.strip
                  @pdf_settings[:image_aspect_ratio] = "4:3" unless VALID_ASPECT_RATIOS.include?(ratio_str)
                  # Устаревший ключ: формат снимков теперь определяется доступностью libvips
                  @pdf_settings.delete(:snapshot_format)
                  legacy_font = Service::FontService.legacy_family_for(@pdf_settings[:font_family])
                  @pdf_settings[:font_family] = legacy_font if legacy_font
                end
              end
            rescue StandardError => e
              warn "Ошибка загрузки настроек программы (#{settings_file}): #{e.message}"
            end
          end

          # 2. Загрузка макетов страниц
          layout_file = PROGRAM_LAYOUT_FILE
          layout_file = File.join(PLUGIN_CONFIG_DIR, "default_layout.yaml") unless File.exist?(layout_file)
          if File.exist?(layout_file)
            load_from_layout_yaml(layout_file)
          end
        end

        # Сохраняет текущие настройки программы в файлы конфигурации плагина:
        # 1. settings.yaml <- параметры PDF (@pdf_settings без custom_layouts)
        # 2. layout.yaml <- макеты страниц (@pdf_settings[:custom_layouts])
        # @return [Boolean] true в случае успешного сохранения
        def save_program_settings
          FileUtils.mkdir_p(PLUGIN_CONFIG_DIR)

          # 1. Сохранение параметров PDF
          pdf_clean = (@pdf_settings || default_pdf_settings).dup
          pdf_clean.delete(:custom_layouts)
          pdf_clean.delete("custom_layouts")

          settings_data = {
            "pdf_settings" => self.class.deep_stringify_keys(pdf_clean),
            "api_targets"  => (@api_targets || []).map(&:to_s).map(&:strip).reject(&:empty?)
          }
          File.open(PROGRAM_SETTINGS_FILE, "w:utf-8") do |f|
            f.write settings_data.to_yaml
          end

          # 2. Сохранение макетов страниц
          save_to_layout_yaml(PROGRAM_LAYOUT_FILE)

          true
        rescue StandardError => e
          warn "Ошибка сохранения настроек программы: #{e.message}"
          false
        end

        # Обновляет параметры рамки кадра (Overlay) в памяти (только @pdf_settings сессии).
        # Запись в settings.yaml выполняется отдельно при flush (save_program_settings).
        # @param params [Hash] параметры рамки (:image_aspect_ratio, :aspect_ratio, :custom_ratio_w, :custom_ratio_h, :show_aspect_overlay, :overlay_border_color, etc.)
        # @return [Boolean]
        def update_frame_settings(params)
          return false unless params.is_a?(Hash)

          ratio_val = params[:image_aspect_ratio] || params["image_aspect_ratio"] || params[:aspect_ratio] || params["aspect_ratio"]
          if ratio_val && !ratio_val.to_s.strip.empty?
            ratio_str = ratio_val.to_s.strip
            @pdf_settings[:image_aspect_ratio] = ratio_str if VALID_ASPECT_RATIOS.include?(ratio_str)
          end

          if params.key?(:custom_ratio_w) || params.key?("custom_ratio_w")
            cw = (params[:custom_ratio_w] || params["custom_ratio_w"]).to_f
            @pdf_settings[:custom_ratio_w] = cw if cw > 0.0
          end

          if params.key?(:custom_ratio_h) || params.key?("custom_ratio_h")
            ch = (params[:custom_ratio_h] || params["custom_ratio_h"]).to_f
            @pdf_settings[:custom_ratio_h] = ch if ch > 0.0
          end

          if params.key?(:show_aspect_overlay) || params.key?("show_aspect_overlay")
            v = params[:show_aspect_overlay]
            v = params["show_aspect_overlay"] if v.nil?
            @pdf_settings[:show_aspect_overlay] = (v == true || v.to_s == "true")
          end

          [:overlay_border_color, :overlay_border_opacity, :overlay_mask_color, :overlay_mask_opacity].each do |k|
            val = params[k] || params[k.to_s]
            @pdf_settings[k] = val unless val.nil?
          end

          true
        end

        # Возвращает паспорт объекта по умолчанию
        # @return [Hash]
        def default_project
          {
            articul:      "",
            articul_locked: false,
            product_tags: [],
            product:      "",
            place:        "",
            adress:       "",
            description:  "",
            tags:         [],
            commercial:   false,
            name_company: ""
          }
        end

        # Возвращает карточку заказчика по умолчанию
        # @return [Hash]
        def default_customer
          {
            id:      "",
            name:    "",
            phone:   "",
            email:   "",
            company: ""
          }
        end

        # Возвращает эталонный список стадий проекта (по умолчанию из project.yaml)
        # @return [Array<Hash>]
        def default_stadia
          [
            { name: "Предварительный проект", status: true },
            { name: "Правки проекта (история правок)", status: false },
            { name: "Выбраны материалы и фурнитура", status: false },
            { name: "Предварительно Утвержден", status: false },
            { name: "Проверка технологом", status: false },
            { name: "Утвержден", status: false },
            { name: "Отправлен в производство", status: false },
            { name: "Оплачен", status: false }
          ]
        end

        # Нормализует список стадий к массиву хэшей [{ name: "...", status: true/false }]
        # @param val [Object]
        # @return [Array<Hash>]
        def normalize_stadia(val)
          return default_stadia if val.nil?

          if val.is_a?(Array)
            return default_stadia if val.empty?
            val.map do |st|
              if st.is_a?(Hash)
                nm = (st[:name] || st["name"] || st[:title] || st["title"]).to_s.strip
                s  = (st[:status] == true || st["status"] == true || st[:status].to_s == "true" || st["status"].to_s == "true")
                { name: nm, status: s }
              elsif st.is_a?(Array)
                if st.size >= 3
                  { name: st[2].to_s.strip, status: (st[1] == true || st[1].to_s == "true") }
                elsif st.size == 2
                  if st[1] == true || st[1] == false || st[1].to_s == "true" || st[1].to_s == "false"
                    { name: st[0].to_s.strip, status: (st[1] == true || st[1].to_s == "true") }
                  else
                    { name: st[1].to_s.strip, status: (st[0] == true || st[0].to_s == "true") }
                  end
                else
                  { name: st[0].to_s.strip, status: false }
                end
              else
                { name: st.to_s.strip, status: false }
              end
            end
          elsif val.is_a?(String) && !val.strip.empty?
            [{ name: val.strip, status: true }]
          else
            default_stadia
          end
        end

        # Возвращает параметры хода работы над проектом по умолчанию
        # @return [Hash]
        def default_workflow
          {
            author:         "",
            price:          "",
            start_date:     "",
            end_date:       "",
            total_duration: "",
            rate:           "",
            status:         "Правки",
            version:        "01",
            revision:       "001",
            stadia:         default_stadia,
            history_edit:   []
          }
        end

        # Генерирует артикул проекта по шаблону: CF#ГГММДД_ЧЧММСС или HF#...
        # @param commercial [Boolean] true для коммерческого (CF#), false для бытового (HF#)
        # @param time [Time] метка времени
        # @return [String]
        def self.generate_articul(commercial: false, time: Time.now)
          prefix = commercial ? "CF#" : "HF#"
          "#{prefix}#{time.strftime('%y%m%d_%H%M%S')}"
        end

        # Генерирует автоматический номер/ID заказчика
        # @param name [String, nil] имя заказчика (принимается для совместимости с веб-интерфейсом)
        # @param time [Time] метка времени
        # @return [String]
        def self.generate_customer_id(name: nil, time: Time.now)
          "CUST-#{time.strftime('%y%m%d%H%M')}"
        end

        # Возвращает структуру метаданных проекта по умолчанию для обратной совместимости
        # @return [Hash] хэш с параметрами проекта
        def default_project_info
          {
            articul:          "",
            articul_locked:   false,
            name_product:     "",
            name_place:       "",
            adress:           "",
            customer:         "",
            company:          "",
            status:           "Правки",
            revision:         1,
            version:          1,
            last_edit:        "",
            trade:            "0",
            # Синонимы для обратной совместимости с существующим кодом и спецификациями
            room_name:        "",
            furniture_name:   "",
            name_customer:    "",
            address:          "",
            edit:             "",
            name_project:     "",
            description:      "",
            phone:            "",
            email:            "",
            task_description: "",
            task_dimensions:  "",
            task_wishes:      "",
            materials:        "",
            appliances:       "",
            lighting:         "",
            notes:            ""
          }
        end

        # Возвращает список адресатов API по умолчанию.
        # Плейсхолдеры: реальные токены хранятся в локальных YAML-файлах,
        # которые не попадают в git (settings.yaml в .gitignore).
        # @return [Array<String>]
        def default_api_targets
          [
            "https://list.prodmd.top/api/projects?token=YOUR_TOKEN_HERE",
            "http://localhost:3000/api/projects?token=YOUR_LOCAL_TOKEN"
          ]
        end

        # Возвращает конфигурацию шаблонов страниц по умолчанию (в процентах).
        # Готовые шаблоны — это обычные шаблоны: пользователь может их удалять,
        # переименовывать и менять описание; удалённые не восстанавливаются
        # (сид попадает в layout.yaml при первом сохранении).
        # @return [Hash] для каждого шаблона: имя, описание, видовое окно, параметры.
        def default_custom_layouts
          default_image_block = {
            x: 25.0, y: 12.0, w: 50.0, h: 82.0,
            visible: true, content: "render_viewport",
            show_background: false, aspect_ratio: "4:3", scale_pct: 100
          }

          # line_gap / line_enabled — общие настройки стека параметров шаблона:
          # «размер между строками» (мм) и тонкая линия-разделитель между
          # параметрами и блоками (задаются в шапке карточки «Параметры страницы»)
          {
            cover: {
              name: "Титульный лист (Cover)", description: "Титульный лист: название проекта, заказчик, артикул",
              image_4_3: default_image_block.dup, params: [], line_gap: 2.5, line_enabled: false
            },
            description: {
              name: "Описание и спецификации (Description)", description: "Описание изделия и спецификации",
              image_4_3: default_image_block.dup, params: [], line_gap: 2.5, line_enabled: false
            },
            explain: {
              name: "Содержание и ведомость (Explain)", description: "Содержание и ведомость материалов",
              image_4_3: default_image_block.dup, params: [], line_gap: 2.5, line_enabled: false
            },
            general: {
              name: "Общий вид (General)", description: "Общий вид изделия с основными параметрами",
              image_4_3: default_image_block.dup, params: [], line_gap: 2.5, line_enabled: false
            },
            visual: {
              name: "Визуализация (Visual)", description: "Крупная визуализация вида модели",
              image_4_3: default_image_block.dup, params: [], line_gap: 2.5, line_enabled: false
            },
            blank: {
              name: "Без шаблона (Blank)", description: "Пустая страница: только видовой экран",
              image_4_3: default_image_block.merge(aspect_ratio: "16:9"), params: [], line_gap: 2.5, line_enabled: false
            }
          }
        end

        # Возвращает базовые настройки экспорта PDF по умолчанию
        # @return [Hash] хэш с параметрами PDF (размер листа, ориентация, цвета, штамп и т.д.)
        def default_pdf_settings
          {
            layout_render_mode: "image",
            save_layout_file:   true,
            compress_pdf:       true,
            image_format:       "png",
            webp_quality:       85,
            render_quality:     "medium",
            page_size:          "A3",
            page_layout:        "landscape",
            margin:             15,
            margin_mm:          5,
            image_width:        1754,
            image_aspect_ratio: "4:3",
            custom_ratio_w:     16,
            custom_ratio_h:     9,
            show_aspect_overlay: false,
            overlay_border_color:   "#FF0000",
            overlay_border_opacity: 100,
            overlay_mask_color:     "#0F172A",
            overlay_mask_opacity:   10,
            scale_factor:       2.0,
            scale_multiplier:   "2.0",
            annotation_font_size: "auto",
            antialias:          true,
            stamp_type:         "draft",
            stamp_custom:       "НЕ УТВЕРЖДЕН",
            auto_open_pdf:      true,
            save_skp_backup:    true,
            primary_color:      "005EB0",
            secondary_color:    "64748B",
            stamp_color:        "D32F2F",
            font_family:        "Sofia Sans Condensed",
            font_weight:        "normal",
            font_width:         "condensed",
            custom_layouts:     default_custom_layouts
          }
        end

        # Вспомогательный метод: выбирает первую непустую строку из переданных аргументов
        # @param vals [Array<Object>]
        # @return [String]
        def self.pick_str(*vals)
          vals.each do |v|
            s = v.to_s.strip
            return s unless s.empty?
          end
          ""
        end

        # Двусторонняя синхронизация полей между модульными сущностями (@project, @customer, @workflow),
        # структурой каталогов @directories и фасадом @project_info для 100% обратной совместимости
        def sync_project_fields!
          @project      ||= default_project
          @customer     ||= default_customer
          @workflow     ||= default_workflow
          @project_info ||= default_project_info

          # --- 1. Артикул и коммерческий флаг (CF# / HF#) ---
          art = self.class.pick_str(@project[:articul], @project_info[:articul])
          @project[:articul]      = art
          @project_info[:articul] = art

          # Блокировка артикула: источник истины — @project; nil (флаг не задан)
          # означает правило «артикул создан однажды => заблокирован»
          lock_raw = @project[:articul_locked]
          locked = lock_raw.nil? ? !art.empty? : (lock_raw == true || lock_raw.to_s == "true")
          @project[:articul_locked]      = locked
          @project_info[:articul_locked] = locked

          # Commercial flag <=> Trade ('1'/'0')
          is_comm = if @project.key?(:commercial) && !@project[:commercial].nil?
                      @project[:commercial] == true || @project[:commercial].to_s == "true"
                    elsif art.start_with?("CF#")
                      true
                    elsif art.start_with?("HF#")
                      false
                    elsif @project_info[:trade].to_s == "1"
                      true
                    else
                      false
                    end
          @project[:commercial]   = is_comm
          @project_info[:trade]   = is_comm ? "1" : "0"

          # --- 2. Изделие и помещение (Product / Place) ---
          prod_tags = @project[:product_tags] || @project_info[:product_tags]
          if prod_tags.is_a?(String)
            prod_tags = prod_tags.split(",").map(&:strip).reject(&:empty?)
          end
          prod_tags = [] unless prod_tags.is_a?(Array)

          prod = self.class.pick_str(@project[:product], @project_info[:name_product], @project_info[:furniture_name])
          if prod_tags.empty? && !prod.empty?
            prod_tags = prod.split(",").map(&:strip).reject(&:empty?)
          elsif prod.empty? && !prod_tags.empty?
            prod = prod_tags.join(", ")
          end

          @project[:product_tags]        = prod_tags
          @project_info[:product_tags]   = prod_tags
          @project[:product]             = prod
          @project_info[:name_product]   = prod
          @project_info[:furniture_name] = prod

          plc = self.class.pick_str(@project[:place], @project_info[:name_place], @project_info[:room_name])
          @project[:place]            = plc
          @project_info[:name_place]  = plc
          @project_info[:room_name]   = plc

          # --- 3. Адрес объекта ---
          adr = self.class.pick_str(@project[:adress], @project_info[:adress], @project_info[:address])
          @project[:adress]       = adr
          @project_info[:adress]  = adr
          @project_info[:address] = adr

          # --- 4. Описание и теги проекта ---
          desc = self.class.pick_str(@project[:description], @project_info[:description], @project_info[:task_description])
          @project[:description]        = desc
          @project_info[:description]   = desc
          @project_info[:task_description] = desc if @project_info[:task_description].to_s.empty?

          tags_val = @project[:tags] || @project_info[:tags] || []
          if tags_val.is_a?(String)
            tags_val = tags_val.split(",").map(&:strip).reject(&:empty?)
          end
          @project[:tags]      = tags_val.is_a?(Array) ? tags_val : []
          @project_info[:tags] = @project[:tags]

          # --- 5. Заказчик и компания (Customer) ---
          c_id = self.class.pick_str(@customer[:id], @project_info[:customer_id])
          @customer[:id]             = c_id
          @project_info[:customer_id]= c_id

          c_name = self.class.pick_str(@customer[:name], @project_info[:customer], @project_info[:name_customer])
          @customer[:name]              = c_name
          @project_info[:customer]      = c_name
          @project_info[:name_customer] = c_name

          c_comp = self.class.pick_str(@customer[:company], @project[:name_company], @project_info[:company])
          @customer[:company]       = c_comp
          @project[:name_company]   = c_comp
          @project_info[:company]   = c_comp

          c_phone = self.class.pick_str(@customer[:phone], @project_info[:phone])
          @customer[:phone]       = c_phone
          @project_info[:phone]   = c_phone

          c_email = self.class.pick_str(@customer[:email], @project_info[:email])
          @customer[:email]       = c_email
          @project_info[:email]   = c_email

          # --- 6. Ход работы (Workflow) ---
          w_author = self.class.pick_str(@workflow[:author], @project_info[:author])
          @workflow[:author]     = w_author
          @project_info[:author] = w_author

          w_price = @workflow[:price]
          w_price = @project_info[:price] if (w_price.nil? || w_price.to_s.strip.empty?) && !@project_info[:price].to_s.strip.empty?
          @workflow[:price]     = w_price
          @project_info[:price] = w_price

          w_start = self.class.pick_str(@workflow[:start_date], @project_info[:start_date])
          @workflow[:start_date]     = w_start
          @project_info[:start_date] = w_start

          w_end = self.class.pick_str(@workflow[:end_date], @project_info[:end_date])
          @workflow[:end_date]     = w_end
          @project_info[:end_date] = w_end

          w_dur = self.class.pick_str(@workflow[:total_duration], @project_info[:total_duration])
          @workflow[:total_duration]     = w_dur
          @project_info[:total_duration] = w_dur

          w_rate = self.class.pick_str(@workflow[:rate], @project_info[:rate])
          @workflow[:rate]     = w_rate
          @project_info[:rate] = w_rate

          # Стадии проекта (Stadia)
          st_raw = @workflow[:stadia] || @project_info[:stadia]
          norm_stadia = normalize_stadia(st_raw)
          @workflow[:stadia]     = norm_stadia
          @project_info[:stadia] = norm_stadia

          w_status = self.class.pick_str(@workflow[:status], @project_info[:status])
          if w_status.empty?
            last_done = norm_stadia.reverse.find { |s| s[:status] == true }
            w_status = last_done ? last_done[:name] : "Предварительный"
          end
          @workflow[:status]     = w_status
          @project_info[:status] = w_status

          # Версия и Ревизия (поддержка и форматированных строк "001", и целых чисел)
          v_raw = @workflow[:version] || @project_info[:version] || 1
          v_int = v_raw.to_i rescue 1
          v_int = 1 if v_int <= 0
          @workflow[:version]     = sprintf("%02d", v_int)
          @project_info[:version] = v_int

          r_raw = @workflow[:revision] || @project_info[:revision] || 1
          r_int = r_raw.to_i rescue 1
          r_int = 1 if r_int <= 0
          @workflow[:revision]     = sprintf("%03d", r_int)
          @project_info[:revision] = r_int

          # Синхронизация истории правок: @workflow[:history_edit] [[date, text]] <=> @history [{date:, text:}]
          sync_history_entries!

          # Последняя правка last_edit
          ledit = (@workflow[:last_edit] || @project_info[:last_edit] || @project_info[:edit]).to_s.strip
          if ledit.empty? && !@history.empty?
            ledit = @history.first[:text].to_s
          end
          @workflow[:last_edit]     = ledit
          @project_info[:last_edit] = ledit
          @project_info[:edit]      = ledit

          # Составной заголовок проекта
          parts = [plc, prod].reject(&:empty?)
          if !parts.empty?
            @project_info[:name_project] = parts.join(" — ")
          end

          # Нормализация directories к массиву хэшей
          normalize_directories!

          # Синхронизация спецификаций из каталогов directories в фасад project_info
          sync_directories_specifications!
        end

        # Синхронизирует спецификации проекта, связывая их с описаниями (description) в каталогах directories
        def sync_directories_specifications!
          dirs = @directories.is_a?(Array) ? @directories : normalize_directories_to_array(@directories)
          return if dirs.nil? || dirs.empty?

          dirs.each do |d|
            next unless d.is_a?(Hash)
            path_str  = (d[:path] || d["path"]).to_s.downcase
            title_str = (d[:title] || d["title"]).to_s.downcase
            desc_val  = (d[:description] || d["description"]).to_s.strip

            desc_is_real = !desc_val.empty? && desc_val != "Дополнительное описание"

            # 1. Материалы и фурнитура
            if path_str.include?("материал") || path_str.include?("фурнитур") ||
               title_str.include?("материал") || title_str.include?("фурнитур")
              if desc_is_real
                @project_info[:materials] = desc_val
              elsif !@project_info[:materials].to_s.strip.empty?
                d[:description] = @project_info[:materials].to_s
              end
            # 2. Техника и подсветка
            elsif path_str.include?("техник") || path_str.include?("подсветк") ||
                  title_str.include?("техник") || title_str.include?("подсветк")
              if desc_is_real
                @project_info[:appliances] = desc_val if @project_info[:appliances].to_s.strip.empty?
                @project_info[:lighting]   = desc_val if @project_info[:lighting].to_s.strip.empty?
              else
                comb = [@project_info[:appliances], @project_info[:lighting]].map(&:to_s).reject { |s| s.strip.empty? }.join("; ")
                d[:description] = comb unless comb.empty?
              end
            # 3. Замеры помещения и ТЗ
            elsif path_str.include?("замер") || title_str.include?("замер")
              if desc_is_real
                @project_info[:task_dimensions] = desc_val if @project_info[:task_dimensions].to_s.strip.empty?
              end
            # 4. Инфо заказчика и примечания
            elsif path_str.include?("инфо") || path_str.include?("заказчик") ||
                  title_str.include?("инфо") || title_str.include?("заказчик")
              if desc_is_real
                @project_info[:notes] = desc_val if @project_info[:notes].to_s.strip.empty?
              end
            end
          end

          # Если notes всё еще пустое, сформировать сводную записку из описаний каталогов
          if @project_info[:notes].to_s.strip.empty?
            spec_lines = []
            dirs.each do |d|
              desc = (d[:description] || d["description"]).to_s.strip
              title = (d[:title] || d["title"]).to_s.strip
              next if desc.empty? || desc == "Дополнительное описание"
              spec_lines << "#{title}: #{desc}"
            end
            @project_info[:notes] = spec_lines.join("\n") unless spec_lines.empty?
          end
        end

        # Отделяет вшитый номер ревизии от текста правки ("Текст правки (rev. 004)").
        # @return [Array<String, String>] [чистый текст, ревизия "004" или ""]
        def split_history_rev(text)
          raw = text.to_s
          m = raw.match(/\(rev\.?\s*(\d{1,})\)\s*\z/i)
          return [raw, ""] unless m
          [raw.sub(/\s*\(rev\.?\s*\d{1,}\)\s*\z/i, "").strip, format("%03d", m[1].to_i)]
        end

        # Приводит запись истории (массив/хэш/строка) к канонической форме:
        # чистый текст без вшитой ревизии + отдельные поля ver/rev записи.
        # @return [Hash]
        def normalize_history_entry(item)
          if item.is_a?(Array)
            d   = item[0].to_s
            t   = item[1].to_s
            lnk = item[2].to_s
            ver = ""
            rev = ""
          elsif item.is_a?(Hash)
            d   = (item[:data] || item[:date] || item["data"] || item["date"]).to_s
            t   = (item[:edit] || item[:text] || item["edit"] || item["text"] || item[:description] || item["description"]).to_s
            lnk = (item[:pdf_link] || item["pdf_link"]).to_s
            ver = (item[:ver] || item["ver"] || item[:version] || item["version"]).to_s
            rev = (item[:rev] || item["rev"]).to_s
          else
            d   = ""
            t   = item.to_s
            lnk = ""
            ver = ""
            rev = ""
          end
          # Миграция старых записей: "(rev. 004)" из текста переносится в поле rev
          t, rev = split_history_rev(t) if rev.empty?
          { date: d, text: t, description: t, data: d, edit: t, pdf_link: lnk, ver: ver, rev: rev }
        end

        # Синхронизирует кортежи @workflow[:history_edit] и структуру @history
        def sync_history_entries!
          @workflow[:history_edit] ||= []
          @history                 ||= []

          if @history.empty?
            unless @workflow[:history_edit].empty?
              @history = @workflow[:history_edit].map { |item| normalize_history_entry(item) }
            end
          else
            @history = @history.map { |item| normalize_history_entry(item) }
            if @workflow[:history_edit].empty?
              @workflow[:history_edit] = @history.map { |n| [n[:data], n[:text]] }
            end
          end

          # Канонический порядок записей истории: новые сверху (newest-first)
          normalize_history_order!
        end

        # Нормализует порядок записей истории к каноническому "новые сверху".
        # Если массив хронологический (старые сверху, даты возрастают) — разворачивает его.
        # Записи без дат или с убывающими датами остаются в исходном порядке (уже newest-first).
        # @return [void]
        def normalize_history_order!
          reorder = lambda do |arr, date_of|
            return arr if arr.nil? || arr.size < 2

            d_first = date_of.call(arr.first).to_s
            d_last  = date_of.call(arr.last).to_s
            (!d_first.empty? && !d_last.empty? && d_first < d_last) ? arr.reverse : arr
          end

          @history = reorder.call(@history, lambda do |h|
            h.is_a?(Hash) ? (h[:date] || h["date"] || h[:data] || h["data"]) : ""
          end)
          @workflow[:history_edit] = reorder.call(@workflow[:history_edit], lambda do |e|
            if e.is_a?(Array)
              e[0]
            elsif e.is_a?(Hash)
              (e[:data] || e["data"] || e[:date] || e["date"])
            end
          end)
          nil
        end

        # Привязывает путь к PDF-файлу к самой свежей записи истории изменений.
        # Пустая ссылка заполняется только у одной (самой верхней) записи: повторный
        # экспорт «без записи правок» не затирает ссылку предыдущей правки.
        # @param pdf_path [String] путь к версионному PDF этого экспорта
        # @return [Boolean] true, если ссылка была проставлена
        def stamp_history_pdf_link!(pdf_path)
          entry = @history.is_a?(Array) ? @history.find { |h| h.is_a?(Hash) } : nil
          return false unless entry

          key = if entry.key?(:pdf_link)
                  :pdf_link
                elsif entry.key?("pdf_link")
                  "pdf_link"
                else
                  :pdf_link # каноническая форма — всегда пишем символьный ключ
                end
          return false unless entry[key].to_s.strip.empty?

          entry[key] = pdf_path.to_s
          true
        end

        # Нормализует каталоги directories: приводит к массиву хэшей.
        # Пустой список НЕ заменяется дефолтами — новая модель стартует без папок,
        # а удаление всех папок пользователем сохраняется.
        def normalize_directories!
          @directories = normalize_directories_to_array(@directories)
        end

        # Преобразует каталоги в чистый массив хэшей для сохранения в YAML
        # @param dirs [Object]
        # @return [Array<Hash>]
        def normalize_directories_to_array(dirs)
          return [] if dirs.nil?
          if dirs.is_a?(Hash)
            dirs.map do |k, v|
              next unless v.is_a?(Hash)
              p_val = (v[:path] || v["path"] || "").to_s
              t_val = (v[:title] || v["title"] || "").to_s
              t_val = File.basename(p_val) if t_val.empty? && !p_val.empty?
              t_val = k.to_s if t_val.empty?
              item = {
                path:        p_val,
                title:       t_val,
                description: (v[:description] || v["description"] || "").to_s
              }
              item[:display] = (v[:display] || v["display"]).to_s if v[:display] || v["display"]
              item[:thumb_size] = (v[:thumb_size] || v["thumb_size"]).to_s if v[:thumb_size] || v["thumb_size"]
              item
            end.compact
          elsif dirs.is_a?(Array)
            dirs.map do |d|
              next unless d.is_a?(Hash)
              p_val = (d[:path] || d["path"] || "").to_s
              t_val = (d[:title] || d["title"] || "").to_s
              t_val = File.basename(p_val) if t_val.empty? && !p_val.empty?
              item = {
                path:        p_val,
                title:       t_val,
                description: (d[:description] || d["description"] || "").to_s
              }
              item[:display] = (d[:display] || d["display"]).to_s if d[:display] || d["display"]
              item[:thumb_size] = (d[:thumb_size] || d["thumb_size"]).to_s if d[:thumb_size] || d["thumb_size"]
              item
            end.compact
          else
            []
          end
        end

        # Очищает строку имени от запрещенных символов файловой системы
        # @param name [String, Object] исходное имя файла
        # @return [String] безопасное для файловой системы имя
        def self.sanitize_filename(name)
          name.to_s.gsub(/[\\\/:\*\?"<>\|]/, "_").strip
        end

        # Суффикс версии и ревизии для имен файлов истории ("01#001")
        # @param project_info [Hash] метаданные проекта
        # @return [String]
        def self.version_rev_suffix(project_info)
          sprintf("%02d#%03d", project_info[:version] || 1, project_info[:revision] || 1)
        end

        # Имя папки артикула: санитизированный артикул, фолбэк — имя файла модели
        # @param project_info [Hash] метаданные проекта
        # @param model [Sketchup::Model, nil] модель SketchUp
        # @return [String, nil] имя папки или nil, если определить невозможно
        def self.articul_folder_name(project_info, model = nil)
          articul = project_info && project_info[:articul] ? project_info[:articul].to_s.strip : ""
          unless articul.empty?
            clean_name = sanitize_filename(articul)
            return clean_name unless clean_name.empty?
          end

          if model && model.respond_to?(:path) && !model.path.to_s.empty?
            clean_base = sanitize_filename(File.basename(model.path.to_s.tr("\\", "/"), ".*"))
            return clean_base unless clean_base.empty?
          end

          nil
        end

        # Папка артикула проекта: <папка .skp>/<Артикул>
        # @param model [Sketchup::Model, nil] модель SketchUp
        # @return [String, nil] абсолютный путь к папке артикула или nil
        def articul_dir_for_model(model)
          return nil unless model && model.respond_to?(:path) && !model.path.to_s.empty?

          folder_name = self.class.articul_folder_name(@project_info, model)
          return nil if folder_name.nil? || folder_name.empty?

          File.expand_path(File.join(File.dirname(model.path.to_s.tr("\\", "/")), folder_name))
        end

        # Полный путь к файлу данных проекта: <папка артикула>/project.yaml.
        # Артикул обязателен: без него путь (и сохранение) невозможен.
        # @param model [Sketchup::Model] модель SketchUp
        # @return [String, nil] путь к файлу YAML или nil, если нет артикула или модель не сохранена
        def yaml_path_for_model(model)
          return nil unless model && model.respond_to?(:path) && !model.path.to_s.empty?
          return nil if @project_info[:articul].to_s.strip.empty?

          art_dir = articul_dir_for_model(model)
          return nil if art_dir.nil? || art_dir.empty?

          File.join(art_dir, PROJECT_YAML_NAME)
        end

        # Автоматическая загрузка данных:
        # 1. Глобальные настройки программы из плагина (settings.yaml + layout.yaml)
        # 2. Данные проекта: project.yaml в папке артикула <папка .skp>/<Артикул>.
        #    Артикул берется только из самого файла модели (.skp, ModelArticulStore):
        #    в одной папке может быть несколько проектов — у каждого свой артикул
        #    и своя папка проекта, файловая эвристика не используется
        # 3. Журнал правок: <Артикул>/edit_history.yaml
        # Модель без артикула в .skp проект не загружает (источник :default):
        # артикул создается через панель либо привязывается через «Импорт YAML».
        # @param model [Sketchup::Model, nil] модель SketchUp
        # @return [Symbol] источник загрузки (:yaml или :default)
        def load_auto(model)
          # Всегда начинаем с загрузки актуальных глобальных настроек программы из плагина
          load_program_settings

          loaded_from = nil

          # 2. Артикул из самого файла модели (.skp) определяет папку проекта
          skp_articul = ModelArticulStore.read(model)
          unless skp_articul.empty?
            @project_info[:articul] = skp_articul
            art_dir = articul_dir_for_model(model)
            if art_dir && File.directory?(art_dir)
              project_yaml = File.join(art_dir, PROJECT_YAML_NAME)
              loaded_from = :yaml if File.exist?(project_yaml) && load_from_yaml(project_yaml, include_settings: false)
            end
          end

          # 3. Журнал правок — только внутри папки артикула
          if model && !@project_info[:articul].to_s.strip.empty?
            art_dir = articul_dir_for_model(model)
            hist_file = art_dir ? File.join(art_dir, "edit_history.yaml") : nil
            load_from_edit_history(hist_file, @project_info[:articul]) if hist_file && File.exist?(hist_file)

            # Шаблоны страниц НЕ читаются из папки проекта:
            # единый источник — layout.yaml внутри расширения (общий для всех .skp)
          end

          # Запись в библиотеку модели (.skp) при загрузке не выполняется: атрибут
          # артикула пишется только в точках сохранения (save_project_yaml,
          # createProjectFolder, SessionStore.import_project_yaml).

          # Нормализация пропорций фрейма к 4:3 при недопустимом значении
          saved_val = @pdf_settings[:image_aspect_ratio].to_s.strip
          unless VALID_ASPECT_RATIOS.include?(saved_val)
            @pdf_settings[:image_aspect_ratio] = "4:3"
          end

          # Синхронизация списка сцен из модели
          sync_with_model_scenes(model) if model

          loaded_from || :default
        end

        # Сохранение данных проекта в YAML: единственный файл — project.yaml внутри
        # папки артикула (<папка .skp>/<Артикул>/project.yaml).
        # Без артикула данные проекта на диск не пишутся — метод возвращает false.
        # После успешной записи артикул дублируется в атрибуты модели (.skp).
        # @param model [Sketchup::Model] модель SketchUp
        # @return [Boolean] true в случае успешного сохранения
        def save_project_yaml(model)
          return false unless model
          return false unless model.respond_to?(:path) && !model.path.to_s.empty?

          sync_project_fields!

          # Артикул обязателен: без него проект не сохраняется
          return false if @project_info[:articul].to_s.strip.empty?

          target_yaml = yaml_path_for_model(model)
          return false unless target_yaml

          FileUtils.mkdir_p(File.dirname(target_yaml)) rescue nil
          save_to_yaml(target_yaml, include_settings: false) &&
            # Артикул дублируется в атрибуты модели (.skp): после сохранения файла
            # модель в любой сессии определяет свою папку проекта по артикулу
            ModelArticulStore.write(model, @project_info[:articul])
        end

        # Применяет данные формы (payload из веб-интерфейса) к текущему объекту в памяти.
        # Запись на диск не выполняется — данные живут в сессии до flush.
        # @param payload [Hash] данные из диалога (project, customer, workflow, pdf_settings, scenes, ...)
        # @return [self]
        def apply_payload!(payload)
          return self unless payload.is_a?(Hash)

          @project.merge!(payload[:project]) if payload[:project].is_a?(Hash)
          @customer.merge!(payload[:customer]) if payload[:customer].is_a?(Hash)
          @workflow.merge!(payload[:workflow]) if payload[:workflow].is_a?(Hash)

          info_src = payload[:project] || payload[:project_info]
          @project_info.merge!(info_src) if info_src

          if payload.key?(:api_targets) && payload[:api_targets].is_a?(Array)
            @api_targets = payload[:api_targets].map(&:to_s).map(&:strip).reject(&:empty?)
          end
          @directories = payload[:directories] if payload[:directories].is_a?(Array)
          @pdf_settings.merge!(payload[:pdf_settings]) if payload[:pdf_settings]
          if payload[:history_edit] && payload[:history_edit].is_a?(Array)
            @history = payload[:history_edit].map { |item| normalize_history_entry(item) }
          elsif payload[:history]
            @history = payload[:history].is_a?(Array) ? payload[:history].map { |item| normalize_history_entry(item) } : payload[:history]
          end

          if payload[:scenes].is_a?(Array)
            @scenes = payload[:scenes].map { |h| SceneItem.from_h(h) }
          end

          sync_project_fields!
          self
        end

        # Одноразовый перенос старых проектов: раньше фон видового экрана был
        # включен по умолчанию и в таком виде сохранялся в сцены. Теперь фон по
        # умолчанию выключен: при первой загрузке проекта, сохраненного старой
        # версией, гасим унаследованный true. Явное включение фона пользователем
        # после миграции сохраняется на диске (маркер в секции project).
        def migrate_legacy_background_default!
          return if @project[:background_default_migrated] == true

          @scenes.each { |sc| sc.viewport_background = false }
          @project[:background_default_migrated] = true
        end

        # Одноразовый перенос старых проектов: раньше рамка кадра была глобальной
        # (pdf_settings[:show_aspect_overlay]), теперь она постраничная (SceneItem#frame_overlay).
        # При первой загрузке проекта, сохраненного старой версией, раздаём всем сценам
        # текущее глобальное значение. После миграции постраничные выборы сохраняются на диске.
        def migrate_frame_overlay_default!
          return if @project[:frame_overlay_default_migrated] == true

          inherited = @pdf_settings[:show_aspect_overlay] == true
          @scenes.each { |sc| sc.frame_overlay = inherited }
          @project[:frame_overlay_default_migrated] = true
        end

        # Одноразовый перенос старых проектов: раньше водяные знаки вида гасились
        # вместе с фоном (RenderingOptions["DisplayWatermarks"] сбрасывался при
        # viewport_background=false), теперь они управляются отдельным постраничным
        # флагом (SceneItem#viewport_watermarks). При первой загрузке проекта,
        # сохраненного старой версией, раздаём сценам текущее значение фона —
        # внешнее поведение не меняется.
        def migrate_watermark_default!
          return if @project[:watermark_default_migrated] == true

          @scenes.each { |sc| sc.viewport_watermarks = sc.viewport_background != false }
          @project[:watermark_default_migrated] = true
        end

        # Синхронизирует список сцен с активной моделью SketchUp, сохраняя настроенные параметры
        # @param model [Sketchup::Model] модель SketchUp
        # @return [void]
        def sync_with_model_scenes(model)
          return unless model && model.respond_to?(:pages)

          # Словарь существующих страниц SketchUp по имени
          pages_by_name = {}
          model.pages.each do |page|
            p_name = page.respond_to?(:name) ? page.name : page.to_s
            pages_by_name[p_name] = page
          end

          new_scenes = []
          seen_pages = {}

          # 1. Сначала обрабатываем существующие @scenes в их текущем (пользовательском) порядке
          @scenes.each do |item|
            page = nil
            if item.scene_ref && (item.scene_ref.is_a?(Sketchup::Page) rescue false)
              page = item.scene_ref if pages_by_name.values.include?(item.scene_ref)
            end
            page ||= pages_by_name[item.original_name] if item.respond_to?(:original_name) && item.original_name
            page ||= pages_by_name[item.name]

            if page
              item.scene_ref = page
              seen_pages[page] = true
              curr_page_name = page.respond_to?(:name) ? page.name : page.to_s

              # Если название в item пустое или совпадает с оригинальным, актуализируем из сцены
              new_name = item.name.to_s.strip
              if new_name.empty?
                item.name = curr_page_name
                item.original_name = curr_page_name if item.respond_to?(:original_name=)
              elsif !new_name.empty? && new_name != curr_page_name
                if page.respond_to?(:name=)
                  begin
                    page.name = new_name
                    item.original_name = new_name if item.respond_to?(:original_name=)
                  rescue StandardError
                    # Игнорируем ограничения при совпадении имен
                  end
                end
              end

              # Примечание / Описание берем из сцены SketchUp
              curr_page_desc = page.respond_to?(:description) ? page.description.to_s.strip : ""
              if !curr_page_desc.empty? && item.description.to_s.strip.empty?
                item.description = curr_page_desc
              elsif page.respond_to?(:description=) && !item.description.to_s.empty? && page.description.to_s != item.description.to_s
                begin
                  page.description = item.description.to_s
                rescue StandardError; end
              elsif !curr_page_desc.empty?
                item.description = curr_page_desc
              end

              new_scenes << item
            end
          end

          # 2. Добавляем любые новые страницы SketchUp, которых еще не было в @scenes
          model.pages.each do |page|
            next if seen_pages[page]

            p_name = page.respond_to?(:name) ? page.name : page.to_s
            included = page.respond_to?(:include_in_animation?) ? page.include_in_animation? : true
            item = Model::SceneItem.new(
              name:          p_name,
              original_name: p_name,
              scene_ref:     page,
              description:   page.respond_to?(:description) ? page.description.to_s : "",
              order:         new_scenes.size,
              enabled:       included
            )
            new_scenes << item
            seen_pages[page] = true
          end

          # 3. Синхронизируем порядковые номера (order)
          new_scenes.each_with_index do |sc, idx|
            sc.order = idx
          end

          @scenes = new_scenes
        end

        # Рекурсивно преобразует строковые ключи вложенных хэшей и массивов в Symbol
        # @param obj [Object] исходный объект (Hash, Array или примитив)
        # @return [Object] объект с символьными ключами
        def self.deep_symbolize_keys(obj)
          case obj
          when Hash
            obj.each_with_object({}) do |(k, v), result|
              result[k.to_s.to_sym] = deep_symbolize_keys(v)
            end
          when Array
            obj.map { |e| deep_symbolize_keys(e) }
          else
            obj
          end
        end

        # Рекурсивно преобразует ключи вложенных хэшей в строки
        # @param obj [Object] исходный объект
        # @return [Object] объект со строковыми ключами
        def self.deep_stringify_keys(obj)
          case obj
          when Hash
            obj.each_with_object({}) do |(k, v), result|
              result[k.to_s] = deep_stringify_keys(v)
            end
          when Array
            obj.map { |e| deep_stringify_keys(e) }
          else
            obj
          end
        end

        # Читает историю правок из файла edit_history.yaml по текущему артикулу
        # @param file_path [String] путь к файлу edit_history.yaml
        # @param articul [String, nil] артикул проекта (если nil, берется из @project_info[:articul])
        # @return [Boolean] true, если история успешно прочитана
        def load_from_edit_history(file_path, articul = nil)
          return false unless File.exist?(file_path)

          begin
            content = File.read(file_path, encoding: "utf-8")
            raw_data = begin
                         YAML.safe_load(content, permitted_classes: [Date, Time])
                       rescue ArgumentError
                         YAML.load(content)
                       end
            return false unless raw_data.is_a?(Hash)

            art_key = (articul || @project_info[:articul]).to_s.strip
            entries = nil

            # 1. Поиск по точному ключу
            if !art_key.empty?
              entries = raw_data[art_key] || raw_data[art_key.to_sym]
            end

            # 2. Если в файле всего одна запись и ключ не совпал точно
            if entries.nil? && raw_data.keys.size == 1
              entries = raw_data.values.first
            end

            # 3. Нечеткий поиск (без учета регистра и спецсимволов)
            if entries.nil? && !art_key.empty?
              clean_target = art_key.gsub(/[^A-Za-z0-9]/, "").downcase
              matching_key = raw_data.keys.find do |k|
                k.to_s.gsub(/[^A-Za-z0-9]/, "").downcase == clean_target
              end
              entries = raw_data[matching_key] if matching_key
            end

            return false unless entries.is_a?(Array)

            @history = entries.map do |item|
              d = item["date"] || item[:date] || ""
              d_str = if d.is_a?(Time)
                        d.strftime("%Y-%m-%d %H:%M")
                      elsif d.is_a?(Date)
                        d.strftime("%Y-%m-%d")
                      else
                        d.to_s
                      end
              txt = (item["text"] || item[:text] || item["description"] || item[:description] || "").to_s
              n = normalize_history_entry({ "date" => d_str, "text" => txt })
              {
                date:        n[:date],
                text:        n[:text],
                description: n[:description],
                ver:         n[:ver],
                rev:         n[:rev]
              }
            end

            # Канонический порядок истории: новые сверху (хронологические файлы разворачиваются)
            normalize_history_order!

            # Синхронизируем последнюю правку с последним элементом истории
            if !@history.empty?
              latest_text = @history.first[:text].to_s
              if @project_info[:last_edit].to_s.strip.empty? || @project_info[:last_edit] != latest_text
                @project_info[:last_edit] = latest_text
                @project_info[:edit]      = latest_text
              end
            end

            true
          rescue StandardError => e
            warn "Ошибка загрузки edit_history.yaml (#{file_path}): #{e.message}"
            false
          end
        end

        # Нормализация списка параметров шаблона: приведение полей к допустимым
        # значениям (строки, числа, булевы флаги). Размещение задается парой
        # align (left/center/right) × valign (top/bottom) — свободных координат нет.
        # Запись с group: true — блок объединения параметров: дети выводятся одной
        # строкой с разделителем « | » и стилем самого блока, поэтому у ребенка
        # хранятся только id/source/label/show_label (зеркало normalizeTemplateParam).
        # Нормализует общие настройки стека параметров на уровне шаблона:
        # line_gap — «размер между строками» (мм, 0..50, по умолчанию 2.5),
        # line_enabled — тонкая линия-разделитель между параметрами и блоками.
        # Ключи приводит к символам, значения — к числу и булеву флагу.
        # @param page [Hash] конфиг одного шаблона (custom_layouts[key])
        # @return [Hash] тот же хэш с нормализованными полями
        def normalize_line_settings!(page)
          return page unless page.is_a?(Hash)

          gap = page[:line_gap] || page["line_gap"] || 2.5
          page.delete("line_gap")
          page[:line_gap] = gap.to_f.clamp(0.0, 50.0)

          raw = page.key?(:line_enabled) ? page[:line_enabled] : page["line_enabled"]
          page.delete("line_enabled")
          page[:line_enabled] = !raw.nil? && !(raw == false || raw.to_s.strip.downcase == "false" || raw.to_s.strip == "0")
          page
        end

        # @param raw [Array] сырой список параметров (из payload диалога или YAML)
        # @return [Array<Hash>]
        def normalize_template_params(raw)
          return [] unless raw.is_a?(Array)

          bool_val = lambda do |v, def_val|
            v.nil? ? def_val : !(v == false || v.to_s == "false" || v == 0 || v.to_s == "0")
          end

          raw.filter_map do |p|
            next unless p.is_a?(Hash)

            src = (p[:source] || p["source"]).to_s.strip
            is_group = p[:group] == true || p["group"] == true || p[:group].to_s == "true"
            next if !is_group && src.empty?

            align_raw = (p[:align] || p["align"] || "left").to_s.strip.downcase
            valign_raw = (p[:valign] || p["valign"] || "top").to_s.strip.downcase

            base = {
              id:         (p[:id] || p["id"]).to_s.strip,
              label:      (p[:label] || p["label"]).to_s.strip,
              show_label: bool_val.call(p.key?(:show_label) ? p[:show_label] : p["show_label"], !is_group),
              align:      %w[left center right].include?(align_raw) ? align_raw : "left",
              valign:     %w[top bottom].include?(valign_raw) ? valign_raw : "top",
              font_family: (p[:font_family] || p["font_family"]).to_s.strip,
              font_size:  (p[:font_size] || p["font_size"] || 10.0).to_f.clamp(4.0, 72.0),
              color:      (p[:color] || p["color"] || "#0F172A").to_s.strip,
              visible:    bool_val.call(p.key?(:visible) ? p[:visible] : p["visible"], true)
            }

            if is_group
              children = Array(p[:params] || p["params"]).filter_map do |c|
                next unless c.is_a?(Hash)

                child_src = (c[:source] || c["source"]).to_s.strip
                next if child_src.empty?

                {
                  id:         (c[:id] || c["id"]).to_s.strip,
                  source:     child_src,
                  label:      (c[:label] || c["label"]).to_s.strip,
                  show_label: bool_val.call(c.key?(:show_label) ? c[:show_label] : c["show_label"], false)
                }
              end
              base.merge!(group: true, params: children)
            else
              base.merge!(source: src)
            end
          end
        end

        # Загружает макеты страниц из отдельного YAML файла (layout.yaml / layout_config.yaml)
        # @param file_path [String] путь к файлу макета
        # @return [Boolean] true, если макеты успешно прочитаны
        def load_from_layout_yaml(file_path)
          return false unless file_path && File.exist?(file_path)

          begin
            content = File.read(file_path, encoding: "utf-8")
            raw = begin
                    YAML.safe_load(content, permitted_classes: [Date, Time, Symbol])
                  rescue ArgumentError
                    YAML.load(content)
                  end
            return false unless raw.is_a?(Hash)

            data = self.class.deep_symbolize_keys(raw)
            layouts = data[:layout] || data[:custom_layouts] || data[:layouts]

            if layouts.nil? && (data.key?(:cover) || data.key?(:description) || data.key?(:explain) || data.key?(:general) || data.key?(:visual))
              layouts = data
            end

            return false unless layouts.is_a?(Hash)

            # layout.yaml — единственный источник списка шаблонов: начинаем с
            # пустого списка, иначе удалённый пользователем готовый шаблон
            # воскресал бы из default_custom_layouts при каждом запуске.
            # Дефолтный сид остаётся только для случая, когда файла макетов
            # нет вовсе (задаётся в default_pdf_settings → default_custom_layouts).
            @pdf_settings[:custom_layouts] = {}
            layouts.each do |page_key, blocks|
              next unless blocks.is_a?(Hash)

              # Чистый лист: страница читается, только если в ней есть блоки новой
              # модели (image_4_3 / params); записи старой (header/slot_N/footer)
              # игнорируются целиком.
              has_new = blocks.key?(:image_4_3) || blocks.key?("image_4_3") ||
                        blocks.key?(:params) || blocks.key?("params")
              next unless has_new

              page = @pdf_settings[:custom_layouts][page_key] ||= {}

              blocks.each do |slot_id, slot_cfg|
                if slot_id.to_s == "image_4_3" && slot_cfg.is_a?(Hash)
                  page[:image_4_3] ||= {}
                  page[:image_4_3].merge!(slot_cfg)
                  page[:image_4_3][:aspect_ratio] ||= "4:3"
                  page[:image_4_3][:scale_pct] = (page[:image_4_3][:scale_pct] || 100).to_i
                  raw_bg = page[:image_4_3][:show_background]
                  page[:image_4_3][:show_background] = !(raw_bg == false || raw_bg.to_s == "false" || raw_bg == 0 || raw_bg.to_s == "0")
                elsif slot_id.to_s == "params" && slot_cfg.is_a?(Array)
                  page[:params] = normalize_template_params(slot_cfg)
                elsif slot_id.to_s == "line_gap" || slot_id.to_s == "line_enabled"
                  page[slot_id.to_sym] = slot_cfg
                elsif TEMPLATE_META_KEYS.include?(slot_id.to_s)
                  # Метаданные шаблона (имя, описание, база) должны переживать
                  # перезапуск — раньше они отбрасывались и имя слетало на
                  # «Шаблон (custom_xxx)» после перезагрузки SketchUp
                  page[slot_id.to_sym] = slot_cfg.to_s
                end
              end
              page[:params] ||= []
              normalize_line_settings!(page)
            end
            true
          rescue StandardError => e
            warn "Ошибка загрузки макета (#{file_path}): #{e.message}"
            false
          end
        end

        # Сохраняет текущую конфигурацию шаблонов страниц в отдельный YAML файл
        # @param file_path [String] путь к файлу layout.yaml
        # @return [Boolean] true в случае успешного сохранения
        def save_to_layout_yaml(file_path)
          return false unless file_path

          FileUtils.mkdir_p(File.dirname(file_path))
          layouts_data = @pdf_settings[:custom_layouts] || default_custom_layouts
          if layouts_data.is_a?(Hash)
            layouts_data.each_value do |page_blocks|
              next unless page_blocks.is_a?(Hash)

              params = page_blocks[:params] || page_blocks["params"]
              page_blocks[:params] = normalize_template_params(params) if params.is_a?(Array)
              normalize_line_settings!(page_blocks)
            end
          end

          # Определяем предпочитаемый корневой ключ (layout или custom_layouts)
          root_key = "layout"
          if File.exist?(file_path)
            begin
              content = File.read(file_path, encoding: "utf-8")
              raw = YAML.safe_load(content) rescue nil
              if raw.is_a?(Hash) && raw.key?("custom_layouts")
                root_key = "custom_layouts"
              end
            rescue StandardError
              # Ignore
            end
          end

          data = {
            root_key => self.class.deep_stringify_keys(layouts_data)
          }

          File.open(file_path, "w:utf-8") do |f|
            f.write data.to_yaml
          end
          true
        end

        # Загружает данные проекта из файла YAML (поддерживает структуру project_config.yaml,
        # одиночные хэши и потоковый формат)
        # @param file_path [String] путь к YAML файлу
        # @param include_settings [Boolean] читать ли секцию pdf_settings (глобальные настройки PDF)
        # @return [Boolean] true в случае успешной загрузки
        def load_from_yaml(file_path, include_settings: true)
          return false unless File.exist?(file_path)

          begin
            content = File.read(file_path, encoding: "utf-8")
            raw_docs = begin
                         YAML.load_stream(content, symbolize_names: true)
                       rescue ArgumentError
                         YAML.load_stream(content)
                       end
            return false if raw_docs.nil? || raw_docs.empty?

            docs = raw_docs.map { |d| self.class.deep_symbolize_keys(d) }

            # Вариант 1: Структурированный одиночный хэш
            if docs.size == 1 && docs[0].is_a?(Hash)
              root = docs[0]

              if root.key?(:api_targets) && root[:api_targets].is_a?(Array)
                @api_targets = root[:api_targets]
              end

              if root.key?(:directories)
                @directories = root[:directories]
                normalize_directories!
              end

              # Проверяем, новая ли это модульная структура (есть ли customer или workflow)
              has_modular = root.key?(:customer) || root.key?(:workflow)

              if has_modular
                @project.merge!(root[:project]) if root[:project].is_a?(Hash)
                # Флага нет в файле: применяем правило «создан однажды => заблокирован»
                if root[:project].is_a?(Hash) && !root[:project].key?(:articul_locked)
                  @project[:articul_locked] = !@project[:articul].to_s.strip.empty?
                end
                @customer.merge!(root[:customer]) if root[:customer].is_a?(Hash)
                if root[:workflow].is_a?(Hash)
                  @workflow.merge!(root[:workflow])
                  unless root[:workflow].key?(:status)
                    @workflow[:status] = ""
                    @project_info.delete(:status) if @project_info
                  end
                  if root[:workflow][:stadia]
                    @workflow[:stadia] = normalize_stadia(root[:workflow][:stadia])
                  end
                end
                if root[:project].is_a?(Hash) && root[:project][:product_tags]
                  @project[:product_tags] = root[:project][:product_tags]
                end
              else
                # Старый плоский формат (все данные лежали внутри project или project_info)
                src = root[:project] || root[:project_info] || {}
                if src.is_a?(Hash)
                  @project[:articul]      = src[:articul].to_s
                  # Флага нет в файле: непустой артикул считается созданным однажды
                  @project[:articul_locked] =
                    if src.key?(:articul_locked)
                      src[:articul_locked]
                    else
                      !@project[:articul].empty?
                    end
                  @project[:product]      = (src[:product] || src[:name_product] || src[:furniture_name]).to_s
                  @project[:place]        = (src[:place] || src[:name_place] || src[:room_name]).to_s
                  @project[:adress]       = (src[:adress] || src[:address]).to_s
                  @project[:description]  = (src[:description] || src[:task_description]).to_s
                  @project[:commercial]   = src[:trade].to_s == "1" || src[:commercial] == true
                  @project[:name_company] = src[:company].to_s

                  @customer[:id]          = (src[:customer_id] || src[:id] || "").to_s
                  @customer[:name]        = (src[:customer] || src[:name_customer] || src[:name]).to_s
                  @customer[:phone]       = src[:phone].to_s
                  @customer[:email]       = src[:email].to_s
                  @customer[:company]     = src[:company].to_s

                  @workflow[:status]      = (src[:status] || "Предварительный").to_s
                  @workflow[:version]     = (src[:version] || "01").to_s
                  @workflow[:revision]    = (src[:revision] || "001").to_s
                  @workflow[:last_edit]   = (src[:last_edit] || src[:edit]).to_s

                  # Копируем специфичные поля описаний
                  [:notes, :materials, :appliances, :lighting, :task_dimensions, :task_wishes].each do |k|
                    @project_info[k] = src[k] if src[k]
                  end
                end
              end

              # Загрузка истории изменений из YAML (поддержка root[:history_edit], root[:workflow][:history_edit], root[:history])
              raw_hist = root[:history_edit] || (root[:workflow].is_a?(Hash) && root[:workflow][:history_edit]) || root[:history]
              if raw_hist.is_a?(Array) && !raw_hist.empty?
                @history = raw_hist.map { |item| normalize_history_entry(item) }
                @workflow[:history_edit] = @history.map { |h| [h[:data], h[:edit]] }
                sync_history_entries!
              end

              sync_project_fields!

              # Секция pdf_settings читается только при явном запросе (импорт полного
              # YAML): настройки PDF глобальные и хранятся в settings.yaml расширения
              if include_settings && root.key?(:pdf_settings) && root[:pdf_settings].is_a?(Hash)
                @pdf_settings.merge!(root[:pdf_settings])
                legacy_font = Service::FontService.legacy_family_for(@pdf_settings[:font_family])
                @pdf_settings[:font_family] = legacy_font if legacy_font
              end

              if root[:scenes].is_a?(Array)
                @scenes = root[:scenes].map { |h| SceneItem.from_h(h) }
                migrate_legacy_background_default!
                migrate_frame_overlay_default!
                migrate_watermark_default!
              end

              # Проверяем, есть ли рядом файл edit_history.yaml
              dir = File.dirname(file_path)
              hist_file = File.join(dir, "edit_history.yaml")
              if File.exist?(hist_file)
                load_from_edit_history(hist_file, @project[:articul])
              end

              # Шаблоны страниц не читаются из папки проекта —
              # единый источник: layout.yaml внутри расширения

              return true
            end

            # Вариант 2: Многодокументный потоковый формат
            if docs[0].is_a?(Hash)
              if docs[0].key?(:project)
                @project.merge!(docs[0][:project])
                unless docs[0][:project].key?(:articul_locked)
                  @project[:articul_locked] = !@project[:articul].to_s.strip.empty?
                end
              else
                @project.merge!(docs[0])
                unless docs[0].key?(:articul_locked)
                  @project[:articul_locked] = !@project[:articul].to_s.strip.empty?
                end
              end
              sync_project_fields!
            end
            if docs[1].is_a?(Array)
              @scenes = docs[1].map { |h| SceneItem.from_h(h) }
              migrate_legacy_background_default!
              migrate_frame_overlay_default!
              migrate_watermark_default!
            end
            if docs[2].is_a?(Array)
              @history = docs[2].map do |item|
                txt = item[:text] || item[:description] || ""
                {
                  date:        item[:date].to_s,
                  text:        txt.to_s,
                  description: txt.to_s
                }
              end
              sync_history_entries!
            end
            if docs[3].is_a?(Hash)
              @pdf_settings.merge!(docs[3])
            end

            # Шаблоны страниц не читаются из папки проекта —
            # единый источник: layout.yaml внутри расширения

            true
          rescue StandardError => e
            warn "Ошибка загрузки YAML (#{file_path}): #{e.message}"
            false
          end
        end

        # Сохраняет данные проекта в YAML файл модульной структуры (project, customer, workflow, directories, scenes)
        # @param file_path [String] путь к сохраняемому YAML файлу
        # @param include_settings [Boolean] сохранять ли секцию pdf_settings
        # @return [Boolean] true в случае успешного сохранения
        def save_to_yaml(file_path, include_settings: true)
          FileUtils.mkdir_p(File.dirname(file_path))
          sync_project_fields!

          # 1. Секция project (Паспорт объекта)
          prj_out = {
            articul:      @project[:articul].to_s,
            articul_locked: @project[:articul_locked] == true,
            background_default_migrated: @project[:background_default_migrated] == true,
            watermark_default_migrated: @project[:watermark_default_migrated] == true,
            product_tags: @project[:product_tags] || [],
            place:        @project[:place].to_s,
            adress:       @project[:adress].to_s,
            description:  @project[:description].to_s,
            commercial:   @project[:commercial] == true
          }
          if !@project[:product].to_s.empty? && (@project[:product_tags].nil? || @project[:product_tags].empty?)
            prj_out[:product_tags] = @project[:product].to_s.split(",").map(&:strip).reject(&:empty?)
          end
          prj_out[:product] = @project[:product].to_s unless @project[:product].to_s.empty?
          if !@project[:name_company].to_s.strip.empty?
            prj_out[:name_company] = @project[:name_company].to_s.strip
          end

          # 2. Секция customer (Карточка клиента)
          c_id = @customer[:id].to_s.strip
          c_id = self.class.generate_customer_id if c_id.empty? && !@customer[:name].to_s.strip.empty?
          @customer[:id] = c_id

          cust_out = {
            id:    c_id,
            name:  @customer[:name].to_s,
            phone: @customer[:phone].to_s,
            email: @customer[:email].to_s
          }
          cust_out[:company] = @customer[:company].to_s unless @customer[:company].to_s.strip.empty?

          # 3. Секция workflow (Процесс и версионность)
          # history_edit пишется на диск в хронологическом порядке (старые сверху);
          # в памяти канонический порядок — новые сверху (см. normalize_history_order!)
          wf_out = {
            author:         @workflow[:author].to_s,
            price:          @workflow[:price].to_s.empty? ? "" : @workflow[:price],
            start_date:     @workflow[:start_date].to_s,
            end_date:       @workflow[:end_date].to_s,
            total_duration: @workflow[:total_duration].to_s,
            version:        @workflow[:version].to_s,
            revision:       @workflow[:revision].to_s,
            stadia:         normalize_stadia(@workflow[:stadia]),
            history_edit:   (@workflow[:history_edit] || []).reverse
          }
          wf_out[:status] = @workflow[:status].to_s unless @workflow[:status].to_s.empty?

          # 4. Секция history_edit (Корневая, как в project.yaml, хронологический порядок)
          hist_out = (@history || []).reverse.map do |h|
            next unless h.is_a?(Hash)
            n = normalize_history_entry(h)
            entry = {
              "data" => n[:data],
              "edit" => n[:text]
            }
            entry["pdf_link"] = n[:pdf_link] unless n[:pdf_link].empty?
            entry["ver"]      = n[:ver] unless n[:ver].empty?
            entry["rev"]      = n[:rev] unless n[:rev].empty?
            entry
          end.compact

          # 5. Секция directories (Массив объектов)
          dirs_out = normalize_directories_to_array(@directories).map do |d|
            entry = {
              "path"        => d[:path].to_s,
              "title"       => d[:title].to_s,
              "description" => d[:description].to_s
            }
            entry["display"] = d[:display].to_s if d[:display]
            entry["thumb_size"] = d[:thumb_size].to_s if d[:thumb_size]
            entry
          end

          # 6. Сборка итогового документа в чистом строгом порядке, соответствующем project.yaml
          data = {
            project:      prj_out,
            customer:     cust_out,
            workflow:     wf_out,
            history_edit: hist_out,
            directories:  dirs_out,
            scenes:       @scenes.map(&:to_h)
          }
          if @api_targets.is_a?(Array)
            data[:api_targets] = @api_targets.map(&:to_s).map(&:strip).reject(&:empty?)
          end
          if include_settings && @pdf_settings && !@pdf_settings.empty?
            data[:pdf_settings] = @pdf_settings
          end

          File.open(file_path, "w:utf-8") do |f|
            f.write self.class.deep_stringify_keys(data).to_yaml
          end

          true
        end

        # Преобразует все данные проекта в стандартный Ruby Hash
        # @return [Hash] хэш со всеми полями проекта, настройками, сценами и историей
        def to_h
          sync_project_fields!

          hist_out = (@history || []).map do |h|
            next unless h.is_a?(Hash)
            n = normalize_history_entry(h)
            {
              data:     n[:data],
              date:     n[:data],
              edit:     n[:text],
              text:     n[:text],
              pdf_link: n[:pdf_link],
              ver:      n[:ver],
              rev:      n[:rev]
            }
          end.compact

          {
            project:      @project,
            customer:     @customer,
            workflow:     @workflow,
            history_edit: hist_out,
            directories:  @directories,
            scenes:       @scenes.map(&:to_h),
            project_info: @project_info, # Для полной совместимости с существующими генераторами и тестами
            pdf_settings: @pdf_settings,
            api_targets:  @api_targets,
            history:      @history
          }
        end
      end
    end
  end
end
