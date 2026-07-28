# frozen_string_literal: true

require "test_helper"

begin
  require "capybara/rails"
  require "capybara/minitest"
  require "selenium-webdriver"
  SYSTEM_TEST_DEPENDENCIES = true
rescue LoadError
  SYSTEM_TEST_DEPENDENCIES = false
end

# Headless-Chrome tests for the few behaviours that only exist in a browser:
# Turbo frame navigation, the theme stamp, toasts and polling.
#
# They are deliberately out of the fast suite (`rake test:system`) and skip
# themselves with an explanatory message when Chrome is not installed, so a
# checkout without a browser still gets a green `rake test`.
class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  USERNAME = "pilot"
  PASSWORD = "correct-horse-battery"

  class << self
    def chrome_available?
      return @chrome_available if defined?(@chrome_available)

      @chrome_available = SYSTEM_TEST_DEPENDENCIES && chrome_binary.present?
    end

    def chrome_binary
      candidates = [
        ENV["CHROME_BIN"],
        "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
        "google-chrome", "google-chrome-stable", "chromium", "chromium-browser"
      ].compact

      candidates.find do |candidate|
        File.executable?(candidate) || system("command -v #{candidate.shellescape} > /dev/null 2>&1")
      end
    end

    def skip_message
      unless SYSTEM_TEST_DEPENDENCIES
        return "capybara/selenium-webdriver are not installed — run `bundle install` with the test group."
      end

      "no Chrome found. Install Google Chrome or Chromium, or set CHROME_BIN, to run system tests."
    end

    # A browser cannot dismiss an HTTP Basic dialog, so system tests run against
    # a host that brings its own (open) authentication. That has to be in place
    # before the engine's controllers are autoloaded, which is why `rake
    # test:system` sets it in the environment rather than a test setting it here.
    def host_base_controller
      ENV["FLIGHTDECK_TEST_BASE_CONTROLLER"].presence
    end
  end

  if chrome_available?
    driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1000 ] do |options|
      options.binary = chrome_binary if chrome_binary && File.executable?(chrome_binary)
      options.add_argument("--no-sandbox")
      options.add_argument("--disable-dev-shm-usage")
      options.add_argument("--disable-gpu")
    end
  end

  def before_setup
    super
    skip(self.class.skip_message) unless self.class.chrome_available?

    unless self.class.host_base_controller
      skip "run system tests with `rake test:system`, which sets " \
           "FLIGHTDECK_TEST_BASE_CONTROLLER=OpenBaseController before boot."
    end

    # Flightdeck::TestHelpers resets the configuration between tests, but the
    # controllers already inherit from the host's base controller — the config
    # has to stay set or every request would get Flightdeck's own 401 on top.
    Flightdeck.config.base_controller_class = self.class.host_base_controller
  end

  # Waits for a condition instead of sleeping, so the tests stay fast and are
  # not flaky on a slow machine.
  def wait_until(timeout: 8, message: "condition never became true")
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout

    loop do
      result = yield
      return result if result
      flunk(message) if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.1
    end
  end

  def theme_stamp
    page.evaluate_script("document.documentElement.getAttribute('data-theme')")
  end

  def live_state
    page.evaluate_script("document.documentElement.getAttribute('data-fd-live')")
  end

  def background_of(selector)
    page.evaluate_script("getComputedStyle(document.querySelector('#{selector}')).backgroundColor")
  end
end
