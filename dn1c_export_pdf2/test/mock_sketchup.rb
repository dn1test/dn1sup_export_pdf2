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
  class MockPage
    attr_accessor :name, :description, :include_in_animation

    def initialize(name, description = "", include_in_anim = true)
      @name = name
      @description = description
      @include_in_animation = include_in_anim
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
    def write_image(options = {})
      filename = options[:filename]
      width = options[:width] || 800
      height = options[:height] || 600
      DN1Code::ExportPdf2::Service::RenderService.create_fallback_image(filename, width, height)
      true
    end
  end

  class MockModel
    attr_accessor :path, :pages, :active_view, :attributes

    def initialize(path = "U:/Projects/SampleProject/model.skp")
      @path = path
      @pages = MockPages.new
      @active_view = MockView.new
      @attributes = {}
    end

    def get_attribute(dict, key, default = nil)
      @attributes.dig(dict, key) || default
    end

    def set_attribute(dict, key, value)
      @attributes[dict] ||= {}
      @attributes[dict][key] = value
    end

    def save_copy(backup_path)
      FileUtils.mkdir_p(File.dirname(backup_path))
      File.write(backup_path, "MOCK_SKP_BACKUP_CONTENT")
      true
    end
  end

  def self.active_model
    @active_model ||= MockModel.new
  end

  def self.active_model=(model)
    @active_model = model
  end

  def self.register_extension(ext, load_on_start = true)
    true
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
  end

  class Toolbar
    def initialize(name); end
    def add_item(cmd); end
    def restore; end
  end

  class Command
    attr_accessor :tooltip, :status_bar_text, :small_icon, :large_icon
    def initialize(name, &block); end
  end

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
  end
end

module Layout
  class PageInfo
    attr_accessor :width, :height, :left_margin, :right_margin, :top_margin, :bottom_margin, :display_margins
    def initialize
      @width = 11.6929
      @height = 8.2677
      @left_margin = 0.2
      @right_margin = 0.2
      @top_margin = 0.2
      @bottom_margin = 0.2
      @display_margins = false
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
    attr_accessor :name
    def initialize(name = "Default")
      @name = name
    end
  end

  class Layers
    def initialize
      @layers = [Layer.new("Default")]
    end

    def first
      @layers.first
    end

    def add(name)
      l = Layer.new(name)
      @layers << l
      l
    end
  end

  class Style
    attr_accessor :font_size, :font_family, :fill_color, :stroke_color
  end

  class Entity
    attr_accessor :style
    def initialize
      @style = Style.new
    end
  end

  class SketchUpModel < Entity
    RASTER_RENDER = 0
    VECTOR_RENDER = 1
    HYBRID_RENDER = 2

    attr_accessor :skp_path, :bounds, :scenes, :current_scene, :render_mode

    def initialize(skp_path, bounds)
      super()
      @skp_path = skp_path
      @bounds = bounds
      @scenes = ["Last Saved SketchUp View", "01. Обложка", "02. Описание", "03. Вид", "Scene 1", "Scene 2"]
      @current_scene = 1
      @render_mode = RASTER_RENDER
    end

    def render_needed?
      true
    end

    def render
      true
    end
  end

  class FormattedText < Entity
    attr_accessor :text, :bounds
    def initialize(text, bounds)
      super()
      @text = text
      @bounds = bounds
    end
  end

  class Document
    attr_accessor :page_info, :pages, :layers, :entities

    def initialize(template_path = nil)
      @page_info = PageInfo.new
      @pages     = Pages.new
      @layers    = Layers.new
      @entities  = []
    end

    def add_entity(entity, layer, page = nil)
      @entities << { entity: entity, layer: layer, page: page }
    end

    def export(pdf_path, options = nil)
      FileUtils.mkdir_p(File.dirname(pdf_path))
      # Создаем валидный тестовый PDF
      pdf = Prawn::Document.new(page_size: "A4", page_layout: :landscape)
      pdf.text "Mock LayOut API Export"
      pdf.render_file(pdf_path)
      true
    end

    def save(layout_path)
      FileUtils.mkdir_p(File.dirname(layout_path))
      File.write(layout_path, "MOCK_LAYOUT_DOCUMENT_CONTENT")
      true
    end
  end
end
