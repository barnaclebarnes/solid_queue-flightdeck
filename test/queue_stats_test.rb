# frozen_string_literal: true

require "test_helper"

class Flightdeck::QueueStatsTest < ActiveSupport::TestCase
  test "reports depth, oldest-ready latency and hourly rate per queue" do
    create_ready_job(queue_name: "critical", created_at: 30.seconds.ago)
    create_ready_job(queue_name: "critical", created_at: 5.seconds.ago)
    create_ready_job(queue_name: "low", created_at: 2.seconds.ago)
    create_finished_job(queue_name: "critical", finished_at: 10.minutes.ago)
    create_finished_job(queue_name: "critical", finished_at: 20.minutes.ago)

    critical = Flightdeck::QueueStats.new.find("critical")

    assert_equal 2, critical.depth
    assert_in_delta 30, critical.latency, 5
    assert_equal 2, critical.rate_per_hour
  end

  test "latency is nil rather than zero when nothing is waiting" do
    create_finished_job(queue_name: "idle", finished_at: 1.minute.ago)

    row = Flightdeck::QueueStats.new.find("idle")

    assert_equal 0, row.depth
    assert_nil row.latency, "an empty queue has no latency to report"
  end

  test "completions outside the rate window are not counted" do
    create_finished_job(queue_name: "default", finished_at: 5.minutes.ago)
    create_finished_job(queue_name: "default", finished_at: 3.hours.ago)

    assert_equal 1, Flightdeck::QueueStats.new.find("default").rate_per_hour
  end

  test "a paused queue reports as paused with how long it has been paused" do
    create_ready_job(queue_name: "webhooks")
    SolidQueue::Pause.create!(queue_name: "webhooks", created_at: 42.minutes.ago)

    row = Flightdeck::QueueStats.new.find("webhooks")

    assert row.paused?
    assert_in_delta 42.minutes, row.paused_for, 30
  end

  test "a queue that exists only as a pause is still listed" do
    SolidQueue::Pause.create!(queue_name: "ghost", created_at: 1.minute.ago)

    row = Flightdeck::QueueStats.new.find("ghost")

    assert_not_nil row, "a paused queue with no jobs must not disappear from the page"
    assert row.paused?
    assert_equal 0, row.depth
  end

  test "queues are listed once each, in name order" do
    create_ready_job(queue_name: "zulu")
    create_ready_job(queue_name: "alpha")
    create_finished_job(queue_name: "alpha", finished_at: 1.minute.ago)
    SolidQueue::Pause.create!(queue_name: "alpha", created_at: 1.minute.ago)

    names = Flightdeck::QueueStats.new.rows.map(&:name)

    assert_equal %w[alpha zulu], names
  end

  test "reports whether anything is paused at all" do
    create_ready_job(queue_name: "default")

    refute Flightdeck::QueueStats.new.any_paused?

    SolidQueue::Queue.new("default").pause
    assert Flightdeck::QueueStats.new.any_paused?
  end
end
