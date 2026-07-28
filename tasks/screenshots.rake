# frozen_string_literal: true

# Captures the README screenshots from a real browser against seeded data.
#
#   bundle exec rake screenshots
#
# Runs in the test environment against a throwaway database, so a developer's
# development data is never touched. Every shot stamps its theme explicitly
# rather than relying on the machine's OS preference, so the output is identical
# on any workstation.

module FlightdeckScreenshots
  OUTPUT_DIR = File.expand_path("../docs/screenshots", __dir__)
  WIDTH = 1440
  HEIGHT = 900
  # Shots are cropped to their content between these bounds, so a short page
  # does not carry a field of empty background and a long one still ends somewhere.
  MIN_HEIGHT = 520
  MAX_HEIGHT = 1600

  # name => { path:, theme:, fit_content: }
  SHOTS = {
    "overview-dark" => { path: "/flightdeck", theme: "dark", fit_content: true },
    "overview-light" => { path: "/flightdeck", theme: "light", fit_content: true },
    "jobs-failed-dark" => { path: "/flightdeck/jobs?state=failed", theme: "dark", fit_content: true },
    "job-detail-dark" => { path: :first_failed_job, theme: "dark", fit_content: true },
    "queues-dark" => { path: "/flightdeck/queues", theme: "dark", fit_content: true },
    "processes-dark" => { path: "/flightdeck/processes", theme: "dark", fit_content: true }
  }.freeze

  class Runner
    def call
      boot_application
      prepare_database

      FileUtils.mkdir_p(OUTPUT_DIR)
      puts "Capturing #{SHOTS.size} screenshots into docs/screenshots/"

      session = build_session
      begin
        SHOTS.each { |name, shot| capture(session, name, shot) }
      ensure
        session.driver.quit
      end

      puts "Done."
    end

    private
      def boot_application
        ENV["RAILS_ENV"] = "test"
        # No browser can dismiss an HTTP Basic dialog, so the screenshots run
        # against a host that supplies its own open base controller. This has to
        # be set before the engine's controllers are autoloaded.
        ENV["FLIGHTDECK_TEST_BASE_CONTROLLER"] ||= "OpenBaseController"

        require File.expand_path("../test/dummy/config/environment", __dir__)
        require "capybara/dsl"
        require "selenium-webdriver"
      end

      def prepare_database
        ActiveRecord::Schema.verbose = false
        load Rails.root.join("db/schema.rb").to_s
        load Rails.root.join("db/seeds.rb").to_s
      end

      def chrome_binary
        @chrome_binary ||= [
          ENV["CHROME_BIN"],
          "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
          "google-chrome", "google-chrome-stable", "chromium", "chromium-browser"
        ].compact.find do |candidate|
          File.executable?(candidate) || system("command -v #{candidate.shellescape} > /dev/null 2>&1")
        end
      end

      def build_session
        abort "No Chrome found. Install Google Chrome or Chromium, or set CHROME_BIN." unless chrome_binary

        Capybara.server = :puma, { Silent: true }
        Capybara.default_max_wait_time = 10
        Capybara.register_driver(:flightdeck_screenshots) { |app| selenium_driver(app) }

        Capybara::Session.new(:flightdeck_screenshots, Rails.application)
      end

      def selenium_driver(app)
        options = Selenium::WebDriver::Chrome::Options.new
        options.binary = chrome_binary if File.executable?(chrome_binary)
        %W[
          --headless=new --hide-scrollbars --force-device-scale-factor=1
          --window-size=#{WIDTH},#{HEIGHT} --no-sandbox --disable-dev-shm-usage --disable-gpu
        ].each { |argument| options.add_argument(argument) }

        Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
      end

      def capture(session, name, shot)
        session.visit(resolve(shot[:path]))
        settle(session, shot[:theme])
        resize(session, shot[:fit_content])
        settle(session, shot[:theme])

        file = File.join(OUTPUT_DIR, "#{name}.png")
        session.save_screenshot(file)

        puts format("  %-18s %-34s %6.1f KB", name, resolve(shot[:path]), File.size(file) / 1024.0)
      end

      def resolve(path)
        return path unless path == :first_failed_job

        @failed_job_path ||= begin
          execution = SolidQueue::FailedExecution.order(created_at: :desc).first
          abort "no failed job in the seeded data" unless execution

          "/flightdeck/jobs/#{execution.job_id}"
        end
      end

      # Stamps the theme, switches polling off so no frame reloads mid-capture,
      # and freezes animation so the same pixels come out every run.
      def settle(session, theme)
        session.execute_script(<<~JS, theme)
          const theme = arguments[0];
          document.documentElement.setAttribute('data-theme', theme);
          document.documentElement.setAttribute('data-fd-live', 'off');
          if (!document.getElementById('fd-screenshot-style')) {
            const style = document.createElement('style');
            style.id = 'fd-screenshot-style';
            style.textContent =
              '*, *::before, *::after { animation: none !important; transition: none !important; }';
            document.head.appendChild(style);
          }
        JS

        session.assert_selector(".fd-app", wait: 10)
        sleep 0.5
      end

      # Sizes the *viewport*, not the window: the browser frame is worth ~140px,
      # so resizing the window to the content height leaves the page clipped.
      def resize(session, fit_content)
        set_viewport(session, HEIGHT)
        return unless fit_content

        set_viewport(session, content_height(session).clamp(MIN_HEIGHT, MAX_HEIGHT))
      end

      # Where the page's content actually ends. The shell is `min-height: 100vh`,
      # so its own height only ever reports the viewport back at us — the last
      # panel's bottom edge is the real answer.
      def content_height(session)
        session.evaluate_script(<<~JS).to_i
          (function () {
            const content = document.querySelector('.fd-content');
            const last = content && content.lastElementChild;
            const box = (last || content).getBoundingClientRect();
            return Math.ceil(box.bottom + window.scrollY + 18);
          })()
        JS
      end

      def set_viewport(session, height)
        2.times do
          inner = session.evaluate_script("window.innerHeight").to_i
          outer = session.current_window.size.last.to_i
          frame = [ outer - inner, 0 ].max

          break if inner == height

          session.current_window.resize_to(WIDTH, height + frame)
          sleep 0.3
        end
      end
  end
end

desc "Capture the README screenshots with headless Chrome (test env, throwaway database)"
task :screenshots do
  require "fileutils"
  FlightdeckScreenshots::Runner.new.call
end
