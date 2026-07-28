# frozen_string_literal: true

module Flightdeck
  # Deliberately not an ApplicationController subclass: assets are immutable,
  # digest-addressed and carry no data, so they are served without auth and
  # without the cost of the full ActionController::Base stack.
  class AssetsController < ActionController::Metal
    include ActionController::Head

    CACHE_CONTROL = "public, max-age=31536000, immutable"

    def show
      entry = Flightdeck::Assets.find(params[:name])
      return head(:not_found) unless entry

      etag = %("#{entry["digest"]}")
      headers["Cache-Control"] = CACHE_CONTROL
      headers["ETag"] = etag
      headers["X-Content-Type-Options"] = "nosniff"

      return head(:not_modified) if stale_etag_match?(etag)

      body = Flightdeck::Assets.read(params[:name])
      return head(:not_found) unless body

      headers["Content-Type"] = entry["content_type"] || Flightdeck::Assets.content_type_for(entry["file"])
      self.status = 200
      self.response_body = body
    end

    private
      def stale_etag_match?(etag)
        matches = request.get_header("HTTP_IF_NONE_MATCH")
        return false if matches.nil?

        matches == "*" || matches.split(",").any? { |candidate| candidate.strip == etag }
      end
  end
end
