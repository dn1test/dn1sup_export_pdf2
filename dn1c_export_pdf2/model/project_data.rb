# frozen_string_literal: true

require "yaml"
require "json"
require "time"
require "date"
require "fileutils"
require_relative "scene_item"

module DN1Code
  module ExportPdf2
    module Model
      # Модель данных проекта: хранит информацию о проекте, сценах, истории ревизий и параметрах PDF.
      # Поддерживает двухуровневую синхронизацию: первичный источник — YAML файлы рядом с SKP
      # (project_config.yaml + edit_history.yaml), вторичный источник — библиотека модели
      # (Attribute Dictionaries SketchUp).
      class ProjectData
        # Имя словаря атрибутов SketchUp для хранения данных
        ATTR_DICT = "DN1C_ExportPDF"

        # Пути к глобальным настройкам программы (хранятся внутри плагина)
        PLUGIN_CONFIG_DIR     = File.expand_path("../config", __dir__)
        PROGRAM_SETTINGS_FILE = File.join(PLUGIN_CONFIG_DIR, "settings.yaml")
        PROGRAM_LAYOUT_FILE   = File.join(PLUGIN_CONFIG_DIR, "layout.yaml")

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
        # @return [Hash] ход работы и жизненный цикл (author, price, start_date, end_date, total_duration, status, version, revision, history_edit)
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

        def custom_layouts=(val)
          @pdf_settings ||= {}
          @pdf_settings[:custom_layouts] = val
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
          @directories  = default_directories
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

        # Возвращает паспорт объекта по умолчанию
        # @return [Hash]
        def default_project
          {
            articul:      "",
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
            { name: "Правки проекта (история правок)", status: true },
            { name: "Выбраны материалы и фурнитура", status: true },
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
            status:         "Правки",
            version:        "01",
            revision:       "001",
            stadia:         default_stadia,
            history_edit:   []
          }
        end

        # Генерирует артикул проекта по шаблону: CF#ГГММДД_ЧЧММСС_НОМЕР или HF#...
        # @param commercial [Boolean] true для коммерческого (CF#), false для бытового (HF#)
        # @param suffix [String] суффикс/номер (по умолчанию "01")
        # @param time [Time] метка времени
        # @return [String]
        def self.generate_articul(commercial: false, suffix: "01", time: Time.now)
          prefix = commercial ? "CF#" : "HF#"
          ts = time.strftime("%y%m%d_%H%M%S")
          "#{prefix}#{ts}_#{suffix}"
        end

        # Генерирует автоматический номер/ID заказчика
        # @param time [Time] метка времени
        # @return [String]
        def self.generate_customer_id(time: Time.now)
          "CUST-#{time.strftime('%y%m%d%H%M')}"
        end

        # Возвращает структуру метаданных проекта по умолчанию для обратной совместимости
        # @return [Hash] хэш с параметрами проекта
        def default_project_info
          {
            articul:          "",
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

        # Возвращает список адресатов API по умолчанию
        # @return [Array<String>]
        def default_api_targets
          [
            "https://list.prodmd.top/api/projects?token=c2fc6e6bd272b4f9688656a7c4fcf6b9aa13ccdf7da077d53bf56e4afcf29a58",
            "http://localhost:3000/api/projects?token=b9fdaae8ca52a355df78d12f9bde54236200d366caf4af9350d8d934d83a9fba"
          ]
        end

        # Возвращает список каталогов проекта по умолчанию (формат массива хэшей)
        # @return [Array<Hash>]
        def default_directories
          [
            {
              path:        "!_замер_фото_задание",
              title:       "Замеры помещения",
              description: "Дополнительное описание",
              display:     "grid"
            },
            {
              path:        "!_инфо_заказчика",
              title:       "Инфо заказчика",
              description: "Дополнительное описание",
              display:     "grid"
            },
            {
              path:        "!_материалы_фурнитура",
              title:       "Материалы и фурнитура",
              description: "Дополнительное описание",
              display:     "grid"
            },
            {
              path:        "!_техника_подсветка",
              title:       "Техника, подсветка",
              description: "Дополнительное описание",
              display:     "list"
            }
          ]
        end

        # Возвращает конфигурацию визуальных блоков макета страниц по умолчанию (в процентах)
        # @return [Hash] хэш с координатами и свойствами блоков для каждого типа страницы
        def default_custom_layouts
          default_hdr_lines = ["furniture_name", "place_address", "customer_or_company", "scene_name", "scene_description"]
          default_hdr_rows  = { "furniture_name" => 1, "place_address" => 2, "customer_or_company" => 3, "scene_name" => 4, "scene_description" => 5 }
          default_hdr_sizes = { "furniture_name" => 11.0, "place_address" => 10.0, "customer_or_company" => 10.0, "scene_name" => 11.0, "scene_description" => 9.0 }
          default_hdr_colors = { "furniture_name" => "#005EB0", "place_address" => "#0F172A", "customer_or_company" => "#0F172A", "scene_name" => "#005EB0", "scene_description" => "#475569" }

          default_mid_lines = ["toc_pages", "spec_materials", "spec_appliances", "general_notes", "workflow_history", "workflow_stadia"]
          default_mid_aligns = {
            "toc_pages" => "left", "spec_materials" => "left", "spec_appliances" => "left", "general_notes" => "left",
            "workflow_history" => "left", "workflow_stadia" => "left", "workflow_revision" => "left",
            "workflow_version" => "left", "workflow_date" => "left", "articul" => "left"
          }
          default_mid_valigns = {
            "toc_pages" => "top", "spec_materials" => "top", "spec_appliances" => "top", "general_notes" => "top",
            "workflow_history" => "bottom", "workflow_stadia" => "bottom", "workflow_revision" => "bottom",
            "workflow_version" => "bottom", "workflow_date" => "bottom", "articul" => "bottom"
          }
          default_mid_sizes = {
            "toc_pages" => 8.0, "spec_materials" => 8.0, "spec_appliances" => 8.0, "general_notes" => 8.0,
            "workflow_history" => 8.0, "workflow_stadia" => 8.0, "workflow_revision" => 8.0,
            "workflow_version" => 8.0, "workflow_date" => 8.0, "articul" => 8.0
          }
          default_mid_colors = {
            "toc_pages" => "#334155", "spec_materials" => "#334155", "spec_appliances" => "#334155", "general_notes" => "#334155",
            "workflow_history" => "#334155", "workflow_stadia" => "#334155", "workflow_revision" => "#334155",
            "workflow_version" => "#334155", "workflow_date" => "#334155", "articul" => "#334155"
          }

          default_ftr_lines = ["footer_last_edit", "footer_ver_rev", "footer_articul", "footer_date", "footer_page_total"]
          default_ftr_aligns = {
            "footer_last_edit" => "left", "footer_ver_rev" => "center", "footer_articul" => "center",
            "footer_date" => "center", "footer_page_total" => "right"
          }

          {
            cover: {
              header:      { x: 25.0, y: 0.0, w: 50.0, h: 30.0, visible: true, content: "header_title", align: "center", valign: "top", font_size: 13.0, lines: default_hdr_lines.dup, line_rows: default_hdr_rows.dup, line_font_sizes: default_hdr_sizes.dup, line_colors: default_hdr_colors.dup, opacity: 0.95 },
              cover_title: { x: 10.0, y: 15.0, w: 80.0, h: 12.0, visible: true, align: "center" },
              image_4_3:   { x: 25.0, y: 12.0, w: 50.0, h: 82.0, visible: true, content: "render_viewport", aspect_ratio: "4:3", scale_pct: 100 },
              slot_1:    { x: 0.0, y: 0.0, w: 25.0, h: 58.0, visible: true, content: "info_lines", align: "left", valign: "top", font_size: 8.5, item_gap_mm: 2.0, item_gap: 2.0, lines: ["articul", "workflow_date", "workflow_version", "workflow_revision", "workflow_stadia"], line_aligns: default_mid_aligns.dup, line_valigns: default_mid_valigns.dup, line_font_sizes: default_mid_sizes.dup, line_colors: default_mid_colors.dup, opacity: 0.92 },
              slot_2:    { x: 0.0, y: 58.0, w: 25.0, h: 36.0, visible: false, content: "none", align: "left", valign: "bottom", font_size: 8.0, lines: [], opacity: 0.88 },
              slot_3:    { x: 75.0, y: 0.0, w: 25.0, h: 58.0, visible: false, content: "none", align: "right", valign: "top", font_size: 8.0, lines: [], opacity: 0.88 },
              slot_4:    { x: 75.0, y: 58.0, w: 25.0, h: 36.0, visible: false, content: "none", align: "right", valign: "bottom", font_size: 8.0, lines: [], opacity: 0.88 },
              footer:    { x: 0.0, y: 94.0, w: 100.0, h: 6.0, visible: true, content: "footer_info", align: "center", valign: "bottom", font_size: 8.5, lines: default_ftr_lines.dup, line_aligns: default_ftr_aligns.dup, opacity: 1.0 }
            },
            description: {
              header:    { x: 25.0, y: 0.0, w: 50.0, h: 30.0, visible: true, content: "header_title", align: "center", valign: "top", font_size: 11.0, lines: default_hdr_lines.dup, line_rows: default_hdr_rows.dup, line_font_sizes: default_hdr_sizes.dup, line_colors: default_hdr_colors.dup, opacity: 0.95 },
              image_4_3: { x: 25.0, y: 12.0, w: 50.0, h: 82.0, visible: true, content: "render_viewport", aspect_ratio: "4:3", scale_pct: 100 },
              slot_1:    { x: 0.0, y: 0.0, w: 25.0, h: 58.0, visible: true, content: "info_lines", align: "left", valign: "top", font_size: 8.5, item_gap_mm: 2.0, item_gap: 2.0, lines: ["spec_materials", "spec_appliances", "general_notes"], line_aligns: default_mid_aligns.dup, line_valigns: default_mid_valigns.dup, line_font_sizes: default_mid_sizes.dup, line_colors: default_mid_colors.dup, opacity: 0.92 },
              slot_2:    { x: 0.0, y: 58.0, w: 25.0, h: 36.0, visible: false, content: "none", align: "left", valign: "bottom", font_size: 8.0, lines: [], opacity: 0.88 },
              slot_3:    { x: 75.0, y: 0.0, w: 25.0, h: 58.0, visible: true, content: "info_lines", align: "right", valign: "top", font_size: 8.5, lines: ["spec_materials", "spec_appliances"], opacity: 0.88 },
              slot_4:    { x: 75.0, y: 58.0, w: 25.0, h: 36.0, visible: false, content: "none", align: "right", valign: "bottom", font_size: 8.0, lines: [], opacity: 0.88 },
              footer:    { x: 0.0, y: 94.0, w: 100.0, h: 6.0, visible: true, content: "footer_info", align: "center", valign: "bottom", font_size: 8.5, lines: default_ftr_lines.dup, line_aligns: default_ftr_aligns.dup, opacity: 1.0 }
            },
            explain: {
              header:    { x: 25.0, y: 0.0, w: 50.0, h: 30.0, visible: true, content: "header_title", align: "center", valign: "top", font_size: 11.0, lines: default_hdr_lines.dup, line_rows: default_hdr_rows.dup, line_font_sizes: default_hdr_sizes.dup, line_colors: default_hdr_colors.dup, opacity: 0.95 },
              image_4_3: { x: 25.0, y: 12.0, w: 50.0, h: 82.0, visible: true, content: "render_viewport", aspect_ratio: "4:3", scale_pct: 100 },
              slot_1:    { x: 0.0, y: 0.0, w: 25.0, h: 58.0, visible: true, content: "info_lines", align: "left", valign: "top", font_size: 8.0, item_gap_mm: 2.0, item_gap: 2.0, lines: ["toc_pages", "general_notes", "workflow_history", "workflow_stadia"], line_aligns: default_mid_aligns.dup, line_valigns: default_mid_valigns.dup, line_font_sizes: default_mid_sizes.dup, line_colors: default_mid_colors.dup, opacity: 0.92 },
              slot_2:    { x: 0.0, y: 58.0, w: 25.0, h: 36.0, visible: false, content: "none", align: "left", valign: "bottom", font_size: 8.0, lines: [], opacity: 0.88 },
              slot_3:    { x: 75.0, y: 0.0, w: 25.0, h: 58.0, visible: true, content: "info_lines", align: "right", valign: "top", font_size: 8.0, lines: ["toc_pages", "workflow_history"], opacity: 0.88 },
              slot_4:    { x: 75.0, y: 58.0, w: 25.0, h: 36.0, visible: false, content: "none", align: "right", valign: "bottom", font_size: 8.0, lines: [], opacity: 0.88 },
              footer:    { x: 0.0, y: 94.0, w: 100.0, h: 6.0, visible: true, content: "footer_info", align: "center", valign: "bottom", font_size: 8.5, lines: default_ftr_lines.dup, line_aligns: default_ftr_aligns.dup, opacity: 1.0 }
            },
            general: {
              header:    { x: 25.0, y: 0.0, w: 50.0, h: 30.0, visible: true, content: "header_title", align: "center", valign: "top", font_size: 11.0, lines: default_hdr_lines.dup, line_rows: default_hdr_rows.dup, line_font_sizes: default_hdr_sizes.dup, line_colors: default_hdr_colors.dup, opacity: 0.95 },
              image_4_3: { x: 25.0, y: 12.0, w: 50.0, h: 82.0, visible: true, content: "render_viewport", aspect_ratio: "4:3", scale_pct: 100 },
              slot_1:    { x: 0.0, y: 0.0, w: 25.0, h: 58.0, visible: false, content: "info_lines", align: "left", valign: "top", font_size: 8.0, item_gap_mm: 2.0, item_gap: 2.0, lines: ["general_notes", "workflow_stadia"], line_aligns: default_mid_aligns.dup, line_valigns: default_mid_valigns.dup, line_font_sizes: default_mid_sizes.dup, line_colors: default_mid_colors.dup, opacity: 0.88 },
              slot_2:    { x: 0.0, y: 58.0, w: 25.0, h: 36.0, visible: false, content: "none", align: "left", valign: "bottom", font_size: 8.0, lines: [], opacity: 0.88 },
              slot_3:    { x: 75.0, y: 0.0, w: 25.0, h: 58.0, visible: false, content: "none", align: "right", valign: "top", font_size: 8.0, lines: [], opacity: 0.88 },
              slot_4:    { x: 75.0, y: 58.0, w: 25.0, h: 36.0, visible: true, content: "info_lines", align: "right", valign: "bottom", font_size: 8.0, lines: ["workflow_history", "workflow_stadia"], opacity: 0.9 },
              footer:    { x: 0.0, y: 94.0, w: 100.0, h: 6.0, visible: true, content: "footer_info", align: "center", valign: "bottom", font_size: 8.5, lines: default_ftr_lines.dup, line_aligns: default_ftr_aligns.dup, opacity: 1.0 }
            },
            visual: {
              header:    { x: 25.0, y: 0.0, w: 50.0, h: 30.0, visible: true, content: "header_title", align: "center", valign: "top", font_size: 10.0, lines: default_hdr_lines.dup, line_rows: default_hdr_rows.dup, line_font_sizes: default_hdr_sizes.dup, line_colors: default_hdr_colors.dup, opacity: 0.95 },
              image_4_3: { x: 25.0, y: 12.0, w: 50.0, h: 82.0, visible: true, content: "render_viewport", aspect_ratio: "4:3", scale_pct: 100 },
              slot_1:    { x: 0.0, y: 0.0, w: 25.0, h: 58.0, visible: false, content: "info_lines", align: "left", valign: "top", font_size: 8.0, item_gap_mm: 2.0, item_gap: 2.0, lines: ["workflow_stadia"], line_aligns: default_mid_aligns.dup, line_valigns: default_mid_valigns.dup, line_font_sizes: default_mid_sizes.dup, line_colors: default_mid_colors.dup, opacity: 0.88 },
              slot_2:    { x: 0.0, y: 58.0, w: 25.0, h: 36.0, visible: false, content: "none", align: "left", valign: "bottom", font_size: 8.0, lines: [], opacity: 0.88 },
              slot_3:    { x: 75.0, y: 0.0, w: 25.0, h: 58.0, visible: false, content: "none", align: "right", valign: "top", font_size: 8.0, lines: [], opacity: 0.88 },
              slot_4:    { x: 75.0, y: 58.0, w: 25.0, h: 36.0, visible: false, content: "none", align: "right", valign: "bottom", font_size: 8.0, lines: [], opacity: 0.88 },
              footer:    { x: 0.0, y: 94.0, w: 100.0, h: 6.0, visible: true, content: "footer_info", align: "center", valign: "bottom", font_size: 8.5, lines: default_ftr_lines.dup, line_aligns: default_ftr_aligns.dup, opacity: 1.0 }
            }
          }

        end

        # Возвращает базовые настройки экспорта PDF по умолчанию
        # @return [Hash] хэш с параметрами PDF (размер листа, ориентация, цвета, штамп и т.д.)
        def default_pdf_settings
          {
            export_engine:      "prawn",
            layout_render_mode: "raster",
            save_layout_file:   true,
            page_size:          "A4",
            page_layout:        "landscape",
            margin:             15,
            margin_mm:          5,
            image_width:        2400,
            image_aspect_ratio: "page",
            custom_ratio_w:     16,
            custom_ratio_h:     9,
            show_aspect_overlay: false,
            overlay_border_color:   "#0EA5E9",
            overlay_border_opacity: 100,
            overlay_mask_color:     "#0F172A",
            overlay_mask_opacity:   55,
            scale_factor:       2.0,
            antialias:          true,
            stamp_type:         "draft",
            stamp_custom:       "НЕ УТВЕРЖДЕН",
            auto_open_pdf:      true,
            save_skp_backup:    true,
            primary_color:      "005EB0",
            secondary_color:    "64748B",
            stamp_color:        "D32F2F",
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

        # Синхронизирует кортежи @workflow[:history_edit] и структуру @history
        def sync_history_entries!
          @workflow[:history_edit] ||= []
          @history                 ||= []

          if @workflow[:history_edit].empty? && !@history.empty?
            @workflow[:history_edit] = @history.map do |h|
              d = (h[:data] || h[:date] || h["data"] || h["date"] || "").to_s
              t = (h[:edit] || h[:text] || h["edit"] || h["text"] || h[:description] || h["description"] || "").to_s
              [d, t]
            end
          elsif !@workflow[:history_edit].empty? && @history.empty?
            @history = @workflow[:history_edit].map do |item|
              if item.is_a?(Array)
                d = item[0].to_s
                t = item[1].to_s
                lnk = item[2].to_s
              elsif item.is_a?(Hash)
                d = (item[:data] || item[:date] || item["data"] || item["date"]).to_s
                t = (item[:edit] || item[:text] || item["edit"] || item["text"] || item[:description] || item["description"]).to_s
                lnk = (item[:pdf_link] || item["pdf_link"]).to_s
              else
                d = ""
                t = item.to_s
                lnk = ""
              end
              { date: d, text: t, description: t, data: d, edit: t, pdf_link: lnk }
            end
          else
            @history = @history.map do |item|
              if item.is_a?(Array)
                d = item[0].to_s
                t = item[1].to_s
                lnk = item[2].to_s
              elsif item.is_a?(Hash)
                d = (item[:data] || item[:date] || item["data"] || item["date"]).to_s
                t = (item[:edit] || item[:text] || item["edit"] || item["text"] || item[:description] || item["description"]).to_s
                lnk = (item[:pdf_link] || item["pdf_link"]).to_s
              else
                d = ""
                t = item.to_s
                lnk = ""
              end
              { date: d, text: t, description: t, data: d, edit: t, pdf_link: lnk }
            end
          end
        end

        # Нормализует каталоги directories
        def normalize_directories!
          @directories = default_directories if @directories.nil? || (@directories.is_a?(Array) && @directories.empty?)
        end

        # Преобразует каталоги в чистый массив хэшей для сохранения в YAML
        # @param dirs [Object]
        # @return [Array<Hash>]
        def normalize_directories_to_array(dirs)
          return default_directories if dirs.nil?
          if dirs.is_a?(Hash)
            dirs.map do |k, v|
              next unless v.is_a?(Hash)
              {
                path:        (v[:path] || v["path"] || "").to_s,
                title:       (v[:title] || v["title"] || "").to_s,
                description: (v[:description] || v["description"] || "").to_s,
                display:     (v[:display] || v["display"] || "grid").to_s
              }
            end.compact
          elsif dirs.is_a?(Array)
            dirs.map do |d|
              next unless d.is_a?(Hash)
              {
                path:        (d[:path] || d["path"] || "").to_s,
                title:       (d[:title] || d["title"] || "").to_s,
                description: (d[:description] || d["description"] || "").to_s,
                display:     (d[:display] || d["display"] || "grid").to_s
              }
            end.compact
          else
            default_directories
          end
        end

        # Очищает строку имени от запрещенных символов файловой системы
        # @param name [String, Object] исходное имя файла
        # @return [String] безопасное для файловой системы имя
        def self.sanitize_filename(name)
          name.to_s.gsub(/[\\\/:\*\?"<>\|]/, "_").strip
        end

        # Определяет имя YAML файла на основе артикула или имени файла модели
        # @param project_info [Hash] метаданные проекта
        # @param model [Sketchup::Model, nil] экземпляр модели SketchUp
        # @return [String] имя файла YAML (например, "PRJ-100.yaml" или "ModelName.yaml")
        def self.resolve_yaml_filename(project_info, model = nil)
          articul = project_info && project_info[:articul] ? project_info[:articul].to_s.strip : ""
          if !articul.empty?
            clean_name = sanitize_filename(articul)
            return "#{clean_name}.yaml" unless clean_name.empty?
          end

          if model && model.respond_to?(:path) && !model.path.to_s.empty?
            clean_path = model.path.to_s.tr("\\", "/")
            base_name = File.basename(clean_path, ".*")
            clean_base = sanitize_filename(base_name)
            return "#{clean_base}.yaml" unless clean_base.empty?
          end

          "project_config.yaml"
        end

        # Ищет существующий YAML файл конфигурации рядом с файлом модели SketchUp
        # @param model [Sketchup::Model] модель SketchUp
        # @return [String, nil] абсолютный путь к существующему YAML файлу или nil
        def self.find_yaml_path_for_model(model)
          return nil unless model && model.respond_to?(:path) && !model.path.to_s.empty?

          clean_path = model.path.to_s.tr("\\", "/")
          dir = File.dirname(clean_path)
          base_name = File.basename(clean_path, ".*")

          # 1. Проверяем артикул из атрибутов модели
          raw_info = model.get_attribute(ATTR_DICT, "project_info", nil) rescue nil
          if raw_info
            begin
              info = JSON.parse(raw_info, symbolize_names: true)
              articul = info[:articul].to_s.strip
              if !articul.empty?
                art_yaml = File.join(dir, "#{sanitize_filename(articul)}.yaml")
                return art_yaml if File.exist?(art_yaml)

                art_yml = File.join(dir, "#{sanitize_filename(articul)}.yml")
                return art_yml if File.exist?(art_yml)
              end
            rescue StandardError
              # Ignore
            end
          end

          # 2. Проверяем имя файла модели <model_basename>.yaml / .yml
          model_yaml = File.join(dir, "#{base_name}.yaml")
          return model_yaml if File.exist?(model_yaml)

          model_yml = File.join(dir, "#{base_name}.yml")
          return model_yml if File.exist?(model_yml)

          # 3. Проверяем project_config.yaml / .yml
          cfg_yaml = File.join(dir, "project_config.yaml")
          return cfg_yaml if File.exist?(cfg_yaml)

          cfg_yml = File.join(dir, "project_config.yml")
          return cfg_yml if File.exist?(cfg_yml)

          # 4. Сканируем папку модели на наличие YAML файла конфигурации проекта (исключая edit_history и layout)
          layout_names = ["layout.yaml", "layout.yml", "layout_config.yaml", "layout_config.yml", "layouts.yaml", "layouts.yml"]
          all_yamls = Dir.glob(File.join(dir, "*.{yaml,yml}")).reject do |f|
            bn = File.basename(f)
            bn.start_with?("~", ".") || bn == "edit_history.yaml" || bn == "edit_history.yml" || layout_names.include?(bn)
          end

          if all_yamls.size == 1
            return all_yamls.first
          elsif all_yamls.size > 1
            matching = all_yamls.find do |f|
              txt = File.read(f, 600, encoding: "utf-8") rescue ""
              txt.include?("project:") || txt.include?("project_info:") || txt.include?("api_targets:")
            end
            return matching if matching
          end

          nil
        end

        # Ищет путь к файлу edit_history.yaml рядом с файлом модели
        # @param model [Sketchup::Model] модель SketchUp
        # @return [String, nil]
        def self.find_edit_history_path_for_model(model)
          return nil unless model && model.respond_to?(:path) && !model.path.to_s.empty?

          clean_path = model.path.to_s.tr("\\", "/")
          dir = File.dirname(clean_path)
          hist_yaml = File.join(dir, "edit_history.yaml")
          return hist_yaml if File.exist?(hist_yaml)

          hist_yml = File.join(dir, "edit_history.yml")
          return hist_yml if File.exist?(hist_yml)

          hist_yaml
        end

        # Находит путь к файлу макетов страниц (layout.yaml / layout_config.yaml)
        # @param dir [String] путь к директории
        # @return [String, nil] путь к файлу layout.yaml
        def self.find_layout_path(dir)
          return nil unless dir && Dir.exist?(dir)

          candidates = [
            "layout.yaml", "layout.yml",
            "layout_config.yaml", "layout_config.yml",
            "layouts.yaml", "layouts.yml"
          ]

          candidates.each do |fn|
            path = File.join(dir, fn)
            return path if File.exist?(path)
          end

          File.join(dir, "layout.yaml")
        end

        # Возвращает путь к файлу макетов страниц рядом с файлом модели SketchUp
        # @param model [Sketchup::Model] модель SketchUp
        # @return [String, nil] путь к файлу layout.yaml или nil
        def self.find_layout_path_for_model(model)
          return nil unless model && model.respond_to?(:path) && !model.path.to_s.empty?

          clean_path = model.path.to_s.tr("\\", "/")
          dir = File.dirname(clean_path)
          find_layout_path(dir)
        end

        # Возвращает целевое имя YAML файла для текущего экземпляра проекта
        # @param model [Sketchup::Model, nil] модель SketchUp
        # @return [String] имя файла YAML
        def yaml_filename(model = nil)
          self.class.resolve_yaml_filename(@project_info, model)
        end

        # Возвращает полный путь к целевому YAML файлу рядом с файлом модели SketchUp
        # @param model [Sketchup::Model] модель SketchUp
        # @return [String, nil] путь к файлу YAML или nil, если модель не сохранена
        def yaml_path_for_model(model)
          return nil unless model && model.respond_to?(:path) && !model.path.to_s.empty?

          clean_path = model.path.to_s.tr("\\", "/")
          dir = File.dirname(clean_path)
          File.join(dir, yaml_filename(model))
        end

        # Автоматическая загрузка данных:
        # 1. Загрузка глобальных настроек программы из плагина (settings.yaml + layout.yaml)
        # 2. ПЕРВИЧНО для данных проекта: YAML файлы рядом с файлом SketchUp (.skp) (project_config.yaml + edit_history.yaml)
        # 3. ВТОРИЧНО: Библиотека файла (атрибуты модели SketchUp)
        # @param model [Sketchup::Model, nil] модель SketchUp
        # @return [Symbol] источник загрузки (:yaml, :model или :default)
        def load_auto(model)
          # Всегда начинаем с загрузки актуальных глобальных настроек программы из плагина
          load_program_settings

          loaded_from = nil

          # 1. ПЕРВИЧНО: Ищем и загружаем YAML файл конфигурации проекта рядом с .skp
          yaml_file = self.class.find_yaml_path_for_model(model)
          if yaml_file && File.exist?(yaml_file)
            if load_from_yaml(yaml_file)
              loaded_from = :yaml
            end
          end

          # 2. ВТОРИЧНО: Если YAML не найден, читаем из библиотеки модели (атрибутов)
          if loaded_from.nil? && model
            if load_from_model(model)
              loaded_from = :model
            end
          end

          if model && model.respond_to?(:path) && !model.path.to_s.empty?
            clean_path = model.path.to_s.tr("\\", "/")
            dir = File.dirname(clean_path)

            # 3. Загружаем журнал изменений из edit_history.yaml, если он есть рядом
            hist_file = File.join(dir, "edit_history.yaml")
            if File.exist?(hist_file)
              load_from_edit_history(hist_file, @project_info[:articul])
            end

            # 4. Если в папке проекта есть явный локальный layout.yaml (проектное переопределение), применяем его
            local_layout = File.join(dir, "layout.yaml")
            if File.exist?(local_layout)
              load_from_layout_yaml(local_layout)
            end
          end

          # Синхронизируем прочитанные данные в библиотеку модели
          save_to_model(model) if model && loaded_from

          # Синхронизация списка сцен из модели
          sync_with_model_scenes(model) if model

          loaded_from || :default
        end

        # Автоматическое сохранение данных:
        # 1. Настройки программы — в файлы плагина (dn1c_export_pdf2/config/settings.yaml и layout.yaml)
        # 2. Данные проекта — в библиотеку модели (Attribute Dictionaries)
        # 3. Данные проекта — в YAML файл рядом с SKP (project_config.yaml / <артикул>.yaml)
        # 4. История правок — сохраняется внутри YAML файла проекта (workflow.history_edit)
        # @param model [Sketchup::Model] модель SketchUp
        # @return [Boolean] true в случае успешного сохранения
        def save_auto(model)
          return false unless model

          sync_project_fields!

          # 1. Находим текущий существующий YAML файл до обновления атрибутов модели
          old_yaml = self.class.find_yaml_path_for_model(model)

          # 2. Сохранение макетов страниц программы плагина
          save_to_layout_yaml(PROGRAM_LAYOUT_FILE)

          # Сохранение в локальный layout.yaml проекта, если он существует рядом с моделью
          if model.respond_to?(:path) && !model.path.to_s.empty?
            model_dir = File.dirname(model.path.to_s.tr("\\", "/"))
            local_layout = File.join(model_dir, "layout.yaml")
            save_to_layout_yaml(local_layout) if File.exist?(local_layout)
          end

          # 3. Сохранение в библиотеку модели (атрибуты)
          save_to_model(model)

          # 4. Сохранение данных проекта в YAML файл рядом с .skp
          if model.respond_to?(:path) && !model.path.to_s.empty?
            target_yaml = yaml_path_for_model(model)
            if target_yaml
              if save_to_yaml(target_yaml, include_settings: false)
                # Если имя YAML файла изменилось (например, при смене или очистке артикула),
                # удаляем старый YAML файл во избежание дубликатов
                if old_yaml && File.exist?(old_yaml)
                  old_norm = File.expand_path(old_yaml).tr("\\", "/").downcase
                  target_norm = File.expand_path(target_yaml).tr("\\", "/").downcase
                  if old_norm != target_norm
                    File.delete(old_yaml) rescue nil
                  end
                end
              end
            end
          end

          true
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

        # Читает данные проекта из словарей атрибутов модели SketchUp (библиотека модели)
        # @param model [Sketchup::Model] модель SketchUp
        # @return [Boolean] true, если данные были успешно прочитаны
        def load_from_model(model)
          return false unless model && model.respond_to?(:get_attribute)

          has_data = false

          # 1. Чтение модульных сущностей project, customer, workflow
          raw_prj = model.get_attribute(ATTR_DICT, "project", nil)
          if raw_prj
            begin
              parsed = JSON.parse(raw_prj, symbolize_names: true)
              @project.merge!(parsed) if parsed.is_a?(Hash)
              has_data = true
            rescue StandardError; end
          end

          raw_cust = model.get_attribute(ATTR_DICT, "customer", nil)
          if raw_cust
            begin
              parsed = JSON.parse(raw_cust, symbolize_names: true)
              @customer.merge!(parsed) if parsed.is_a?(Hash)
              has_data = true
            rescue StandardError; end
          end

          raw_wf = model.get_attribute(ATTR_DICT, "workflow", nil)
          if raw_wf
            begin
              parsed = JSON.parse(raw_wf, symbolize_names: true)
              @workflow.merge!(parsed) if parsed.is_a?(Hash)
              has_data = true
            rescue StandardError; end
          end

          # 2. Обратная совместимость с общим словарем project_info
          raw_info = model.get_attribute(ATTR_DICT, "project_info", nil)
          if raw_info
            begin
              parsed = JSON.parse(raw_info, symbolize_names: true)
              @project_info.merge!(parsed) if parsed.is_a?(Hash)
              has_data = true
            rescue StandardError; end
          end

          sync_project_fields!

          raw_settings = model.get_attribute(ATTR_DICT, "pdf_settings", nil)
          if raw_settings
            begin
              parsed = JSON.parse(raw_settings, symbolize_names: true)
              @pdf_settings.merge!(parsed)
              has_data = true
            rescue StandardError; end
          end

          raw_targets = model.get_attribute(ATTR_DICT, "api_targets", nil)
          if raw_targets
            begin
              parsed = JSON.parse(raw_targets)
              @api_targets = parsed if parsed.is_a?(Array)
              has_data = true
            rescue StandardError; end
          end

          raw_dirs = model.get_attribute(ATTR_DICT, "directories", nil)
          if raw_dirs
            begin
              parsed = JSON.parse(raw_dirs, symbolize_names: true)
              @directories = parsed if parsed.is_a?(Array) || parsed.is_a?(Hash)
              normalize_directories!
              has_data = true
            rescue StandardError; end
          end

          raw_history = model.get_attribute(ATTR_DICT, "history", nil)
          if raw_history
            begin
              parsed = JSON.parse(raw_history, symbolize_names: true)
              if parsed.is_a?(Array)
                @history = parsed.map do |item|
                  txt = item[:text] || item[:description] || ""
                  {
                    date:        item[:date].to_s,
                    text:        txt.to_s,
                    description: txt.to_s
                  }
                end
                sync_history_entries!
                has_data = true
              end
            rescue StandardError; end
          end

          raw_scenes = model.get_attribute(ATTR_DICT, "scenes", nil)
          if raw_scenes
            begin
              parsed = JSON.parse(raw_scenes, symbolize_names: true)
              if parsed.is_a?(Array) && !parsed.empty?
                @scenes = parsed.map { |h| SceneItem.from_h(h) }
                has_data = true
              end
            rescue StandardError; end
          end

          sync_with_model_scenes(model)
          has_data
        end

        # Сохраняет данные проекта в словарь атрибутов модели SketchUp (библиотека модели)
        # @param model [Sketchup::Model] модель SketchUp
        # @return [Boolean] true в случае успешного сохранения
        def save_to_model(model)
          return false unless model && model.respond_to?(:set_attribute)

          sync_project_fields!

          model.set_attribute(ATTR_DICT, "project", JSON.generate(@project))
          model.set_attribute(ATTR_DICT, "customer", JSON.generate(@customer))
          model.set_attribute(ATTR_DICT, "workflow", JSON.generate(@workflow))
          model.set_attribute(ATTR_DICT, "project_info", JSON.generate(@project_info))
          model.set_attribute(ATTR_DICT, "pdf_settings", JSON.generate(@pdf_settings))
          model.set_attribute(ATTR_DICT, "api_targets", JSON.generate(@api_targets))
          model.set_attribute(ATTR_DICT, "directories", JSON.generate(@directories))
          model.set_attribute(ATTR_DICT, "history", JSON.generate(@history))

          scenes_data = @scenes.map(&:to_h)
          model.set_attribute(ATTR_DICT, "scenes", JSON.generate(scenes_data))
          true
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
              {
                date:        d_str,
                text:        txt,
                description: txt
              }
            end

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

        # Сохраняет историю правок в файл edit_history.yaml под текущим артикулом проекта
        # @param file_path [String] путь к файлу edit_history.yaml
        # @param articul [String, nil] артикул проекта
        # @return [Boolean] true в случае успешного сохранения
        def save_to_edit_history(file_path, articul = nil)
          FileUtils.mkdir_p(File.dirname(file_path))

          existing_data = {}
          if File.exist?(file_path)
            begin
              content = File.read(file_path, encoding: "utf-8")
              parsed = begin
                         YAML.safe_load(content, permitted_classes: [Date, Time])
                       rescue ArgumentError
                         YAML.load(content)
                       end
              existing_data = parsed if parsed.is_a?(Hash)
            rescue StandardError
              existing_data = {}
            end
          end

          art_key = (articul || @project_info[:articul]).to_s.strip
          art_key = "DEFAULT" if art_key.empty?

          formatted_entries = @history.map do |item|
            d = item[:date] || item["date"] || ""
            d_str = if d.is_a?(Time)
                      d.strftime("%Y-%m-%d %H:%M")
                    elsif d.is_a?(Date)
                      d.strftime("%Y-%m-%d")
                    else
                      d.to_s
                    end
            txt = (item[:text] || item["text"] || item[:description] || item["description"] || "").to_s
            {
              "date" => d_str,
              "text" => txt
            }
          end

          existing_data[art_key] = formatted_entries

          File.open(file_path, "w:utf-8") do |f|
            f.write existing_data.to_yaml
          end
          true
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

            @pdf_settings[:custom_layouts] ||= default_custom_layouts
            layouts.each do |page_key, blocks|
              if blocks.is_a?(Hash)
                @pdf_settings[:custom_layouts][page_key] ||= {}
                blocks.each do |slot_id, slot_cfg|
                  if slot_cfg.is_a?(Hash)
                    @pdf_settings[:custom_layouts][page_key][slot_id] ||= {}
                    @pdf_settings[:custom_layouts][page_key][slot_id].merge!(slot_cfg)
                  else
                    @pdf_settings[:custom_layouts][page_key][slot_id] = slot_cfg
                  end
                  if slot_id.to_s == "header"
                    @pdf_settings[:custom_layouts][page_key][slot_id][:y] = 0.0
                    @pdf_settings[:custom_layouts][page_key][slot_id][:h] = 30.0
                    @pdf_settings[:custom_layouts][page_key][slot_id][:valign] ||= "top"
                    @pdf_settings[:custom_layouts][page_key][slot_id][:line_rows] ||= { "furniture_name" => 1, "place_address" => 2, "customer_or_company" => 3, "scene_name" => 4, "scene_description" => 5 }
                    @pdf_settings[:custom_layouts][page_key][slot_id][:line_font_sizes] ||= { "furniture_name" => 11.0, "place_address" => 10.0, "customer_or_company" => 10.0, "scene_name" => 11.0, "scene_description" => 9.0 }
                    @pdf_settings[:custom_layouts][page_key][slot_id][:line_colors] ||= { "furniture_name" => "#005EB0", "place_address" => "#0F172A", "customer_or_company" => "#0F172A", "scene_name" => "#005EB0", "scene_description" => "#475569" }
                  end
                  if slot_id.to_s == "image_4_3"
                    @pdf_settings[:custom_layouts][page_key][slot_id][:aspect_ratio] ||= "4:3"
                    @pdf_settings[:custom_layouts][page_key][slot_id][:scale_pct] = (@pdf_settings[:custom_layouts][page_key][slot_id][:scale_pct] || 100).to_i
                  end
                  if slot_id.to_s == "slot_1"
                    cfg = @pdf_settings[:custom_layouts][page_key][slot_id]
                    if cfg.is_a?(Hash)
                      c = (cfg[:content] || cfg["content"]).to_s
                      lines = cfg[:lines] || cfg["lines"]
                      if c.empty?
                        cfg[:content] = "info_lines"
                      end
                      if lines.nil?
                        def_tpl = default_custom_layouts[page_key.to_sym]
                        def_lines = def_tpl && def_tpl[:slot_1] && def_tpl[:slot_1][:lines]
                        cfg[:lines] = def_lines ? def_lines.dup : ["toc_pages", "spec_materials", "spec_appliances", "general_notes", "workflow_history", "workflow_stadia"]
                      end
                      cfg[:item_gap_mm] = (cfg[:item_gap_mm] || cfg["item_gap_mm"] || cfg[:item_gap] || cfg["item_gap"] || 2.0).to_f
                    end
                  end
                end
              end
            end
            true
          rescue StandardError => e
            warn "Ошибка загрузки макета (#{file_path}): #{e.message}"
            false
          end
        end

        # Сохраняет текущую конфигурацию макетов страниц в отдельный YAML файл
        # @param file_path [String] путь к файлу layout.yaml
        # @return [Boolean] true в случае успешного сохранения
        def save_to_layout_yaml(file_path)
          return false unless file_path

          FileUtils.mkdir_p(File.dirname(file_path))
          layouts_data = @pdf_settings[:custom_layouts] || default_custom_layouts
          if layouts_data.is_a?(Hash)
            layouts_data.each_value do |page_slots|
              next unless page_slots.is_a?(Hash)
              hdr = page_slots[:header] || page_slots["header"]
              if hdr.is_a?(Hash)
                hdr[:y] = 0.0 if hdr.key?(:y)
                hdr["y"] = 0.0 if hdr.key?("y")
                hdr[:h] = 30.0 if hdr.key?(:h)
                hdr["h"] = 30.0 if hdr.key?("h")
                hdr[:h] ||= 30.0
              end
              s1 = page_slots[:slot_1] || page_slots["slot_1"]
              if s1.is_a?(Hash)
                c = (s1[:content] || s1["content"]).to_s
                if c.empty? || c == "none"
                  s1[:content] = "info_lines" if s1.key?(:content)
                  s1["content"] = "info_lines" if s1.key?("content")
                  s1[:content] ||= "info_lines"
                end
                gap_val = (s1[:item_gap_mm] || s1["item_gap_mm"] || s1[:item_gap] || s1["item_gap"] || 2.0).to_f
                s1[:item_gap_mm] = gap_val if s1.key?(:item_gap_mm)
                s1["item_gap_mm"] = gap_val if s1.key?("item_gap_mm")
                s1[:item_gap_mm] ||= gap_val
              end
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
        # @return [Boolean] true в случае успешной загрузки
        def load_from_yaml(file_path)
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
                @history = raw_hist.map do |item|
                  if item.is_a?(Array)
                    d = item[0].to_s
                    t = item[1].to_s
                    lnk = item[2].to_s
                  elsif item.is_a?(Hash)
                    d = (item[:data] || item[:date] || item["data"] || item["date"]).to_s
                    t = (item[:edit] || item[:text] || item["edit"] || item["text"] || item[:description] || item["description"]).to_s
                    lnk = (item[:pdf_link] || item["pdf_link"]).to_s
                  else
                    d = ""
                    t = item.to_s
                    lnk = ""
                  end
                  { date: d, text: t, description: t, data: d, edit: t, pdf_link: lnk }
                end
                @workflow[:history_edit] = @history.map { |h| [h[:data], h[:edit]] }
                sync_history_entries!
              end

              sync_project_fields!

              if root.key?(:pdf_settings) && root[:pdf_settings].is_a?(Hash)
                @pdf_settings.merge!(root[:pdf_settings])
              end

              if root[:scenes].is_a?(Array)
                @scenes = root[:scenes].map { |h| SceneItem.from_h(h) }
              end

              # Проверяем, есть ли рядом файл edit_history.yaml
              dir = File.dirname(file_path)
              hist_file = File.join(dir, "edit_history.yaml")
              if File.exist?(hist_file)
                load_from_edit_history(hist_file, @project[:articul])
              end

              # Если в проекте есть явный локальный layout.yaml (переопределение макета проекта), применяем его
              local_layout = File.join(dir, "layout.yaml")
              if File.exist?(local_layout)
                load_from_layout_yaml(local_layout)
              end

              return true
            end

            # Вариант 2: Многодокументный потоковый формат
            if docs[0].is_a?(Hash)
              if docs[0].key?(:project)
                @project.merge!(docs[0][:project])
              else
                @project.merge!(docs[0])
              end
              sync_project_fields!
            end
            if docs[1].is_a?(Array)
              @scenes = docs[1].map { |h| SceneItem.from_h(h) }
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

            # Проверяем локальный файл макета для варианта 2
            dir = File.dirname(file_path)
            local_layout = File.join(dir, "layout.yaml")
            if File.exist?(local_layout)
              load_from_layout_yaml(local_layout)
            end

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
          wf_out = {
            author:         @workflow[:author].to_s,
            price:          @workflow[:price].to_s.empty? ? "" : @workflow[:price],
            start_date:     @workflow[:start_date].to_s,
            end_date:       @workflow[:end_date].to_s,
            total_duration: @workflow[:total_duration].to_s,
            version:        @workflow[:version].to_s,
            revision:       @workflow[:revision].to_s,
            stadia:         normalize_stadia(@workflow[:stadia]),
            history_edit:   @workflow[:history_edit] || []
          }
          wf_out[:status] = @workflow[:status].to_s unless @workflow[:status].to_s.empty?

          # 4. Секция history_edit (Корневая, как в project.yaml)
          hist_out = (@history || []).map do |h|
            next unless h.is_a?(Hash)
            d = (h[:data] || h[:date] || h["data"] || h["date"] || "").to_s
            t = (h[:edit] || h[:text] || h[:description] || h["edit"] || h["text"] || h["description"] || "").to_s
            lnk = (h[:pdf_link] || h["pdf_link"] || "").to_s
            entry = {
              "data" => d,
              "edit" => t
            }
            entry["pdf_link"] = lnk unless lnk.empty?
            entry
          end.compact

          # 5. Секция directories (Массив объектов)
          dirs_out = normalize_directories_to_array(@directories)

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

        # Увеличивает номер ревизии проекта (+1) и добавляет запись с таймштампом в историю
        # @param description [String] текстовое описание причины создания новой ревизии
        # @param date_str [String, nil] пользовательская дата (по умолчанию Time.now)
        # @param pdf_link [String, nil] имя/ссылка на файл PDF
        # @return [void]
        def increment_revision!(description = "Экспорт в PDF", date_str = nil, pdf_link = nil)
          rev_num = (@workflow[:revision].to_i rescue 0)
          rev_num = 1 if rev_num <= 0
          new_rev = rev_num + 1
          new_rev_str = sprintf("%03d", new_rev)

          @workflow[:revision]     = new_rev_str
          @project_info[:revision] = new_rev

          now_str = date_str || Time.now.strftime("%Y-%m-%d %H:%M")
          clean_desc = description.to_s.strip
          clean_desc = "Правки" if clean_desc.empty?
          entry_text = clean_desc.include?("(rev.") ? clean_desc : "#{clean_desc} (rev. #{new_rev_str})"

          @workflow[:last_edit]     = clean_desc
          @project_info[:last_edit] = clean_desc
          @project_info[:edit]      = clean_desc

          pdf_link_str = pdf_link.to_s.strip
          if pdf_link_str.empty?
            art = @project[:articul].to_s.strip
            art = "PROJECT" if art.empty?
            ver = @workflow[:version].to_s.strip
            ver = "01" if ver.empty?
            pdf_link_str = "#{art}_v#{ver}_r#{new_rev_str}.pdf"
          end

          @workflow[:history_edit] ||= []
          @workflow[:history_edit].unshift([now_str, entry_text])

          new_entry = {
            date:        now_str,
            data:        now_str,
            text:        entry_text,
            edit:        entry_text,
            description: entry_text,
            pdf_link:    pdf_link_str
          }
          @history.unshift(new_entry)
        end

        # Преобразует все данные проекта в стандартный Ruby Hash
        # @return [Hash] хэш со всеми полями проекта, настройками, сценами и историей
        def to_h
          sync_project_fields!

          hist_out = (@history || []).map do |h|
            next unless h.is_a?(Hash)
            d = (h[:data] || h[:date] || h["data"] || h["date"] || "").to_s
            t = (h[:edit] || h[:text] || h[:description] || h["edit"] || h["text"] || h["description"] || "").to_s
            lnk = (h[:pdf_link] || h["pdf_link"] || "").to_s
            {
              data:     d,
              date:     d,
              edit:     t,
              text:     t,
              pdf_link: lnk
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
