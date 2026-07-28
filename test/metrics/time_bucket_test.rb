# frozen_string_literal: true

require "test_helper"

class Flightdeck::Metrics::TimeBucketTest < ActiveSupport::TestCase
  TimeBucket = Flightdeck::Metrics::TimeBucket

  # --- the documented expressions -------------------------------------------
  #
  # These are asserted verbatim because they are the only adapter-specific SQL
  # in the gem: a silent change to one of them would skew every chart on a
  # database this test suite does not otherwise run against.

  test "PostgreSQL buckets with EXTRACT(EPOCH ...)" do
    assert_equal "FLOOR(EXTRACT(EPOCH FROM solid_queue_jobs.finished_at) / 3600) * 3600",
                 TimeBucket.bucket("solid_queue_jobs.finished_at", 3600, family: :postgresql)
  end

  test "MySQL buckets with UNIX_TIMESTAMP" do
    assert_equal "FLOOR(UNIX_TIMESTAMP(solid_queue_jobs.finished_at) / 3600) * 3600",
                 TimeBucket.bucket("solid_queue_jobs.finished_at", 3600, family: :mysql)
  end

  test "SQLite buckets with integer division on strftime" do
    assert_equal "(CAST(strftime('%s', solid_queue_jobs.finished_at) AS INTEGER) / 3600) * 3600",
                 TimeBucket.bucket("solid_queue_jobs.finished_at", 3600, family: :sqlite)
  end

  test "epoch expressions per adapter" do
    assert_equal "EXTRACT(EPOCH FROM t.c)", TimeBucket.epoch("t.c", family: :postgresql)
    assert_equal "UNIX_TIMESTAMP(t.c)", TimeBucket.epoch("t.c", family: :mysql)
    assert_equal "CAST(strftime('%s', t.c) AS INTEGER)", TimeBucket.epoch("t.c", family: :sqlite)
  end

  test "elapsed subtracts two epochs in the right order" do
    assert_equal "(EXTRACT(EPOCH FROM t.finished_at) - EXTRACT(EPOCH FROM t.created_at))",
                 TimeBucket.elapsed("t.created_at", "t.finished_at", family: :postgresql)
  end

  # --- adapter detection ----------------------------------------------------

  test "recognises the supported adapter names" do
    assert_equal :postgresql, TimeBucket.family("PostgreSQL")
    assert_equal :mysql, TimeBucket.family("Mysql2")
    assert_equal :mysql, TimeBucket.family("Trilogy")
    assert_equal :sqlite, TimeBucket.family("SQLite")
  end

  test "an unknown adapter raises with a message naming what is supported" do
    error = assert_raises(TimeBucket::UnsupportedAdapter) { TimeBucket.family("OracleEnhanced") }

    assert_match(/OracleEnhanced/, error.message)
    assert_match(/PostgreSQL, MySQL\/Trilogy, SQLite/, error.message)
  end

  test "this test run is against a supported adapter" do
    assert_includes %i[postgresql mysql sqlite], TimeBucket.family
  end

  # --- guards ---------------------------------------------------------------

  test "rejects anything that is not a plain column identifier" do
    [ "jobs.finished_at; DROP TABLE x", "NOW()", "a.b.c", "" ].each do |bad|
      assert_raises(ArgumentError, "#{bad.inspect} should be rejected") do
        TimeBucket.bucket(bad, 60, family: :sqlite)
      end
    end
  end

  test "rejects a non-positive bucket width" do
    assert_raises(ArgumentError) { TimeBucket.bucket("t.c", 0, family: :sqlite) }
    assert_raises(ArgumentError) { TimeBucket.bucket("t.c", -60, family: :sqlite) }
    assert_raises(ArgumentError, TypeError) { TimeBucket.bucket("t.c", "sixty", family: :sqlite) }
  end

  # --- behaviour against the real database ----------------------------------

  test "buckets real timestamps to the start of their bucket, in UTC" do
    # 14:05, 14:59 and 15:01 UTC: the first two share an hourly bucket.
    [ "2026-07-27 14:05:30", "2026-07-27 14:59:59", "2026-07-27 15:01:00" ].each do |at|
      create_finished_job(finished_at: Time.utc(*at.split(/[- :]/).map(&:to_i)))
    end

    counts = SolidQueue::Job
      .group(Flightdeck::Metrics::TimeBucket.sql("solid_queue_jobs.finished_at", 3600))
      .count
      .transform_keys(&:to_i)

    assert_equal 2, counts[Time.utc(2026, 7, 27, 14).to_i]
    assert_equal 1, counts[Time.utc(2026, 7, 27, 15).to_i]
  end

  test "bucket boundaries are exact" do
    create_finished_job(finished_at: Time.utc(2026, 7, 27, 14, 0, 0))
    create_finished_job(finished_at: Time.utc(2026, 7, 27, 13, 59, 59))

    counts = SolidQueue::Job
      .group(Flightdeck::Metrics::TimeBucket.sql("solid_queue_jobs.finished_at", 3600))
      .count
      .transform_keys(&:to_i)

    assert_equal 1, counts[Time.utc(2026, 7, 27, 14).to_i]
    assert_equal 1, counts[Time.utc(2026, 7, 27, 13).to_i]
  end

  test "five-minute buckets divide the hour as expected" do
    create_finished_job(finished_at: Time.utc(2026, 7, 27, 14, 3, 0))
    create_finished_job(finished_at: Time.utc(2026, 7, 27, 14, 4, 59))
    create_finished_job(finished_at: Time.utc(2026, 7, 27, 14, 5, 0))

    counts = SolidQueue::Job
      .group(Flightdeck::Metrics::TimeBucket.sql("solid_queue_jobs.finished_at", 300))
      .count
      .transform_keys(&:to_i)

    assert_equal 2, counts[Time.utc(2026, 7, 27, 14, 0).to_i]
    assert_equal 1, counts[Time.utc(2026, 7, 27, 14, 5).to_i]
  end

  test "elapsed measures the real difference between two columns" do
    create_job(created_at: Time.utc(2026, 7, 27, 14, 0, 0), finished_at: Time.utc(2026, 7, 27, 14, 0, 30))

    average = SolidQueue::Job.average(
      Flightdeck::Metrics::TimeBucket.elapsed_sql("solid_queue_jobs.created_at", "solid_queue_jobs.finished_at")
    )

    assert_in_delta 30, average.to_f, 0.01
  end
end
