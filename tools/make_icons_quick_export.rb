# frozen_string_literal: true
# =============================================================================
# tools/make_icons_quick_export.rb — генерация иконок быстрого экспорта:
#   • векторный SVG: dn1sup_export_pdf2/ico/quick_export.svg (исходник дизайна);
#   • растровые PNG: dn1sup_export_pdf2/ico/quick_export.png (16px),
#     dn1sup_export_pdf2/ico/quick_export_large.png (24px)
#   (рендеринг чистым Ruby с 4x суперсэмплингом и антиалиасингом,
#   геометрия повторяет quick_export.svg: светлый документ, красная шапка PDF,
#   серый превью-блок, жёлто-оранжевый круг-бейдж с белой молнией).
# =============================================================================

require 'zlib'
require 'fileutils'

# -- PNG сборщик -------------------------------------------------------------

def png_chunk(type, data)
  [data.bytesize].pack('N') + type + data + [Zlib.crc32(type + data)].pack('N')
end

def write_png(path, pixels, width, height)
  raw = pixels.map { |row| "\x00" + row.map { |px| px.pack('C4') }.join }.join
  png = "\x89PNG\r\n\x1a\n".b +
        png_chunk('IHDR', [width, height, 8, 6, 0, 0, 0].pack('N5')) +
        png_chunk('IDAT', Zlib::Deflate.deflate(raw, Zlib::BEST_COMPRESSION)) +
        png_chunk('IEND', '')
  File.binwrite(path, png)
  puts "  ✓ #{File.basename(path)} (#{width}x#{height})"
end

# -- Канва с альфа-блендингом -------------------------------------------------

class ImageBuffer
  attr_reader :w, :h, :pixels

  def initialize(w, h)
    @w = w
    @h = h
    @pixels = Array.new(h) { Array.new(w) { [0, 0, 0, 0] } }
  end

  def blend_pixel(x, y, r, g, b, a)
    return if x < 0 || x >= @w || y < 0 || y >= @h || a <= 0

    cur = @pixels[y][x]
    sa = a / 255.0
    da = cur[3] / 255.0
    out_a = sa + da * (1.0 - sa)
    return if out_a.zero?

    out_r = ((r * sa + cur[0] * da * (1.0 - sa)) / out_a).round.clamp(0, 255)
    out_g = ((g * sa + cur[1] * da * (1.0 - sa)) / out_a).round.clamp(0, 255)
    out_b = ((b * sa + cur[2] * da * (1.0 - sa)) / out_a).round.clamp(0, 255)
    @pixels[y][x] = [out_r, out_g, out_b, (out_a * 255).round.clamp(0, 255)]
  end

  # Сглаженный спуск (4x бокс-фильтр) в результирующий буфер
  def downsample(scale = 4)
    target_w = @w / scale
    target_h = @h / scale
    out = Array.new(target_h) { Array.new(target_w) { [0, 0, 0, 0] } }

    target_h.times do |ty|
      target_w.times do |tx|
        sum_r = 0.0
        sum_g = 0.0
        sum_b = 0.0
        sum_a = 0.0

        scale.times do |sy|
          scale.times do |sx|
            px = @pixels[ty * scale + sy][tx * scale + sx]
            a = px[3] / 255.0
            sum_r += px[0] * a
            sum_g += px[1] * a
            sum_b += px[2] * a
            sum_a += a
          end
        end

        count = (scale * scale).to_f
        avg_a = sum_a / count
        if avg_a > 0.001
          avg_r = (sum_r / sum_a).round.clamp(0, 255)
          avg_g = (sum_g / sum_a).round.clamp(0, 255)
          avg_b = (sum_b / sum_a).round.clamp(0, 255)
          out[ty][tx] = [avg_r, avg_g, avg_b, (avg_a * 255).round.clamp(0, 255)]
        end
      end
    end
    out
  end
end

# -- Геометрические помощники (в единицах сетки 24x24) ------------------------

