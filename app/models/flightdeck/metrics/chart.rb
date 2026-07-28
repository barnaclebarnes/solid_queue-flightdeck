# frozen_string_literal: true

module Flightdeck
  module Metrics
    # Geometry for the server-rendered SVG charts.
    #
    # All the arithmetic lives here so the ERB partials stay readable: they
    # place elements and nothing else. Colours are never computed here either —
    # the partials reference the CSS custom properties, so charts re-theme with
    # the rest of the page and there is no inline colour to get out of step.
    class Chart
      WIDTH = 720
      HEIGHT = 190
      PAD_LEFT = 40
      PAD_RIGHT = 10
      PAD_TOP = 12
      PAD_BOTTOM = 22
      GRID_INTERVALS = 3

      attr_reader :points, :window

      def initialize(points:, window:)
        @points = points
        @window = window
      end

      def width = WIDTH
      def height = HEIGHT
      def plot_left = PAD_LEFT
      def plot_right = WIDTH - PAD_RIGHT
      def plot_top = PAD_TOP
      def plot_bottom = HEIGHT - PAD_BOTTOM
      def plot_width = plot_right - plot_left
      def plot_height = plot_bottom - plot_top
      def empty? = points.empty?

      def gridlines
        (0..GRID_INTERVALS).map do |i|
          value = axis_max * (GRID_INTERVALS - i) / GRID_INTERVALS.to_f
          { y: round(plot_top + (plot_height * i / GRID_INTERVALS.to_f)), value: value, label: format_value(value) }
        end
      end

      # Ticks are placed on bucket boundaries so a label always names a bucket
      # that is actually on screen.
      def x_ticks
        every = [ window.tick_every.to_i, 1 ].max

        points.each_with_index.filter_map do |point, index|
          next unless (index % every).zero?

          { x: round(tick_x(index)), label: format_time(point.at, window.tick_format) }
        end
      end

      def axis_max
        @axis_max ||= nice_ceiling(raw_max)
      end

      def format_time(time, pattern)
        time.in_time_zone(Flightdeck.config.display_timezone).strftime(pattern)
      end

      def full_time(time)
        format_time(time, "%Y-%m-%d %H:%M")
      end

      private
        def raw_max = 0

        def tick_x(index)
          plot_left + (slot_width * index) + (slot_width / 2.0)
        end

        def slot_width
          @slot_width ||= points.empty? ? plot_width : plot_width / points.size.to_f
        end

        def y_for(value)
          return plot_bottom if axis_max.zero?

          plot_bottom - ((value.to_f / axis_max) * plot_height)
        end

        # A round number at or above the data's peak, so gridline labels are
        # readable numbers rather than whatever the maximum happened to be.
        def nice_ceiling(value)
          return 1 if value.nil? || value <= 0

          magnitude = 10**Math.log10(value).floor
          [ 1, 2, 2.5, 5, 10 ].each do |factor|
            candidate = magnitude * factor
            return candidate >= 10 ? candidate.round : candidate if candidate >= value
          end
          value
        end

        def format_value(value)
          case value
          when 0 then "0"
          when 0...1 then value.round(2).to_s
          when 1...1_000 then value < 10 ? value.round(1).to_s.sub(/\.0\z/, "") : value.round.to_s
          when 1_000...1_000_000 then "#{(value / 1_000.0).round(1).to_s.sub(/\.0\z/, "")}k"
          else "#{(value / 1_000_000.0).round(1).to_s.sub(/\.0\z/, "")}M"
          end
        end

        def round(value) = value.round(2)
    end
  end
end
