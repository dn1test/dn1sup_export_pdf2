# frozen_string_literal: true

module DN1Code
  module ExportPdf2
    module Model
      # Утилиты для путей файлов на диске.
      module PathUtil
        class << self
          # Строит URL со схемой file:/// из пути файла или папки.
          # UI.openURL принимает только URL: символ '#' обрезается как фрагмент,
          # пробелы, '%' и кириллица ломают запрос, поэтому каждый сегмент пути
          # процент-кодируется (RFC 3986: '#' -> %23, пробел -> %20).
          # @param path [String, nil] путь файла или папки (прямые или обратные слэши)
          # @return [String, nil] URL вида file:///U:/... либо nil для пустого пути
          def file_url(path)
            clean = path.to_s.strip.tr("\\", "/")
            return nil if clean.empty?

            encoded = clean.split("/", -1).map { |segment| encode_segment(segment) }.join("/")
            "file:///" + encoded
          end

          private

          # Кодирует небезопасные байты сегмента; разделители '/' и ':' (буква
          # диска) не попадают сюда
          def encode_segment(segment)
            segment.bytes.map do |byte|
              char = byte.chr
              char.match?(/[A-Za-z0-9\-._~:]/) ? char : format("%%%02X", byte)
            end.join
          end
        end
      end
    end
  end
end
