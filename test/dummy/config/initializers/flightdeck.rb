# frozen_string_literal: true

if ENV["FLIGHTDECK_TEST_BASE_CONTROLLER"].present?
  Flightdeck.configure do |config|
    config.base_controller_class = ENV["FLIGHTDECK_TEST_BASE_CONTROLLER"]
  end
end
