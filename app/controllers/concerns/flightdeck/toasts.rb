# frozen_string_literal: true

module Flightdeck
  # Shared response shape for the small member actions on the infrastructure
  # pages: a toast plus a re-rendered frame over Turbo Streams, or a redirect
  # carrying the same sentence in the flash when Turbo is not in play.
  module Toasts
    extend ActiveSupport::Concern

    private
      def toast(message, level: :success)
        @toast = { message: message, level: level, continuable: false }
      end

      def respond_with_toast(template, fallback:)
        respond_to do |format|
          format.turbo_stream { render template, formats: :turbo_stream }
          format.any do
            flash[@toast[:level] == :error ? :alert : :notice] = @toast[:message]
            redirect_to fallback
          end
        end
      end
  end
end
