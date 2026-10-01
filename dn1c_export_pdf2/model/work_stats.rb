# frozen_string_literal: true

require "date"

module DN1Code
  module ExportPdf2
    module Model
      # Учёт активной работы над проектом: чистая логика над простым Hash
      # (секция work_stats в project.yaml). Никаких зависимостей от SketchUp —
      # агрегации и нормализация тестируются офлайн.
      #
      # Структура данных (в памяти ключи-символы, даты внутри daily/hourly —
      # строки, т.к. они же являются ключами в YAML):
      #   { version: 1,
      #     total_seconds: Integer,
      #     first_tracked: "YYYY-MM-DD" | nil,
      #     last_tracked:  "YYYY-MM-DD" | nil,
      #     daily:  { "YYYY-MM-DD"    => seconds },
      #     hourly: { "YYYY-MM-DD HH" => seconds } }  # HH — 00..23
      #
      # Месячные/годовые разрезы не хранятся — вычисляются из daily
      # в report(). hourly нужен для почасового графика и чистится до
      # HOURLY_KEEP_DAYS дней.
      module WorkStats
        VERSION          = 1
        HOURLY_KEEP_DAYS = 90

        RU_MONTHS = %w[Янв Фев Мар Апр Май Июн Июл Авг Сен Окт Ноя Дек].freeze
        RU_DAYS   = %w[Вс Пн Вт Ср Чт Пт Сб].freeze
        EN_MONTHS = %w[Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec].freeze
        EN_DAYS   = %w[Sun Mon Tue Wed Thu Fri Sat].freeze

        module_function

        # Пустая структура статистики
        # @return [Hash]
        def blank_data
          {
            version:       VERSION,
            total_seconds: 0,
            first_tracked: nil,
            last_tracked:  nil,
            daily:         {},
            hourly:        {}
          }
        end

        # Нормализует данные из YAML (ключи верхнего уровня могут прийти
        # строками, ключи дат — символами) и вливает в пустую структуру.
        # @param data [Hash, nil]
        # @return [Hash] новая нормализованная структура
        def normalize(data)
          base = blank_data
          return base unless data.is_a?(Hash)

          src = {}
          data.each { |key, value| src[key.to_sym] = value }

          base[:total_seconds] = src[:total_seconds].to_i if src[:total_seconds]
          base[:first_tracked] = src[:first_tracked].to_s unless src[:first_tracked].to_s.empty?
          base[:last_tracked]  = src[:last_tracked].to_s unless src[:last_tracked].to_s.empty?
          base[:daily]         = seconds_map(src[:daily])
          base[:hourly]        = seconds_map(src[:hourly])
          base[:version]       = src[:version].to_i.nonzero? || VERSION
          base
        end

        # Начисляет секунды активной работы в бакеты дня и часа.
        # @param data [Hash] структура статистики (мутируется)
        # @param seconds [Integer] начисляемые секунды (> 0)
        # @param at [Time] момент времени
        # @return [Hash] та же структура
        def accrue!(data, seconds, at = Time.now)
          return data unless data.is_a?(Hash) && seconds.is_a?(Numeric) && seconds.positive?

          seconds = seconds.round
          day     = at.strftime("%Y-%m-%d")
          hour    = at.strftime("%Y-%m-%d %H")

          data[:daily]         = {} unless data[:daily].is_a?(Hash)
          data[:hourly]        = {} unless data[:hourly].is_a?(Hash)
          data[:daily][day]    = data[:daily][day].to_i + seconds
          data[:hourly][hour]  = data[:hourly][hour].to_i + seconds
          data[:total_seconds] = data[:total_seconds].to_i + seconds
          data[:first_tracked] = [data[:first_tracked].to_s, day].min unless data[:first_tracked].to_s.empty?
          data[:first_tracked] ||= day
          data[:last_tracked]  = [data[:last_tracked].to_s, day].max
          data[:version]       = VERSION
          data
        end

        # Удаляет почасовые бакеты старше HOURLY_KEEP_DAYS дней (дневные хранятся
        # всегда — на них строятся недельные/месячные/годовые разрезы).
        # @param data [Hash] структура статистики (мутируется)
        # @param now [Time]
        # @return [Hash] та же структура
        def prune!(data, now = Time.now)
          return data unless data.is_a?(Hash) && data[:hourly].is_a?(Hash)

          cutoff = (now.to_date - HOURLY_KEEP_DAYS).strftime("%Y-%m-%d")
          data[:hourly].delete_if { |key, _sec| key.to_s[0, 10] < cutoff }
          data
        end

        # Пустая ли статистика (нечего показывать и незачем писать в YAML)
        # @param data [Hash, nil]
        # @return [Boolean]
        def blank?(data)
          return true unless data.is_a?(Hash)

          data[:total_seconds].to_i <= 0 && seconds_map(data[:daily]).empty?
        end

        # Человекочитаемая длительность для workflow.total_duration:
        # «45 мин», «2 ч 30 мин», «1 д 4 ч». Пустая строка при нуле.
        # @param seconds [Numeric]
        # @return [String]
        def format_duration(seconds)
          total = seconds.to_i
          return "" if total <= 0

          minutes = total / 60
          return "#{[minutes, 1].max} мин" if minutes < 60

          hours = minutes / 60
          if hours < 24
            rem = minutes % 60
            rem.positive? ? "#{hours} ч #{rem} мин" : "#{hours} ч"
          else
            days = hours / 24
            rem_h = hours % 24
            rem_h.positive? ? "#{days} д #{rem_h} ч" : "#{days} д"
          end
        end

        # Данные для вкладки «Статистика»: сводки и серии для графиков.
        # @param data [Hash] структура статистики
        # @param now [Time]
        # @return [Hash] { total_seconds, today_seconds, weeks3_seconds,
        #   month_seconds, today, first_tracked, last_tracked, empty,
        #   series: { hourly, daily, monthly, yearly } }
        def report(data, now = Time.now)
          data    = normalize(data)
          daily   = data[:daily]
          date    = now.to_date

          series = {
            hourly:  hourly_series(data[:hourly], now),
            daily:   daily_series(daily, date),
            monthly: monthly_series(daily, date),
            yearly:  yearly_series(daily, date)
          }

          {
            total_seconds:   data[:total_seconds].to_i,
            today_seconds:   daily[date.strftime("%Y-%m-%d")].to_i,
            weeks3_seconds:  window_seconds(daily, date - 20, date),
            month_seconds:   window_seconds(daily, Date.new(date.year, date.month, 1), date),
            today:           date.strftime("%d.%m.%Y"),
            first_tracked:   data[:first_tracked],
            last_tracked:    data[:last_tracked],
            empty:           data[:total_seconds].to_i <= 0,
            series:          series
          }
        end

        # ------------------------------------------------------------------
        # Внутренние хелперы (module_function — доступны и как функции модуля)

        # Приводит карту "дата/дата-час" => секунды к строковым ключам и целым
        # значениям (ключи из YAML приходят символами после symbolize_names)
        def seconds_map(raw)
          return {} unless raw.is_a?(Hash)

          raw.each_with_object({}) do |(key, sec), memo|
            str = key.to_s
            memo[str] = memo[str].to_i + sec.to_i
          end
        end

        def window_seconds(daily, from_date, to_date)
          daily.sum do |key, sec|
            key >= from_date.strftime("%Y-%m-%d") && key <= to_date.strftime("%Y-%m-%d") ? sec.to_i : 0
          end
        end

        # Почасовой график: часы текущего календарного дня 00..23 без дат —
        # дата дня показывается отдельно (поле today в report).
        def hourly_series(hourly, now)
          day = now.strftime("%Y-%m-%d")
          (0...24).map do |h|
            key = format("%s %02d", day, h)
            { label: format("%02d:00", h), seconds: hourly[key].to_i }
          end
        end

        # Короткие имена месяцев/дней недели для подписей графика —
        # по языку интерфейса (Locale.lang, см. locale.rb)
        def month_names
          Locale.lang == :en ? EN_MONTHS : RU_MONTHS
        end

        def day_names
          Locale.lang == :en ? EN_DAYS : RU_DAYS
        end

        # Дневной график: последние 3 недели (21 день), метки с днём недели
        # и флагом weekend для выделения сб/вс на графике
        def daily_series(daily, date)
          (0...21).reverse_each.map do |i|
            d = date - i
            { label: "#{day_names[d.wday]} #{d.strftime('%d.%m')}",
              seconds: daily[d.strftime("%Y-%m-%d")].to_i,
              weekend: d.saturday? || d.sunday? }
          end
        end

        def monthly_series(daily, date)
          by_month = Hash.new(0)
          daily.each { |key, sec| by_month[key[0, 7]] += sec.to_i if key.size >= 7 }
          (0...12).reverse_each.map do |i|
            first = Date.new(date.year, date.month, 1) << i
            { label: "#{month_names[first.month - 1]} #{first.year}",
              seconds: by_month[first.strftime("%Y-%m")].to_i }
          end
        end

        def yearly_series(daily, date)
          by_year = Hash.new(0)
          daily.each { |key, sec| by_year[key[0, 4]] += sec.to_i if key.size >= 4 }
          years = (by_year.keys + [date.strftime("%Y")]).uniq.sort
          years.map { |y| { label: y, seconds: by_year[y].to_i } }
        end
      end
    end
  end
end
