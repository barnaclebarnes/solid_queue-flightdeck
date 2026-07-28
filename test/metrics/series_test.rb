# frozen_string_literal: true

require "test_helper"

class Flightdeck::Metrics::SeriesTest < ActiveSupport::TestCase
  Series = Flightdeck::Metrics::Series

  # A fixed instant, on an exact hour, so bucket boundaries are unambiguous.
  NOW = Time.utc(2026, 7, 27, 15, 0, 0)

  # --- windows --------------------------------------------------------------

  test "the three windows have the documented bucket widths and counts" do
    assert_equal [ 5.minutes.to_i, 12 ], window_shape("1h")
    assert_equal [ 1.hour.to_i, 24 ], window_shape("24h")
    assert_equal [ 6.hours.to_i, 28 ], window_shape("7d")
  end

  test "an unknown range falls back to the default window" do
    assert_equal "24h", Series.window_for("nonsense").key
    assert_equal "24h", Series.window_for(nil).key
    assert_equal "1h", Series.window_for("1h").key
  end

  test "buckets are aligned to absolute epoch multiples, not to now" do
    series = Series.new(window: "24h", now: Time.utc(2026, 7, 27, 15, 37, 12))

    assert series.buckets.all? { |bucket| (bucket % 1.hour.to_i).zero? },
           "every bucket should start on the hour"
    assert_equal Time.utc(2026, 7, 27, 15).to_i, series.buckets.last
    assert_equal 24, series.buckets.size
  end

  # --- throughput -----------------------------------------------------------

  test "throughput separates succeeded from failed, per bucket" do
    create_finished_job(finished_at: NOW - 30.minutes)
    create_finished_job(finished_at: NOW - 30.minutes)
    create_finished_job(finished_at: NOW - 90.minutes)
    create_failed_at(NOW - 30.minutes)

    points = Series.new(window: "24h", now: NOW).throughput.index_by(&:at)

    assert_equal 2, points[NOW - 1.hour].succeeded
    assert_equal 1, points[NOW - 1.hour].failed
    assert_equal 1, points[NOW - 2.hours].succeeded
    assert_equal 0, points[NOW - 2.hours].failed
  end

  test "every bucket is present even when nothing happened in it" do
    create_finished_job(finished_at: NOW - 30.minutes)

    points = Series.new(window: "24h", now: NOW).throughput

    assert_equal 24, points.size
    assert_equal 24, points.map(&:at).uniq.size
    assert_equal 1, points.sum(&:succeeded)
    assert points.count { |p| p.total.zero? } == 23
  end

  test "an empty database yields a full series of zeroes rather than nothing" do
    points = Series.new(window: "24h", now: NOW).throughput

    assert_equal 24, points.size
    assert points.all? { |point| point.total.zero? }
    assert Series.new(window: "24h", now: NOW).empty?
  end

  test "rows outside the window are excluded" do
    create_finished_job(finished_at: NOW - 30.minutes)
    create_finished_job(finished_at: NOW - 40.hours)

    series = Series.new(window: "24h", now: NOW)

    assert_equal 1, series.total_succeeded
  end

  test "a row on the leading edge of the window is included" do
    series = Series.new(window: "24h", now: NOW)
    create_finished_job(finished_at: series.starts_at)

    assert_equal 1, Series.new(window: "24h", now: NOW).total_succeeded
  end

  test "the one-hour window buckets into five-minute slots" do
    create_finished_job(finished_at: NOW - 7.minutes)
    create_finished_job(finished_at: NOW - 6.minutes)

    points = Series.new(window: "1h", now: NOW).throughput

    assert_equal 12, points.size
    assert_equal 2, points.sum(&:succeeded)
    assert_equal 2, points.find { |p| p.at == NOW - 10.minutes }.succeeded
  end

  test "the seven-day window buckets into six-hour slots" do
    create_finished_job(finished_at: NOW - 2.days)

    points = Series.new(window: "7d", now: NOW).throughput

    assert_equal 28, points.size
    assert_equal 1, points.sum(&:succeeded)
  end

  # --- completion time ------------------------------------------------------

  test "completion time averages enqueue-to-finish per bucket" do
    create_job(created_at: NOW - 90.minutes, finished_at: NOW - 89.minutes)  # 60s
    create_job(created_at: NOW - 80.minutes, finished_at: NOW - 78.minutes)  # 120s

    points = Series.new(window: "24h", now: NOW).completion_time.index_by(&:at)

    assert_in_delta 90, points[NOW - 2.hours].seconds, 0.5
  end

  test "buckets with nothing finished are nil, not zero" do
    create_job(created_at: NOW - 30.minutes, finished_at: NOW - 29.minutes)

    points = Series.new(window: "24h", now: NOW).completion_time

    assert_equal 24, points.size
    assert_equal 1, points.count { |point| !point.seconds.nil? }
    assert points.count(&:blank?) == 23, "an unmeasured bucket must not read as zero seconds"
  end

  test "completion time on an empty database is all gaps and does not raise" do
    points = Series.new(window: "7d", now: NOW).completion_time

    assert_equal 28, points.size
    assert points.all?(&:blank?)
  end

  # --- retention honesty ----------------------------------------------------

  test "reports the window as truncated when retention is shorter than it" do
    with_retention(1.day) do
      refute Series.new(window: "1h", now: NOW).truncated_by_retention?
      refute Series.new(window: "24h", now: NOW).truncated_by_retention?
      assert Series.new(window: "7d", now: NOW).truncated_by_retention?
    end
  end

  test "no truncation claim when finished jobs are not preserved at all" do
    original = SolidQueue.preserve_finished_jobs
    SolidQueue.preserve_finished_jobs = false

    refute Series.new(window: "7d", now: NOW).truncated_by_retention?
  ensure
    SolidQueue.preserve_finished_jobs = original
  end

  # --- sparklines -----------------------------------------------------------

  test "queue sparklines come back per queue, one slot per hour" do
    create_finished_job(queue_name: "critical", finished_at: NOW - 30.minutes)
    create_finished_job(queue_name: "critical", finished_at: NOW - 30.minutes)
    create_finished_job(queue_name: "low", finished_at: NOW - 3.hours)

    lines = Series.queue_sparklines(now: NOW)

    assert_equal Series::SPARKLINE_HOURS, lines["critical"].size
    # NOW is exactly 15:00, so the final slot is the 15:00 hour, which is still
    # empty; the two jobs finished at 14:30 belong to the slot before it.
    assert_equal 0, lines["critical"].last
    assert_equal 2, lines["critical"][-2]
    assert_equal 3, lines.sum { |_, values| values.sum }
    assert_nil lines["never-seen"]
  end

  test "sparkline slots outside the window are dropped rather than misplaced" do
    create_finished_job(queue_name: "critical", finished_at: NOW - 40.hours)

    lines = Series.queue_sparklines(now: NOW)

    assert_equal 0, lines.values.sum(&:sum)
  end

  private
    def window_shape(key)
      window = Series.window_for(key)
      [ window.bucket_seconds, window.bucket_count ]
    end

    def create_failed_at(time)
      create_failed_job.tap do |job|
        SolidQueue::FailedExecution.where(job_id: job.id).update_all(created_at: time)
      end
    end

    def with_retention(duration)
      original = SolidQueue.clear_finished_jobs_after
      SolidQueue.clear_finished_jobs_after = duration
      yield
    ensure
      SolidQueue.clear_finished_jobs_after = original
    end
end
