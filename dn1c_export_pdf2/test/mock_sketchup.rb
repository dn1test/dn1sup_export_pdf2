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
