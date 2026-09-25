# frozen_string_literal: true

# -------------------------------------------------------------------------------
# Mock SketchUp API Environment for Standalone CLI Testing (Outside SketchUp ONLY)
# -------------------------------------------------------------------------------

# Если скрипт загружен внутри реального SketchUp — полностью выходим и ничего не переопределяем!
if defined?(Sketchup) && Sketchup.respond_to?(:version)
  # Сброс мока active_model если он был ранее установлен
  if Sketchup.instance_variable_defined?(:@active_model)
    Sketchup.remove_instance_variable(:@active_model) rescue nil
  end
  # Удаляем временный метод active_model= если был объявлен
  if Sketchup.singleton_class.method_defined?(:active_model=)
    class << Sketchup
      remove_method :active_model= rescue nil
    end
  end
  return
end

module Sketchup
  class Text
    attr_accessor :text, :font
    def initialize(text = "Выноска", font = { name: "Sofia Sans Condensed", size: 14, bold: false, italic: false })
      @text = text
      @font = font
    end
  end

  class MockEntities
    include Enumerable
    attr_accessor :items
    def initialize(items = [])
      @items = items
    end
    def each(&block); @items.each(&block); end
    def grep(klass)
      @items.select { |item| item.is_a?(klass) }
    end
    def <<(item); @items << item; self; end
  end

  class MockStyle
    attr_accessor :name
    def initialize(name = "Default Style")
      @name = name
    end
  end

  class MockStyles
    attr_accessor :selected_style, :active_style
    def initialize
      @selected_style = MockStyle.new("Default Style")
      @active_style = @selected_style
    end
  end

  class MockPage
    attr_accessor :name, :description, :include_in_animation, :rendering_options, :style

    def initialize(name, description = "", include_in_anim = true)
      @name = name
      @description = description
      @include_in_animation = include_in_anim
      @style = MockStyle.new("#{name} Style")
      @rendering_options = {
        "SilhouetteWidth" => 2,
        "SectionCutWidth" => 4,
        "DepthQueWidth" => 4,
        "LineEndWidth" => 1,
        "LineExtension" => 1,
        "DrawSilhouettes" => true,
        "DrawLineEnds" => false,
        "ExtendLines" => false,
        "DrawProfilesOnly" => false,
        "DisplayDims" => true,
        "DisplayText" => true,
        "RenderMode" => 2
      }
    end

    def include_in_animation?
      @include_in_animation
    end
  end

  class MockPages
    include Enumerable

    def initialize(pages = [])
      @pages = pages
      @selected = pages.first
    end

    def each(&block)
      @pages.each(&block)
    end

    def size
      @pages.size
    end

    def [](index)
      @pages[index]
    end

    def selected_page
      @selected
    end

    def selected_page=(page)
      @selected = page
    end

    def add(name)
      p = MockPage.new(name)
      @pages << p
      p
    end
  end

  class MockView
    attr_accessor :vpwidth, :vpheight, :drawing_color, :line_width, :line_stipple, :drawn_elements, :last_write_image_options

    def initialize
      @vpwidth = 1920.0
      @vpheight = 1080.0
      @drawing_color = nil
      @line_width = 1
      @line_stipple = ""
      @drawn_elements = []
      @last_write_image_options = nil
    end

    def draw2d(mode, pts)
      @drawn_elements << { mode: mode, pts: pts, color: @drawing_color }
    end

    def draw_text(pos, text, options = nil)
      @drawn_elements << { mode: :text, pos: pos, text: text, options: options }
    end

    def invalidate
      true
    end

    def write_image(options = {})
      @last_write_image_options = options
      filename = options[:filename]
      width = options[:width] || 800
      height = options[:height] || 600
      DN1Code::ExportPdf2::Service::RenderService.create_fallback_image(filename, width, height)
      true
    end
  end

  class Overlay
    attr_reader :overlay_id, :name, :description
    attr_accessor :enabled

    def initialize(overlay_id, name, options = {})
      @overlay_id = overlay_id
      @name = name
      @description = options[:description] || ""
      @enabled = false
    end

    def enabled?
      @enabled == true
    end

    def draw(view); end
  end

  class MockOverlaysCollection
    include Enumerable

    def initialize
      @overlays = []
    end

    def add(overlay)
      @overlays << overlay unless @overlays.include?(overlay)
      overlay
    end

    def remove(overlay)
      @overlays.delete(overlay)
    end

    def each(&block)
      @overlays.each(&block)
    end

    def size
      @overlays.size
    end

    def [](idx)
      @overlays[idx]
    end
  end

  class AppObserver
    def onNewModel(model); end
    def onOpenModel(model); end
    def onActivateModel(model); end
    def onPreSaveModel(model); end
    def onPostSaveModel(model); end
    def onSaveModel(model); end
    def onQuit; end
  end

  class ModelObserver
    def onPreSaveModel(model); end
    def onPostSaveModel(model); end
    def onSaveModel(model); end
    def onErase(model); end
  end

  class MockModel
    attr_accessor :path, :pages, :active_view, :attributes, :observers, :overlays, :rendering_options, :styles, :entities

    def initialize(path = "U:/Projects/SampleProject/model.skp")
      @path = path
      @pages = MockPages.new
      @active_view = MockView.new
      @overlays = MockOverlaysCollection.new
      @styles = MockStyles.new
      @attributes = {}
      @observers = []
      @entities = MockEntities.new([Text.new])
      @rendering_options = {
        "SilhouetteWidth" => 2,
        "SectionCutWidth" => 4,
        "DepthQueWidth" => 4,
        "LineEndWidth" => 1,
        "DisplayDims" => true,
        "DisplayText" => true,
        "RenderMode" => 2
      }
    end

    def add_observer(obs)
      @observers << obs unless @observers.include?(obs)
      true
    end

    def remove_observer(obs)
      @observers.delete(obs)
      true
    end

    def get_attribute(dict, key, default = nil)
      @attributes.dig(dict, key) || default
    end

    def set_attribute(dict, key, value)
      @attributes[dict] ||= {}
      @attributes[dict][key] = value
    end

    def save(new_path = nil)
      @path = new_path if new_path && !new_path.empty?

      # Pre-save event
      @observers.each { |o| o.onPreSaveModel(self) if o.respond_to?(:onPreSaveModel) }
      Sketchup.observers.each { |o| o.onPreSaveModel(self) if o.respond_to?(:onPreSaveModel) }

      FileUtils.mkdir_p(File.dirname(@path))
      File.write(@path, "MOCK_SKP_CONTENT")

      # Post-save event
      @observers.each do |o|
        o.onPostSaveModel(self) if o.respond_to?(:onPostSaveModel)
        o.onSaveModel(self) if o.respond_to?(:onSaveModel)
      end
      Sketchup.observers.each do |o|
        o.onPostSaveModel(self) if o.respond_to?(:onPostSaveModel)
        o.onSaveModel(self) if o.respond_to?(:onSaveModel)
      end

      true
    end

    def save_copy(backup_path)
      FileUtils.mkdir_p(File.dirname(backup_path))
      File.write(backup_path, "MOCK_SKP_BACKUP_CONTENT")
      true
    end
  end

  def self.observers
    @observers ||= []
  end

  def self.add_observer(obs)
    observers << obs unless observers.include?(obs)
    true
  end

  def self.active_model
    @active_model ||= MockModel.new
  end

  def self.active_model=(model)
    @active_model = model
  end

  def self.status_text=(text)
    @status_text = text
  end

  def self.status_text
    @status_text
  end

  def self.register_extension(ext, load_on_start = true)
    true
  end

  # Цвет SketchUp (RGB + опциональная альфа 0..255)
  class Color
    attr_reader :red, :green, :blue, :alpha

    def initialize(*args)
      if args.size >= 3
        @red = args[0].to_i
        @green = args[1].to_i
        @blue = args[2].to_i
        @alpha = args[3].nil? ? 255 : args[3].to_i
      end
    end

    def to_a
      [@red, @green, @blue, @alpha]
    end
  end
