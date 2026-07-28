# frozen_string_literal: true

require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "active_job/railtie"

Bundler.require(*Rails.groups)

require "flightdeck"
require "fileutils"

# These are all gitignored working directories. Committed .keep files make a
# plain checkout complete, but creating them here too means the dummy app boots
# even from a tree where they were cleaned away — the logger below opens a file
# and would otherwise take the whole suite down with Errno::ENOENT.
%w[log tmp storage].each do |directory|
  FileUtils.mkdir_p(File.expand_path("../#{directory}", __dir__))
end

module Dummy
  class Application < Rails::Application
    config.load_defaults Rails::VERSION::STRING.to_f

    config.root = File.expand_path("..", __dir__)

    # Flipped by the second CI leg to prove the engine-local middleware carries
    # cookies, session and flash into a host that has none of them.
    config.api_only = ENV["FLIGHTDECK_TEST_API_ONLY"].present?

    config.eager_load = false
    config.consider_all_requests_local = true
    config.secret_key_base = "flightdeck-dummy-secret-key-base-flightdeck-dummy-secret-key-base"

    # The host of a Solid Queue dashboard uses Solid Queue: this is what makes
    # "Run now" on a recurring task actually write a solid_queue_jobs row.
    config.active_job.queue_adapter = :solid_queue
    config.logger = ActiveSupport::Logger.new(File.expand_path("../log/dummy.log", __dir__))
    config.log_level = :warn
  end
end
