# frozen_string_literal: true

require "test_helper"
require "open3"

class Flightdeck::BootTest < ActiveSupport::TestCase
  PROBE = File.expand_path("support/probe.rb", __dir__)

  test "the engine boots without ever touching the database" do
    result = probe(
      "DATABASE_URL" => "sqlite3:/flightdeck-does-not-exist/nowhere.sqlite3"
    )

    assert result["booted"], "dummy app failed to boot: #{result["error"]} #{result["backtrace"]}"
    refute result["adapter_touched"], "an initializer opened a database connection at boot"
  end

  test "a configured base_controller_class becomes the superclass and its filters run" do
    result = probe(
      "FLIGHTDECK_TEST_BASE_CONTROLLER" => "HostBaseController",
      "FLIGHTDECK_PROBE_REQUEST" => "1"
    )

    assert result["booted"], "dummy app failed to boot: #{result["error"]} #{result["backtrace"]}"
    assert_equal "HostBaseController", result["base_controller"]

    assert_equal 403, result["without_host_token"],
                 "the host's own before_action must be able to reject the request"
    assert_equal 200, result["with_host_token"],
                 "Flightdeck must not add its own 401 on top of host authentication"
    assert result["with_host_token_body_has_shell"], "the dashboard shell did not render"
  end

  test "without a base controller the engine still refuses unauthenticated requests" do
    result = probe("FLIGHTDECK_PROBE_REQUEST" => "1")

    assert result["booted"], "dummy app failed to boot: #{result["error"]} #{result["backtrace"]}"
    assert_equal "ActionController::Base", result["base_controller"]
    assert_equal 401, result["without_host_token"]
    assert_equal 401, result["with_host_token"]
  end

  private
    def probe(env = {})
      base = {
        "RAILS_ENV" => "test",
        "FLIGHTDECK_USERNAME" => nil,
        "FLIGHTDECK_PASSWORD" => nil,
        "FLIGHTDECK_TEST_BASE_CONTROLLER" => nil,
        "FLIGHTDECK_PROBE_REQUEST" => nil
      }

      stdout, stderr, status = Open3.capture3(base.merge(env), RbConfig.ruby, PROBE)
      assert_predicate status, :success?, "probe exited #{status.exitstatus}:\n#{stderr}"

      JSON.parse(stdout.lines.last.to_s)
    end
end
