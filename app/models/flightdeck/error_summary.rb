# frozen_string_literal: true

module Flightdeck
  # A failed execution's `error` column is JSON that can run to many kilobytes
  # once a backtrace is in it. List views only ever read a bounded prefix of it,
  # which means the JSON is usually truncated mid-string — so parse when we can
  # and fall back to scanning for the two fields we need.
  class ErrorSummary
    UNKNOWN = "UnknownError"

    attr_reader :exception_class, :message

    def self.parse(raw)
      new(raw)
    end

    def self.none
      new(nil)
    end

    def initialize(raw)
      @exception_class, @message = extract(raw)
    end

    def present?
      exception_class.present?
    end

    def group_key
      exception_class.presence || UNKNOWN
    end

    def to_s
      return "" unless present?

      message.present? ? "#{exception_class}: #{message}" : exception_class
    end

    private
      def extract(raw)
        return [ nil, nil ] if raw.blank?

        parsed = safe_parse(raw)
        return [ parsed["exception_class"].presence, parsed["message"].to_s ] if parsed.is_a?(Hash)

        [
          raw[/"exception_class"\s*:\s*"((?:[^"\\]|\\.)*)"/, 1]&.then { |value| unescape(value) },
          raw[/"message"\s*:\s*"((?:[^"\\]|\\.)*)"/, 1]&.then { |value| unescape(value) }.to_s
        ]
      end

      def safe_parse(raw)
        JSON.parse(raw)
      rescue JSON::ParserError
        nil
      end

      def unescape(value)
        JSON.parse(%("#{value}"))
      rescue JSON::ParserError
        value
      end
  end
end
