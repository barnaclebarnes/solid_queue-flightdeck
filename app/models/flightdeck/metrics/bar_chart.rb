# frozen_string_literal: true

module Flightdeck
  module Metrics
    # Succeeded stacked under failed, per bucket.
    class BarChart < Chart
      BAR_GAP = 2
      CORNER = 1.5

      def bars
        points.each_with_index.map do |point, index|
          x = plot_left + (slot_width * index)
          bar_width = [ slot_width - BAR_GAP, 1 ].max

          failed_height = height_for(point.failed)
          succeeded_height = height_for(point.succeeded)
          failed_y = plot_bottom - failed_height - succeeded_height

          {
            x: round(x + (BAR_GAP / 2.0)),
            width: round(bar_width),
            corner: CORNER,
            succeeded: { y: round(plot_bottom - succeeded_height), height: round(succeeded_height) },
            failed: { y: round(failed_y), height: round(failed_height) },
            empty: point.total.zero?,
            title: bar_title(point)
          }
        end
      end

      private
        def raw_max = points.map(&:total).max.to_i

        def height_for(value)
          return 0 if value.to_i.zero? || axis_max.zero?

          # Anything non-zero gets at least a hairline, so a bucket with a
          # single job is visibly different from a bucket with none.
          [ (value.to_f / axis_max) * plot_height, 1.0 ].max
        end

        def bar_title(point)
          "#{full_time(point.at)} · #{number(point.succeeded)} succeeded · #{number(point.failed)} failed"
        end

        def number(value) = ActiveSupport::NumberHelper.number_to_delimited(value.to_i)
    end
  end
end
