# frozen_string_literal: true

# -------------------------------------------------------------------------------
# Standalone CLI Script: Обновление DN1C Export PDF 2 из dev-папки в SketchUp Plugins
# Запуск:
#   ruby update_from_dev.rb
# -------------------------------------------------------------------------------

require_relative "dn1c_export_pdf2/version"
require_relative "dn1c_export_pdf2/service/dev_updater"
require "net/http"
require "json"

puts "=========================================================="
puts "  DN1C Export PDF 2 (v#{DN1Code::ExportPdf2::PLUGIN_VERSION}) — Обновление из dev-папки"
puts "=========================================================="

dev_dir = ARGV[0] || File.expand_path(__dir__)
plugins_dir = ARGV[1]

puts "[1/3] Поиск каталогов..."
src = DN1Code::ExportPdf2::Service::DevUpdater.resolve_dev_dir(dev_dir)
dst = DN1Code::ExportPdf2::Service::DevUpdater.resolve_plugins_dir(plugins_dir)

puts "  • Dev папка:     #{src || '(не найдена)'}"
puts "  • Plugins папка: #{dst || '(не найдена)'}"

unless src && Dir.exist?(src)
  warn "ОШИБКА: Исходный каталог разработки не найден: #{dev_dir}"
  exit 1
end

unless dst && Dir.exist?(dst)
  warn "ОШИБКА: Целевой каталог Plugins SketchUp не найден: #{dst}"
  exit 1
end

puts "\n[2/4] Сборка веб-интерфейса (Vue + Vite)..."
frontend_dir = File.join(__dir__, "frontend")
if Dir.exist?(File.join(frontend_dir, "node_modules"))
  npm = Gem.win_platform? ? "npm.cmd" : "npm"
  if system(npm, "run", "build", chdir: frontend_dir)
    puts "  ✅ GUI собран в dn1c_export_pdf2/dialog/html"
  else
    warn "  ⚠️  Сборка GUI завершилась с ошибкой — в Plugins уйдёт последняя успешная сборка"
  end
else
  puts "  ℹ️  frontend/node_modules не установлен — берётся закоммиченная сборка dialog/html"
end

puts "\n[3/4] Копирование файлов расширения..."
res = DN1Code::ExportPdf2::Service::DevUpdater.update!(src, dst)

if res[:success]
  if res[:same_dir]
    puts "  ℹ️  Каталоги совпадают: расширение работает напрямую из dev-папки."
  else
    puts "  ✅ Скопировано файлов: #{res[:files_copied]}"
    puts "  🧹 Удалено устаревших: #{res[:files_pruned] || 0}" if res[:files_pruned].to_i.positive?
    puts "  ✅ Дата обновления:    #{res[:updated_at]}"
  end
else
  warn "  ❌ Ошибка копирования: #{res[:error]}"
  exit 1
end

puts "\n[4/4] Проверка запущенного SketchUp и горячая перезагрузка..."
# Попытка послать команду горячей перезагрузки через dev-мост SketchUp (порт 9877)
bridge_port = 9877
begin
  uri = URI("http://127.0.0.1:#{bridge_port}/eval")
  # Код на Ruby для выполнения внутри SketchUp
  ruby_code = <<~RUBY
    if defined?(DN1Code::ExportPdf2::Service::DevUpdater)
      DN1Code::ExportPdf2::Service::DevUpdater.reload!
    else
      load File.join(Sketchup.find_support_file("Plugins"), "dn1c_export_pdf2.rb")
    end
  RUBY

  req = Net::HTTP::Post.new(uri)
  req["Content-Type"] = "application/json"
  req.body = JSON.generate({ code: ruby_code })

  http = Net::HTTP.new(uri.host, uri.port)
  http.open_timeout = 1.0
  # Перезагрузка расширения внутри SketchUp может занять несколько секунд
  http.read_timeout = 15.0
  response = http.request(req)

  if response.is_a?(Net::HTTPSuccess)
    puts "  ⚡ SketchUp обнаружен (порт #{bridge_port}): плагин успешно перезагружен на лету!"
  else
    puts "  ⚡ SketchUp ответил (код #{response.code}), расширение обновлено в Plugins."
  end
rescue Errno::ECONNREFUSED, Net::OpenTimeout, StandardError
  puts "  ℹ️  SketchUp dev-мост не запущен на порту #{bridge_port}."
  puts "     Файлы в каталоге Plugins обновлены. При следующем открытии SketchUp"
  puts "     или через меню 'Plugins -> #{DN1Code::ExportPdf2::PLUGIN_NAME} -> Перезагрузить' изменения вступят в силу."
end

puts "\n=========================================================="
puts "  Готово! Версия: v#{DN1Code::ExportPdf2::PLUGIN_VERSION}"
puts "=========================================================="
