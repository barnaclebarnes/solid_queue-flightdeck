# frozen_string_literal: true

module Flightdeck
  module MetricsHelper
    TREND_GLYPHS = { up: "▲", down: "▼", flat: "▪" }.freeze

    def fd_poll_ms = (Flightdeck.config.poll_interval.to_f * 1000).round
    def fd_chart_poll_ms = (Flightdeck.config.chart_poll_interval.to_f * 1000).round

    def fd_poll_seconds = Flightdeck.config.poll_interval.to_i

    def fd_trend_glyph(trend) = TREND_GLYPHS.fetch(trend.to_sym, TREND_GLYPHS[:flat])

    # --- topbar clock ---------------------------------------------------------
    #
    # Rendered server-side so the clock is right before JavaScript runs, and
    # driven by an offset so it keeps showing the configured display timezone
    # rather than the viewer's.

    def fd_display_zone
      ActiveSupport::TimeZone[Flightdeck.config.display_timezone] || ActiveSupport::TimeZone["UTC"]
    end

    def fd_clock_now = "#{Time.current.in_time_zone(fd_display_zone).strftime("%H:%M:%S")} #{fd_zone_label}"

    def fd_zone_label
      zone = fd_display_zone
      zone.name == "UTC" ? "UTC" : Time.current.in_time_zone(zone).strftime("%Z")
    end

    def fd_zone_offset_seconds
      fd_display_zone.now.utc_offset
    end

    # Colour follows whether the movement is good news, not which way the arrow
    # points: more failures is an "up" arrow but bad news.
    def fd_delta_class(tile)
      return "flat" if tile.trend.to_sym == :flat

      tile.good ? "up" : "down"
    end

    def fd_depth_share(depth, max)
      return 0 if max.to_i.zero?

      [ (depth.to_f / max * 100).round, 100 ].min
    end
  end
end