end

module Geom
  class Point3d
    attr_accessor :x, :y, :z

    def initialize(x = 0.0, y = 0.0, z = 0.0)
      @x = x.to_f
      @y = y.to_f
      @z = z.to_f
    end

    def to_a
      [@x, @y, @z]
    end
  end

  class Point2d
    attr_accessor :x, :y

    def initialize(x = 0.0, y = 0.0)
      @x = x.to_f
      @y = y.to_f
    end

    def to_a
      [@x, @y]
    end
  end
end

class SketchupExtension
  attr_accessor :name, :description, :version, :copyright, :creator

  def initialize(name, path)
    @name = name
    @path = path
  end
end

module UI
  MB_OK = 0

  def self.messagebox(msg, type = 0)
    puts "[UI::messagebox] #{msg}"
  end

  def self.openURL(url)
    puts "[UI::openURL] #{url}"
  end

  def self.menu(name)
    MockMenu.new(name)
  end

  class MockMenu
    def initialize(name); end
    def add_submenu(name); self; end
    def add_item(name, &block); self; end
    def add_separator; self; end
    def set_validation_proc(item = nil, &block); true; end
  end

  class Toolbar
    def initialize(name); end
    def add_item(cmd); end
    def restore; end
  end

  class Command
    attr_accessor :tooltip, :status_bar_text, :small_icon, :large_icon
    def initialize(name, &block); end
    def set_validation_proc(&block); true; end
  end

  MF_CHECKED   = 1 unless defined?(MF_CHECKED)
  MF_UNCHECKED = 0 unless defined?(MF_UNCHECKED)

  class HtmlDialog
    STYLE_DIALOG = 1
    def initialize(opts = {}); end
    def set_file(path); end
    def add_action_callback(name, &block); end
    def show; end
    def visible?; false; end
    def bring_to_front; end
    def execute_script(code); end
  end
