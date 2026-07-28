# frozen_string_literal: true

module Flightdeck
  # Turns a job's stored payload into the one part of it a list row wants: the
  # actual job arguments.
  #
  # What Solid Queue stores is the whole ActiveJob serialization —
  # `{"job_class":…,"job_id":…,"queue_name":…,"arguments":[…],…}` — so a raw
  # preview is almost entirely boilerplate that is identical on every row. The
  # job detail page still shows the full payload, where it is genuinely useful.
  #
  # The input is a byte prefix truncated by SQL, so the JSON is usually cut off
  # mid-value. Parsing is lenient by design: extract what is there, and fall
  # back to the raw prefix rather than showing nothing.
  class ArgumentsPreview
    KEY = /"arguments"\s*:\s*/
    ELLIPSIS = "…"

    def self.format(raw, length: 120)
      new(raw).to_s(length: length)
    end

    def initialize(raw)
      @raw = raw.to_s
    end

    def to_s(length: 120)
      value = extract
      return "" if value.blank?

      value.gsub(/\s+/, " ").strip.truncate(length, omission: ELLIPSIS)
    end

    private
      attr_reader :raw

      def extract
        return "" if raw.blank?

        from_parsed_payload || from_truncated_payload || raw
      end

      # The happy path: the prefix happened to contain the whole payload.
      def from_parsed_payload
        parsed = JSON.parse(raw)
        return nil unless parsed.is_a?(Hash) && parsed.key?("arguments")

        JSON.generate(parsed["arguments"])
      rescue JSON::ParserError
        nil
      end

      # The usual path: the payload was cut off, so walk the arguments value
      # ourselves and take as much of it as survived.
      def from_truncated_payload
        match = KEY.match(raw)
        return nil unless match

        balanced_prefix(raw[match.end(0)..].to_s)
      end

      # Reads one JSON value from the front of `text`, stopping either when it
      # closes cleanly or when the string runs out mid-value.
      def balanced_prefix(text)
        return nil if text.empty?

        depth = 0
        in_string = false
        escaped = false

        text.each_char.with_index do |char, index|
          if escaped
            escaped = false
          elsif char == "\\"
            escaped = true
          elsif char == '"'
            in_string = !in_string
          elsif !in_string
            case char
            when "[", "{" then depth += 1
            when "]", "}"
              depth -= 1
              return text[0..index] if depth.zero?
            when ","
              # A top-level comma means the arguments value ended and the next
              # payload key has begun.
              return text[0...index] if depth.zero?
            end
          end
        end

        "#{text}#{ELLIPSIS}"
      end
  end
end
