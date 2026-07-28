# frozen_string_literal: true

module Flightdeck
  # Turns the common cron shapes into a readable sentence.
  #
  # Fugit parses cron but does not describe it, so this is ours. It only claims
  # to understand patterns it genuinely does: anything else returns nil and the
  # view shows the raw cron on its own. A confidently wrong description of a
  # schedule is worse than no description.
  class CronSchedule
    DAYS = %w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday].freeze
    MONTHS = %w[- January February March April May June July August September October November December].freeze

    attr_reader :raw

    def initialize(raw)
      @raw = raw.to_s.strip
    end

    def self.humanize(raw) = new(raw).to_human

    # Cron fields, plus an optional trailing timezone that Solid Queue allows.
    def fields
      @fields ||= begin
        parts = raw.split(/\s+/)
        parts.size.between?(5, 6) ? parts : nil
      end
    end

    def timezone
      fields && fields.size == 6 ? fields[5] : nil
    end

    def to_human
      return nil unless fields

      minute, hour, day_of_month, month, day_of_week = fields.first(5)
      return nil unless simple?(minute, hour, day_of_month, month, day_of_week)

      [ frequency(minute, hour, day_of_month, month, day_of_week), timezone ].compact.join(" ").presence
    end

    private
      # Only fields we can describe faithfully: a wildcard, a plain number, or a
      # `*/n` step. Lists and ranges are left to the raw cron.
      def simple?(*values)
        values.all? { |value| value.match?(%r{\A(\*|\d+|\*/\d+)\z}) }
      end

      def frequency(minute, hour, day_of_month, month, day_of_week)
        return every_n_minutes(minute) if step(minute) && hour == "*"
        return "every minute" if minute == "*" && hour == "*"

        return nil unless minute.match?(/\A\d+\z/)

        return "every #{pluralize_hours(step(hour))} at :#{pad(minute)}" if step(hour)
        return "every hour at :#{pad(minute)}" if hour == "*"
        return nil unless hour.match?(/\A\d+\z/)

        at = "at #{pad(hour)}:#{pad(minute)}"

        if day_of_week != "*"
          # cron ORs day-of-month with day-of-week when both are restricted, so
          # "0 0 1 1 1" is not "Mondays" — it is "January 1st or any Monday in
          # January". Refuse to describe that rather than describe it wrongly.
          return nil unless day_of_month == "*" && month == "*"
          return nil unless day_of_week.match?(/\A\d+\z/)

          return "#{DAYS[day_of_week.to_i % 7]}s #{at}"
        end

        return "#{ordinal_day(day_of_month)} of #{month_name(month)} #{at}" if day_of_month != "*" && month != "*"
        return "#{ordinal_day(day_of_month)} of every month #{at}" if day_of_month != "*"
        return "every day of #{month_name(month)} #{at}" if month != "*"

        "every day #{at}"
      end

      def every_n_minutes(minute)
        n = step(minute)
        n == 1 ? "every minute" : "every #{n} minutes"
      end

      def pluralize_hours(n) = n == 1 ? "hour" : "#{n} hours"

      def ordinal_day(value)
        return nil unless value.match?(/\A\d+\z/)

        "day #{value.to_i}"
      end

      def month_name(value)
        value.match?(/\A\d+\z/) ? MONTHS[value.to_i] : nil
      end

      def step(value)
        value[%r{\A\*/(\d+)\z}, 1]&.to_i
      end

      def pad(value) = format("%02d", value.to_i)
  end
end