end

GL_QUADS     = 7 unless defined?(GL_QUADS)
GL_LINES     = 1 unless defined?(GL_LINES)
GL_LINE_LOOP = 2 unless defined?(GL_LINE_LOOP)

def file_loaded?(file)
  $LOADED_FEATURES_MOCK ||= []
  $LOADED_FEATURES_MOCK.include?(file)
end

def file_loaded(file)
  $LOADED_FEATURES_MOCK ||= []
  $LOADED_FEATURES_MOCK << file
end

# -------------------------------------------------------------------------------
# Mock Geom & LayOut API for Testing
# -------------------------------------------------------------------------------
module Geom
  class Point2d
    attr_accessor :x, :y
    def initialize(x = 0, y = 0)
      @x = x.to_f
      @y = y.to_f
    end

    def to_a
      [@x, @y]
    end
  end

  class Bounds2d
    attr_accessor :x, :y, :width, :height
    def initialize(x = 0, y = 0, w = 1, h = 1)
      if x.is_a?(Point2d) && y.is_a?(Point2d)
        @x = x.x
        @y = x.y
        @width = y.x - x.x
        @height = y.y - x.y
      else
        @x = x.to_f
        @y = y.to_f
        @width = w.to_f
        @height = h.to_f
      end
    end

    def upper_left
      Point2d.new(@x, @y)
    end

    def lower_right
      Point2d.new(@x + @width, @y + @height)
    end

    def to_a
      [upper_left.to_a, lower_right.to_a]
    end
  end

  # Мок 2D-трансформации LayOut (бумажное пространство)
  class Transformation2d
    attr_reader :to_a

    def initialize(arr = [1.0, 0.0, 0.0, 1.0, 0.0, 0.0])
      @to_a = arr.map(&:to_f)
    end

    def self.rotation(_point2d, angle_rad)
      cos = Math.cos(angle_rad)
      sin = Math.sin(angle_rad)
      new([cos, sin, -sin, cos, 0.0, 0.0])
    end

    def self.translation(vector2d_or_arr)
      vals = vector2d_or_arr.respond_to?(:x) ? [vector2d_or_arr.x, vector2d_or_arr.y] : vector2d_or_arr
      new([1.0, 0.0, 0.0, 1.0, vals[0].to_f, vals[1].to_f])
    end

    def identity?
      @to_a == [1.0, 0.0, 0.0, 1.0, 0.0, 0.0]
    end
  end
end

