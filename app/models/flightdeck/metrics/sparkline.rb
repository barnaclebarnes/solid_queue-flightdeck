# frozen_string_literal: true

module Flightdeck
  module Metrics
    # Tiny area+line for the queue cards and the Overview mini-table.
    class Sparkline
      WIDTH = 100
      HEIGHT = 30

      attr_reader :values

      def initialize(values)
        @values = Array(values).map(&:to_i)
      end

      def width = WIDTH
      def height = HEIGHT
      def any? = values.any? && values.max.positive?

      def coordinates
        @coordinates ||= begin
          max = [ values.max.to_i, 1 ].max
          step = values.size > 1 ? WIDTH.to_f / (values.size - 1) : WIDTH.to_f

          values.each_with_index.map do |value, index|
            { x: (index * step).round(2),
              y: (HEIGHT - 2 - ((value.to_f / max) * (HEIGHT - 4))).round(2) }
          end
        end
      end

      def line_path
        coordinates.each_with_index.map { |c, i| "#{i.zero? ? "M" : "L"} #{c[:x]} #{c[:y]}" }.join(" ")
      end

      def area_path
        return "" if coordinates.empty?

        "#{line_path} L #{coordinates.last[:x]} #{HEIGHT} L #{coordinates.first[:x]} #{HEIGHT} Z"
      end

      def last_point = coordinates.last
    end
  end
end