def lerp(a, b, t)
  (a * (1.0 - t) + b * t).round
end

# Знаковая дистанция до скруглённого прямоугольника (отрицательная внутри)
def sd_round_rect(px, py, x0, y0, x1, y1, r)
  cx = (x0 + x1) / 2.0
  cy = (y0 + y1) / 2.0
  hx = (x1 - x0) / 2.0 - r
  hy = (y1 - y0) / 2.0 - r
  hx = 0.0 if hx.negative?
  hy = 0.0 if hy.negative?
  qx = (px - cx).abs - hx
  qy = (py - cy).abs - hy
  ax = qx.positive? ? qx : 0.0
  ay = qy.positive? ? qy : 0.0
  Math.sqrt(ax * ax + ay * ay) + [qx, qy].max - r
end

def point_in_poly(px, py, poly)
  inside = false
  j = poly.size - 1
  poly.each_with_index do |(xi, yi), i|
    xj, yj = poly[j]
    if ((yi > py) != (yj > py)) && (px < (xj - xi) * (py - yi) / (yj - yi) + xi)
      inside = !inside
    end
    j = i
  end
  inside
end

# Дистанция до отрезка (для линий-превью)
def dist_to_seg(px, py, x0, y0, x1, y1)
  dx = x1 - x0
  dy = y1 - y0
  len2 = dx * dx + dy * dy
  t = len2.zero? ? 0.0 : (((px - x0) * dx + (py - y0) * dy) / len2).clamp(0.0, 1.0)
  Math.sqrt((px - (x0 + dx * t))**2 + (py - (y0 + dy * t))**2)
end

# Микрошрифт 3x5 для надписи PDF в шапке (белым по красному)
GLYPHS_3X5 = {
  'P' => ['###', '#.#', '###', '#..', '#..'],
  'D' => ['##.', '#.#', '#.#', '#.#', '##.'],
  'F' => ['###', '#..', '##.', '#..', '#..']
}.freeze

def pdf_text_pixel?(nx, ny)
  # Надпись "PDF", центр (10.5, ~5.2), размер фонт-пикселя 0.55
  fp = 0.55
  text = 'PDF'
  total_w = text.length * 3 * fp + (text.length - 1) * fp
  x0 = 10.5 - total_w / 2.0
  y0 = 5.2 - 5 * fp / 2.0
  text.chars.each_with_index do |ch, gi|
    gx0 = x0 + gi * 4 * fp
    GLYPHS_3X5[ch].each_with_index do |row, r|
      row.chars.each_with_index do |c, col|
        next unless c == '#'

        px0 = gx0 + col * fp
        py0 = y0 + r * fp
        return true if nx >= px0 && nx < px0 + fp && ny >= py0 && ny < py0 + fp
      end
    end
  end
  false
end

# -- Рендеринг иконки высокого разрешения (на сетке 24 x 24) ------------------

MOUNTAIN = [[6.5, 15.0], [9.5, 11.5], [11.5, 14.0], [13.0, 12.5], [15.0, 15.0]].freeze
BOLT = [[18.5, 13.0], [14.5, 17.5], [16.8, 17.5], [16.0, 21.5],
        [20.0, 16.5], [17.7, 16.5]].freeze