module Layout
  class PageInfo
    RESOLUTION_LOW    = 0
    RESOLUTION_MEDIUM = 1
    RESOLUTION_HIGH   = 2

    attr_accessor :width, :height, :left_margin, :right_margin, :top_margin, :bottom_margin,
                  :display_margins, :show_margins, :output_resolution, :image_output_resolution
    def initialize
      @width = 11.6929
      @height = 8.2677
      @left_margin = 0.2
      @right_margin = 0.2
      @top_margin = 0.2
      @bottom_margin = 0.2
      @display_margins = false
      @show_margins = false
      @output_resolution = RESOLUTION_MEDIUM
      @image_output_resolution = RESOLUTION_MEDIUM
    end
  end

  class Page
    attr_accessor :name
    def initialize(name = "Page 1")
      @name = name
    end
  end

  class Pages
    include Enumerable
    def initialize
      @pages = [Page.new("Page 1")]
    end

    def each(&block)
      @pages.each(&block)
    end

    def count
      @pages.size
    end

    def size
      @pages.size
    end

    def initial
      @pages.first
    end

    def first
      @pages.first
    end

    def add(name)
      p = Page.new(name)
      @pages << p
      p
    end
  end

  class Layer
    attr_accessor :name, :shared
    def initialize(name = "Default", shared = false)
      @name = name
      @shared = shared
    end

    def shared?
      @shared
    end
  end

  class Layers
    include Enumerable
    def initialize
      @layers = [Layer.new("Default")]
    end

    def each(&block)
      @layers.each(&block)
    end

    def size
      @layers.size
    end

    def first
      @layers.first
    end

    def add(name, shared = false)
      l = Layer.new(name, shared)
      @layers << l
      l
    end
  end

  class Style
    ALIGN_LEFT   = 0
    ALIGN_RIGHT  = 1
    ALIGN_CENTER = 2
    ANCHOR_TOP    = 0
    ANCHOR_CENTER = 1
    ANCHOR_BOTTOM = 2

    attr_accessor :font_size, :font_family, :fill_color, :stroke_color,
                  :text_color, :text_bold, :text_italic, :text_alignment, :text_anchor,
                  :stroked, :solid_filled, :stroke_width
  end

  class Entity
    attr_accessor :style, :transformation
    def initialize
      @style = Style.new
      @transformation = nil
    end

    def bounds
      @bounds
    end

    def transform!(transformation)
      @transformation = transformation
      self
    end
  end

  class SketchUpModel < Entity
    RASTER_RENDER = 0
    VECTOR_RENDER = 1
    HYBRID_RENDER = 2

    attr_accessor :skp_path, :bounds, :scenes, :current_scene, :render_mode, :line_weight, :display_background

    def initialize(skp_path, bounds)
      super()
      @skp_path = skp_path
      @bounds = bounds
      @scenes = ["Last Saved SketchUp View", "01. Обложка", "02. Описание", "03. Вид", "Scene 1", "Scene 2"]
      @current_scene = 1
      @render_mode = RASTER_RENDER
      @line_weight = 0.5
      @display_background = true
    end

    def display_background?
      @display_background
    end

    def render_needed?
      true
    end

    def render
      true
    end

    def reset_style
      true
    end
  end

  class FormattedText < Entity
    GROW_MODE_BOUNDED   = 0
    GROW_MODE_UNBOUNDED = 1
    ANCHOR_TYPE_TOP_LEFT      = 0
    ANCHOR_TYPE_CENTER_LEFT   = 1
    ANCHOR_TYPE_BOTTOM_LEFT   = 2
    ANCHOR_TYPE_TOP_RIGHT     = 3
    ANCHOR_TYPE_CENTER_RIGHT  = 4
    ANCHOR_TYPE_BOTTOM_RIGHT  = 5
    ANCHOR_TYPE_TOP_CENTER    = 6
    ANCHOR_TYPE_CENTER_CENTER = 7
    ANCHOR_TYPE_BOTTOM_CENTER = 8

    attr_accessor :text, :bounds, :grow_mode, :rtf_data, :anchor_point, :anchor_type

    # Перегрузки: new(text, bounds) и new(text, anchor_point, anchor_type)
    def initialize(text, bounds_or_point, anchor_type = nil)
      super()
      @text = text
      if anchor_type.nil?
        @bounds = bounds_or_point
      else
        @anchor_point = bounds_or_point
        @anchor_type = anchor_type
      end
      @grow_mode = GROW_MODE_BOUNDED
    end

    # Возвращает Style для диапазона текста (мок: единый стиль)
    def style(_index = 0, _length = nil)
      @style
    end

    def apply_style(applied, _index = 0, _length = nil)
      @style = applied
      true
    end

    def rtf=(rtf_text)
      @rtf_data = rtf_text
      # Извлекаем читаемый текст из простого RTF для отладки
      # (кириллица приходит как \uNNNN? — декодируем в UTF-8, иначе .chr теряет её)
      @text = rtf_text.gsub(/\\u(-?\d+)\?/) { Regexp.last_match(1).to_i.abs.chr(Encoding::UTF_8) rescue "" }
                      .gsub(/\{\\[^{}]*}|\\[a-z]+\d* ?/i, "")
                      .gsub(/[{}]/, "")
      true
    end

    def plain_text
      @text.to_s
    end
  end

  # Растровое изображение на листе
  class Image < Entity
    attr_accessor :path, :bounds

    def initialize(path, bounds)
      super()
      @path = path
      @bounds = bounds
    end
  end

  # Прямоугольная фигура (разделительные линии)
  class Rectangle < Entity
    TYPE_NORMAL   = 0
    TYPE_ROUNDED  = 1
    TYPE_LOZENGE  = 2
    TYPE_BULGED   = 3

    attr_accessor :bounds, :type

    def initialize(bounds)
      super()
      @bounds = bounds
      @type = TYPE_NORMAL
    end
  end

  # Ломаная линия (галочка чекбокса стадии проекта)
  class Path < Entity
    attr_accessor :points

    def initialize(*points)
      super()
      @points = points
    end

    def append_point(point)
      @points << point
      self
    end
  end

  class Grid
    attr_accessor :show_grid, :print_grid
    def initialize
      @show_grid = true
      @print_grid = false
    end
  end

  class Document
    attr_accessor :page_info, :pages, :layers, :entities, :grid

    def initialize(template_path_or_opts = nil)
      @page_info = PageInfo.new
      if template_path_or_opts.is_a?(Hash)
        margin = template_path_or_opts[:margin] || template_path_or_opts[:margin_mm]
        is_mm = !template_path_or_opts[:margin_mm].nil?
        factor = is_mm ? 25.4 : 72.0
        if margin.is_a?(Array)
          top_m    = (margin[0] || 15).to_f / factor
          right_m  = (margin[1] || margin[0] || 15).to_f / factor
          bottom_m = (margin[2] || margin[0] || 15).to_f / factor
          left_m   = (margin[3] || margin[1] || margin[0] || 15).to_f / factor
          @page_info.top_margin    = top_m
          @page_info.right_margin  = right_m
          @page_info.bottom_margin = bottom_m
          @page_info.left_margin   = left_m
        elsif margin
          m_in = margin.to_f / factor
          @page_info.left_margin   = m_in
          @page_info.right_margin  = m_in
          @page_info.top_margin    = m_in
          @page_info.bottom_margin = m_in
        end
      end
      @pages     = Pages.new
      @layers    = Layers.new
      @grid      = Grid.new
      @entities  = []
    end

    def bounds
      w = (@page_info && @page_info.width) ? @page_info.width.to_f * 72.0 : 841.89
      h = (@page_info && @page_info.height) ? @page_info.height.to_f * 72.0 : 595.28
      margin = (@page_info && @page_info.left_margin) ? @page_info.left_margin.to_f * 72.0 : 14.17
      Struct.new(:width, :height, :top, :bottom, :left, :right).new(
        w - (margin * 2),
        h - (margin * 2),
        h - margin,
        margin,
        margin,
        w - margin
      )
    end

    def render_file(pdf_path)
      export(pdf_path)
    end

    def start_new_page
      pages.add("Page #{@pages.count + 1}")
    end

    def add_entity(entity, layer, page = nil)
      @entities << { entity: entity, layer: layer, page: page }
    end

    def remove_entity(entity)
      @entities.reject! { |rec| rec[:entity].equal?(entity) }
    end

    def export(pdf_path, options = nil)
      ::FileUtils.mkdir_p(File.dirname(pdf_path))

      # Определение параметров сжатия:
      # compress: true -> сжатие потоков через Zlib / FlateDecode
      # compress: false -> без сжатия, потоки сырые (максимальное качество)
      compress = if options.is_a?(Hash)
                   val = options.key?(:compress) ? options[:compress] : (options.key?(:compress_pdf) ? options[:compress_pdf] : options[:compress_images])
                   val == true || val.to_s == "true" || val == "compress"
                 else
                   false
                 end

      # Генерация валидного PDF-1.4 на чистом Ruby без сторонних библиотек
      sanitize = ->(s) { s.to_s.gsub(/[\\()]/, "").gsub(/[^\x20-\x7E\n]/, " ") }

      page_obj_nums = []
      content_obj_nums = []

      @pages.each_with_index do |page, page_idx|
        stream_lines = []
        stream_lines << "BT"
        stream_lines << "/F1 12 Tf"
        stream_lines << "50 550 Td"
        stream_lines << "(Mock LayOut API Export - #{sanitize.call(page.name)}) Tj"
        stream_lines << "0 -20 Td"
        stream_lines << "(Page #{page_idx + 1} of #{@pages.count}) Tj"

        page_entities = @entities.select { |rec| rec[:page].nil? || rec[:page].equal?(page) }
        page_entities.each do |rec|
          ent = rec[:entity]
          case ent
          when FormattedText
            txt = ent.respond_to?(:plain_text) ? ent.plain_text : ent.text.to_s
            stream_lines << "0 -14 Td (#{sanitize.call(txt)[0..100]}) Tj"
          when Image
            stream_lines << "0 -14 Td ([image:#{File.basename(ent.path.to_s)}]) Tj"
          when Rectangle
            stream_lines << "0 -6 Td (--- divider line ---) Tj"
          when SketchUpModel
            stream_lines << "0 -14 Td ([viewport:#{File.basename(ent.skp_path.to_s)} mode:#{ent.render_mode}]) Tj"
          end
        end

        # Добор объема для реалистичного размера PDF (с учетом сжатия Deflate)
        1400.times do |i|
          a = (i * 7919) % 99_991
          b = (i * 104_729) % 99_991
          stream_lines << "0 -6 Td (p#{page_idx} n#{i} ref#{a} pos#{b} #{'-' * (i % 12)}) Tj"
        end

        stream_lines << "ET"
        stream_data = stream_lines.join("\n")

        content_obj_num = 4 + (page_idx * 2) + 1
        page_obj_num = 4 + (page_idx * 2)

        page_obj_nums << page_obj_num
        content_obj_nums << { num: content_obj_num, data: stream_data }
      end

      # Формирование таблицы объектов PDF
      all_objs = {}
      all_objs[1] = "<</Type /Catalog /Pages 2 0 R>>"
      kids_str = page_obj_nums.map { |n| "#{n} 0 R" }.join(" ")
      all_objs[2] = "<</Type /Pages /Kids [#{kids_str}] /Count #{page_obj_nums.size}>>"
      all_objs[3] = "<</Type /Font /Subtype /Type1 /BaseFont /Helvetica>>"

      page_obj_nums.each_with_index do |p_num, idx|
        c_num = content_obj_nums[idx][:num]
        all_objs[p_num] = "<</Type /Page /Parent 2 0 R /MediaBox [0 0 842 595] /Resources <</Font <</F1 3 0 R>>>> /Contents #{c_num} 0 R>>"
        c_data = content_obj_nums[idx][:data]
        if compress
          require "zlib" unless defined?(::Zlib)
          compressed_data = ::Zlib::Deflate.deflate(c_data)
          all_objs[c_num] = "<</Length #{compressed_data.bytesize} /Filter /FlateDecode>>\nstream\n#{compressed_data}\nendstream"
        else
          all_objs[c_num] = "<</Length #{c_data.bytesize}>>\nstream\n#{c_data}\nendstream"
        end
      end

      File.open(pdf_path, "wb") do |f|
        f.write("%PDF-1.4\n%\xE2\xE3\xCF\xD3\n")
        offsets = {}
        total_objs = all_objs.keys.max
        (1..total_objs).each do |num|
          offsets[num] = f.pos
          f.write("#{num} 0 obj\n#{all_objs[num]}\nendobj\n")
        end
        xref_pos = f.pos
        f.write("xref\n0 #{total_objs + 1}\n")
        f.write("0000000000 65535 f \n")
        (1..total_objs).each do |num|
          f.write(sprintf("%010d 00000 n \n", offsets[num]))
        end
        f.write("trailer\n<</Size #{total_objs + 1} /Root 1 0 R>>\n")
        f.write("startxref\n#{xref_pos}\n%%EOF\n")
      end
      true
    end

    def save(layout_path)
      FileUtils.mkdir_p(File.dirname(layout_path))
      File.write(layout_path, "MOCK_LAYOUT_DOCUMENT_CONTENT")
      true
    end
  end
end
