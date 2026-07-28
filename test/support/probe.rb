# frozen_string_literal: true

# Runs in a fresh process (see test/boot_test.rb) so that it can boot the dummy
# app under configuration that cannot be changed once Zeitwerk has loaded the
# engine's controllers. Prints a single JSON line on stdout.

require "json"

result = { "booted" => false }

begin
  require_relative "../dummy/config/environment"
  result["booted"] = true
  result["adapter_touched"] = ActiveRecord::Base.connection_pool.connected?
  result["base_controller"] = Flightdeck::ApplicationController.superclass.name

  if ENV["FLIGHTDECK_PROBE_REQUEST"].present?
    require "rack/test"

    session = Rack::Test::Session.new(Rails.application)

    session.get "/flightdeck"
    result["without_host_token"] = session.last_response.status

    session.get "/flightdeck", {}, { "HTTP_X_HOST_TOKEN" => "hosted" }
    result["with_host_token"] = session.last_response.status
    result["with_host_token_body_has_shell"] = session.last_response.body.include?("fd-app")
  end
rescue Exception => error # rubocop:disable Lint/RescueException
  result["error"] = "#{error.class}: #{error.message}"
  result["backtrace"] = error.backtrace&.first(5)
end

puts JSON.generate(result)