def render_icon(target_size)
  scale = 4
  hires = target_size * scale
  buf = ImageBuffer.new(hires, hires)
  s = hires / 24.0

  hires.times do |y|
    ny = (y + 0.5) / s
    hires.times do |x|
      nx = (x + 0.5) / s

      # 1. Документ: x 4..17, y 2..22, rx 2
      #    заливка — вертикальный градиент #FFFFFF -> #E8EDF1, обводка #B0BEC5
      d_doc = sd_round_rect(nx, ny, 4.0, 2.0, 17.0, 22.0, 2.0)
      if d_doc <= 0.55
        if d_doc >= -0.55
          buf.blend_pixel(x, y, 176, 190, 197, 255) # обводка #B0BEC5
        else
          t = ((ny - 2.0) / 20.0).clamp(0.0, 1.0)
          buf.blend_pixel(x, y, lerp(255, 232, t), lerp(255, 237, t),
                          lerp(255, 241, t), 255)
        end
      end

      # 2. Красная шапка: верх документа, y 2..5.5 (верхние углы скруглены)
      if d_doc < -0.55 && ny <= 5.5
        if pdf_text_pixel?(nx, ny)
          buf.blend_pixel(x, y, 255, 255, 255, 255) # надпись PDF
        else
          t = (((nx - 4.0) + (ny - 2.0)) / 16.5).clamp(0.0, 1.0)
          buf.blend_pixel(x, y, lerp(229, 183, t), lerp(57, 28, t),
                          lerp(53, 28, t), 255) # #E53935 -> #B71C1C
        end
      end

      # 3. Серый превью-блок: x 6..15, y 9.5..15.7, rx 1
      #    заливка #E2E8F0, обводка #CBD5E1
      d_prev = sd_round_rect(nx, ny, 6.0, 9.5, 15.0, 15.7, 1.0)
      if d_prev <= 0.4
        if d_prev >= -0.4
          buf.blend_pixel(x, y, 203, 213, 225, 255) # #CBD5E1
        else
          buf.blend_pixel(x, y, 226, 232, 240, 255) # #E2E8F0
        end
      end

      # 4. Горы в превью: #64748B с opacity .8
      if d_prev < -0.4 && point_in_poly(nx, ny, MOUNTAIN)
        buf.blend_pixel(x, y, 100, 116, 139, 204)
      end

      # 5. Солнце в превью: центр (8.6, 11.4), r 1, #F59E0B
      if d_prev < -0.4 && ((nx - 8.6)**2 + (ny - 11.4)**2) <= 1.0
        buf.blend_pixel(x, y, 245, 158, 11, 255)
      end

      # 6. Строки-превью под блоком: #94A3B8 и #CBD5E1
      if dist_to_seg(nx, ny, 6.0, 18.0, 13.0, 18.0) <= 0.5 && d_doc < -0.55
        buf.blend_pixel(x, y, 148, 163, 184, 255)
      end
      if dist_to_seg(nx, ny, 6.0, 20.0, 11.0, 20.0) <= 0.5 && d_doc < -0.55
        buf.blend_pixel(x, y, 203, 213, 225, 255)
      end

      # 7. Круг-бейдж молнии: центр (17, 17), r 5,
      #    градиент #FBBF24 -> #EA580C, белая обводка
      d_badge = Math.sqrt((nx - 17.0)**2 + (ny - 17.0)**2)
      if d_badge <= 5.6
        if d_badge >= 3.9
          buf.blend_pixel(x, y, 255, 255, 255, 255) # обводка
        else
          t = (((nx - 12.0) + (ny - 12.0)) / 10.0).clamp(0.0, 1.0)
          buf.blend_pixel(x, y, lerp(251, 234, t), lerp(191, 88, t),
                          lerp(36, 12, t), 255)
        end
      end

      # 8. Белая молния на бейдже
      if d_badge < 3.9 && point_in_poly(nx, ny, BOLT)
        buf.blend_pixel(x, y, 255, 255, 255, 255)
      end
    end
  end

  buf.downsample(scale)
end

# -- Генерация файлов ----------------------------------------------------------

if __FILE__ == $PROGRAM_NAME
  out = File.join(__dir__, '..', 'dn1sup_export_pdf2', 'ico')
  FileUtils.mkdir_p(out)
  puts "Генерация иконок quick_export в #{out}:"

  { 'quick_export.png' => 16, 'quick_export_large.png' => 24 }.each do |name, size|
    px = render_icon(size)
    write_png(File.join(out, name), px, size, size)
  end

  puts "\nГотово! Иконки quick_export успешно созданы."
end
