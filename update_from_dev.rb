# frozen_string_literal: true

# -------------------------------------------------------------------------------
# Standalone CLI Script: Обновление DN1Sup Export PDF 2 из dev-папки в SketchUp Plugins
# Запуск:
#   ruby update_from_dev.rb
# -------------------------------------------------------------------------------

require_relative "dn1sup_export_pdf2/version"
require_relative "dn1sup_export_pdf2/service/dev_updater"
require "json"
require "socket"

puts "=========================================================="
puts "  DN1Sup Export PDF 2 (v#{DN1Code::ExportPdf2::PLUGIN_VERSION}) — Обновление из dev-папки"
puts "=========================================================="

dev_dir = ARGV[0] || File.expand_path(__dir__)
plugins_dir = ARGV[1]

puts "[1/4] Поиск каталогов..."
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
    puts "  ✅ GUI собран в dn1sup_export_pdf2/dialog/html"
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
# Мост dn1sup_mcp2 слушает 127.0.0.1:9877 по TCP newline-JSON (НЕ HTTP):
# один запрос = одно соединение, одна строка JSON с "\n", ответ — одна строка JSON.
# Команды: eval | status | ping | stop (см. bridge_client.rb моста).
# Старый код слал сюда HTTP POST /eval — мост HTTP не понимает, и скрипт всегда
# врал "мост не запущен", хотя SketchUp работал (проверено через MCP status).
bridge_port = 9877
begin
  # Код на Ruby для выполнения внутри SketchUp
  ruby_code = <<~RUBY
    if defined?(DN1Code::ExportPdf2::Service::DevUpdater)
      DN1Code::ExportPdf2::Service::DevUpdater.reload!
    else
      load File.join(Sketchup.find_support_file("Plugins"), "dn1sup_export_pdf2.rb")
    end
  RUBY

  request = JSON.generate({ id: rand(1..1_000_000_000), cmd: "eval", code: ruby_code }) + "\n"

  sock = Socket.tcp("127.0.0.1", bridge_port, connect_timeout: 2)
  sock.write(request)
  line = nil
  line = sock.gets if IO.select([sock], nil, nil, 15.0)
  sock.close

  if line
    resp = (JSON.parse(line) rescue {})
    err = resp["error"] || resp["backtrace"]
    if err
      puts "  ⚠️  SketchUp ответил с ошибкой: #{err}"
      puts "     Файлы в каталоге Plugins обновлены — перезагрузите расширение вручную."
    else
      puts "  ⚡ SketchUp обнаружен (порт #{bridge_port}): плагин успешно перезагружен на лету!"
    end
  else
    puts "  ⚠️  Мост на порту #{bridge_port} закрыл соединение без ответа."
    puts "     Файлы в каталоге Plugins обновлены — перезагрузите расширение вручную."
  end
rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT, SocketError
  puts "  ℹ️  SketchUp-мост не отвечает на порту #{bridge_port} (SketchUp закрыт?)."
  puts "     Файлы в каталоге Plugins обновлены. При следующем открытии SketchUp"
  puts "     или через меню 'Extensions -> DN1Sup -> Export PDF 2 -> Перезагрузить' изменения вступят в силу."
rescue StandardError => e
  puts "  ⚠️  Hot Reload не удался (#{e.class}: #{e.message})."
  puts "     Файлы в каталоге Plugins обновлены — перезагрузите расширение вручную."
end

puts "\n=========================================================="
puts "  Готово! Версия: v#{DN1Code::ExportPdf2::PLUGIN_VERSION}"
puts "=========================================================="
