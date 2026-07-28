# frozen_string_literal: true

module Flightdeck
  module Metrics
    # The only adapter-specific SQL in Flightdeck.
    #
    # Charts bucket timestamps into fixed-width windows. Doing that portably
    # means converting a timestamp to a UTC epoch integer and dividing — never
    # date_trunc, which does not exist everywhere and drags the server's
    # timezone into the answer. Everything downstream is an integer number of
    # seconds since the epoch, in UTC; the display timezone is applied at render
    # time and nowhere else.
    module TimeBucket
      class UnsupportedAdapter < StandardError; end

      # Identifiers are built by Flightdeck, never by a request, but they are
      # still validated before being interpolated so that can never change by
      # accident.
      IDENTIFIER = /\A[a-z_][a-z0-9_]*(\.[a-z_][a-z0-9_]*)?\z/

      class << self
        def adapter_name
          SolidQueue::Record.connection.adapter_name.to_s
        end

        # Normalises the adapter into the three SQL dialects we support.
        def family(name = adapter_name)
          case name.to_s.downcase
          when /postgres/ then :postgresql
          when /mysql|trilogy/ then :mysql
          when /sqlite/ then :sqlite
          else
            raise UnsupportedAdapter,
                  "Flightdeck cannot bucket time on the #{name} adapter. " \
                  "Supported adapters: PostgreSQL, MySQL/Trilogy, SQLite."
          end
        end

        # Seconds since the UTC epoch, as a number the database can do
        # arithmetic on.
        def epoch(column, family: self.family)
          col = identifier!(column)

          case family
          when :postgresql then "EXTRACT(EPOCH FROM #{col})"
          when :mysql then "UNIX_TIMESTAMP(#{col})"
          when :sqlite then "CAST(strftime('%s', #{col}) AS INTEGER)"
          else raise UnsupportedAdapter, "unknown family #{family.inspect}"
          end
        end

        # The epoch second at which `column`'s bucket starts.
        #
        # SQLite gets integer division rather than FLOOR() on purpose: floor() is
        # only available when SQLite is compiled with math functions, and
        # integer division is exact for the post-1970 timestamps we deal with.
        def bucket(column, seconds, family: self.family)
          seconds = interval!(seconds)
          col = identifier!(column)

          case family
          when :postgresql then "FLOOR(EXTRACT(EPOCH FROM #{col}) / #{seconds}) * #{seconds}"
          when :mysql then "FLOOR(UNIX_TIMESTAMP(#{col}) / #{seconds}) * #{seconds}"
          when :sqlite then "(CAST(strftime('%s', #{col}) AS INTEGER) / #{seconds}) * #{seconds}"
          else raise UnsupportedAdapter, "unknown family #{family.inspect}"
          end
        end

        def sql(column, seconds) = Arel.sql(bucket(column, seconds))

        # Seconds between two timestamp columns, for averaging in SQL.
        def elapsed(from_column, to_column, family: self.family)
          "(#{epoch(to_column, family: family)} - #{epoch(from_column, family: family)})"
        end

        def elapsed_sql(from_column, to_column) = Arel.sql(elapsed(from_column, to_column))

        private
          def identifier!(column)
            value = column.to_s
            return value if IDENTIFIER.match?(value)

            raise ArgumentError, "#{column.inspect} is not a plain column identifier"
          end

          def interval!(seconds)
            value = Integer(seconds)
            return value if value.positive?

            raise ArgumentError, "bucket width must be a positive number of seconds"
          end
      end
    end
  end
end
