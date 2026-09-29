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
      # Недельные/месячные/годовые разрезы не хранятся — вычисляются из daily
      # в report(). hourly нужен для почасового графика и чистится до
      # HOURLY_KEEP_DAYS дней.
      module WorkStats
        VERSION          = 1
        HOURLY_KEEP_DAYS = 90

        RU_MONTHS = %w[Янв Фев Мар Апр Май Июн Июл Авг Сен Окт Ноя Дек].freeze

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
        # @return [Hash] { total_seconds, today_seconds, week7_seconds,
        #   month30_seconds, first_tracked, last_tracked, empty,
        #   series: { hourly, daily, weekly, monthly, yearly } }
        def report(data, now = Time.now)
          data    = normalize(data)
          daily   = data[:daily]
          date    = now.to_date

          series = {
            hourly:  hourly_series(data[:hourly], now),
            daily:   daily_series(daily, date),
            weekly:  weekly_series(daily, date),
            monthly: monthly_series(daily, date),
            yearly:  yearly_series(daily, date)
          }

          {
            total_seconds:   data[:total_seconds].to_i,
            today_seconds:   daily[date.strftime("%Y-%m-%d")].to_i,
            week7_seconds:   window_seconds(daily, date - 6, date),
            month30_seconds: window_seconds(daily, date - 29, date),
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

        # Почасовой график: последние 24 часа, выровненные на начало часа.
        # Окно пересекает полночь, поэтому часы не из сегодняшнего дня
        # подписываются с датой («28.09 15:00»).
        def hourly_series(hourly, now)
          hour0 = Time.at((now.to_i / 3600) * 3600)
          today = now.to_date
          (0...24).reverse_each.map do |i|
            t = hour0 - i * 3600
            label = t.to_date == today ? t.strftime("%H:00") : t.strftime("%d.%m %H:00")
            { label: label, seconds: hourly[t.strftime("%Y-%m-%d %H")].to_i }
          end
        end

        def daily_series(daily, date)
          (0...30).reverse_each.map do |i|
            d = date - i
            { label: d.strftime("%d.%m"), seconds: daily[d.strftime("%Y-%m-%d")].to_i }
          end
        end

        # Недели по ISO (начало — понедельник), последние 12 недель
        def weekly_series(daily, date)
          monday = date - date.cwday + 1
          by_week = Hash.new(0)
          daily.each do |key, sec|
            d = begin
              Date.strptime(key, "%Y-%m-%d")
            rescue ArgumentError
              next
            end
            by_week[(d - d.cwday + 1).strftime("%Y-%m-%d")] += sec.to_i
          end
          (0...12).reverse_each.map do |i|
            ws = monday - i * 7
            { label: "#{ws.strftime('%d.%m')}–#{(ws + 6).strftime('%d.%m')}",
              seconds: by_week[ws.strftime("%Y-%m-%d")].to_i }
          end
        end

        def monthly_series(daily, date)
          by_month = Hash.new(0)
          daily.each { |key, sec| by_month[key[0, 7]] += sec.to_i if key.size >= 7 }
          (0...12).reverse_each.map do |i|
            first = Date.new(date.year, date.month, 1) << i
            { label: "#{RU_MONTHS[first.month - 1]} #{first.year}",
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
