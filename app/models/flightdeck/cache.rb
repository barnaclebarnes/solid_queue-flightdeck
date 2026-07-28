# frozen_string_literal: true

module Flightdeck
  # Thin wrapper over Rails.cache for the dashboard's short-lived aggregates.
  #
  # Two things it guarantees:
  #   * it degrades to simply calling the block, so a host running the null
  #     store (or no cache at all) still gets a working dashboard;
  #   * a mutation can ask for fresh numbers via .bypass, so the response to a
  #     retry never shows the counts from before the retry.
  module Cache
    NAMESPACE = "flightdeck"

    class << self
      def fetch(*key_parts, expires_in:, &block)
        store = Rails.cache
        return block.call if store.nil? || expires_in.to_f <= 0

        store.fetch(key_for(key_parts), expires_in: expires_in, force: bypass?, &block)
      rescue StandardError
        # A cache backend that is down must never take the dashboard with it.
        block.call
      end

      # Inside this block every fetch recomputes and rewrites, so a page
      # rendered straight after a mutation reflects it.
      def bypass
        previous = Thread.current[:flightdeck_cache_bypass]
        Thread.current[:flightdeck_cache_bypass] = true
        yield
      ensure
        Thread.current[:flightdeck_cache_bypass] = previous
      end

      def bypass? = Thread.current[:flightdeck_cache_bypass].present?

      def key_for(parts)
        [ NAMESPACE, *Array(parts).flatten.map { |part| normalize(part) } ].join(":")
      end

      private
        def normalize(part)
          case part
          when Hash then part.sort_by { |key, _| key.to_s }.map { |key, value| "#{key}=#{value}" }.join(",")
          when nil then ""
          else part.to_s
          end
        end
    end
  end
end
