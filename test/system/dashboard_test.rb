# frozen_string_literal: true

require "application_system_test_case"

class Flightdeck::DashboardSystemTest < ApplicationSystemTestCase
  # Found by its accessible label rather than its text: the toggle is icon-only.
  def theme_button
    find("button[aria-label^='Switch to ']")
  end

  def toggle_theme
    theme_button.click
  end

  def visible_theme_icons
    page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll('.fd-theme-toggle svg'))
           .filter(function (icon) { return getComputedStyle(icon).display !== 'none' }).length
    JS
  end

  # Regression for the "Content missing" bug: a job link lives inside the
  # polling #fd-jobs frame, and its destination has no such frame. Without an
  # explicit escape, Turbo swaps "Content missing" into the frame instead of
  # navigating the page.
  test "clicking through from the overview to a job detail page" do
    create_ready_job(class_name: "SearchIndexJob", queue_name: "critical")
    create_finished_job(queue_name: "critical", finished_at: 10.minutes.ago)

    visit "/flightdeck"
    assert_selector ".fd-tile", count: 6

    within("#fd-overview-queues") { click_link "View all" }
    assert_current_path "/flightdeck/queues"

    visit "/flightdeck/jobs"
    click_link "SearchIndexJob"

    assert_selector ".fd-jd-head h2", text: "SearchIndexJob"
    assert_no_text "Content missing"
    assert_match %r{/flightdeck/jobs/\d+}, current_path
  end

  test "job links in the failed list open the detail page too" do
    create_failed_job(class_name: "Billing::ChargeSubscriptionJob", exception_class: "Stripe::RateLimitError")

    visit "/flightdeck/jobs?state=failed"
    click_link "Billing::ChargeSubscriptionJob"

    assert_selector ".fd-error-box", text: "Stripe::RateLimitError"
    assert_no_text "Content missing"
  end

  # Regression for the theme bug: the stamp has to reach the shell, not just the
  # content area, in both directions.
  test "the theme toggle restyles the whole shell, sidebar included" do
    visit "/flightdeck"

    sidebar_before = background_of(".fd-side")
    topbar_before = background_of(".fd-topbar")

    toggle_theme
    assert_includes %w[light dark], theme_stamp

    wait_until(message: "the sidebar background never changed") { background_of(".fd-side") != sidebar_before }
    refute_equal topbar_before, background_of(".fd-topbar"), "the topbar must follow the theme too"

    # And back again, so neither direction is a one-way trip.
    stamped = theme_stamp
    toggle_theme
    wait_until(message: "the stamp never flipped back") { theme_stamp != stamped }
    wait_until(message: "the sidebar never returned") { background_of(".fd-side") == sidebar_before }
  end

  test "the theme toggle is an icon button whose label names what clicking does" do
    visit "/flightdeck"

    # The label has to describe the *action*, and stay true after toggling.
    label_before = theme_button[:"aria-label"]
    assert_match(/\ASwitch to (light|dark) theme\z/, label_before)
    assert_equal theme_stamp == "dark" ? "Switch to light theme" : "Switch to dark theme", label_before

    # Icon only: no text, and exactly one of the two icons visible.
    assert_empty theme_button.text.strip
    assert_equal 1, visible_theme_icons, "exactly one of the sun/moon icons should be visible"

    toggle_theme
    wait_until(message: "the aria-label never followed the theme") { theme_button[:"aria-label"] != label_before }

    assert_equal theme_stamp == "dark" ? "Switch to light theme" : "Switch to dark theme",
                 theme_button[:"aria-label"]
    assert_equal 1, visible_theme_icons, "the icon should have swapped, not doubled up"
  end

  test "the theme choice survives a page navigation" do
    visit "/flightdeck"
    toggle_theme
    chosen = theme_stamp

    visit "/flightdeck/queues"

    assert_equal chosen, theme_stamp
  end

  test "retrying a failed job from the list shows a toast and drops the row" do
    job = create_failed_job(class_name: "WebhookDeliveryJob")

    visit "/flightdeck/jobs?state=failed"
    assert_selector "#fd-job-#{job.id}"

    accept_confirm { find("#fd-job-#{job.id}").click_link("Retry") }

    assert_selector "#fd-toasts .fd-toast", text: "Retried job ##{job.id}"
    assert_no_selector "#fd-job-#{job.id}"
    assert SolidQueue::ReadyExecution.exists?(job_id: job.id), "the job should be ready again"
  end

  test "the LIVE switch pauses and resumes polling" do
    create_ready_job

    visit "/flightdeck/jobs?state=ready"
    assert_selector "turbo-frame#fd-jobs"

    # Polling starts on: the frame acquires a src on its first tick.
    assert_equal "on", live_state

    find(".fd-live").click
    assert_equal "off", live_state
    assert_selector ".fd-live", text: "PAUSED"

    # While paused a new job must not appear on its own.
    create_ready_job(class_name: "AppearsWhilePausedJob")
    sleep 1.5
    assert_no_text "AppearsWhilePausedJob"

    # Resuming refreshes immediately rather than waiting out an interval.
    find(".fd-live").click
    assert_equal "on", live_state
    assert_text "AppearsWhilePausedJob"
  end

  test "the topbar clock ticks" do
    visit "/flightdeck"

    first = find(".fd-clock").text
    assert_match(/\A\d{2}:\d{2}:\d{2} \w+\z/, first)

    wait_until(timeout: 4, message: "the clock never advanced") { find(".fd-clock").text != first }
  end

  test "list rows show job arguments rather than the ActiveJob envelope" do
    create_ready_job(class_name: "SearchIndexJob",
                     arguments: { "arguments" => [ { "model" => "Product", "id" => 41_230 } ] })

    visit "/flightdeck/jobs?state=ready"

    assert_selector ".args", text: "Product"
    assert_no_selector ".args", text: "job_class"
  end
end
