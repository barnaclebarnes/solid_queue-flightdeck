# frozen_string_literal: true

require "test_helper"

class Flightdeck::CacheTest < ActiveSupport::TestCase
  NOW = Time.utc(2026, 7, 27, 15, 0, 0)

  test "a repeated series within the TTL issues no further queries" do
    create_finished_job(finished_at: NOW - 30.minutes)

    first = count_queries { Flightdeck::Metrics::Series.new(window: "24h", now: NOW).throughput }
    assert_operator first, :>, 0, "the first call should actually query"

    second = count_queries { Flightdeck::Metrics::Series.new(window: "24h", now: NOW).throughput }
    assert_equal 0, second, "the second call within the TTL should be served from cache"
  end

  test "an expired entry is recomputed" do
    create_finished_job(finished_at: NOW - 30.minutes)

    Flightdeck::Metrics::Series.new(window: "24h", now: NOW).throughput
    Rails.cache.clear

    assert_operator count_queries { Flightdeck::Metrics::Series.new(window: "24h", now: NOW).throughput },
                   :>, 0, "an expired entry must be recomputed"
  end

  test "different windows do not share a cache entry" do
    create_finished_job(finished_at: NOW - 30.minutes)

    Flightdeck::Metrics::Series.new(window: "24h", now: NOW).throughput

    assert_operator count_queries { Flightdeck::Metrics::Series.new(window: "1h", now: NOW).throughput },
                   :>, 0
  end

  test "job counts are cached, and different filters do not collide" do
    create_ready_job(class_name: "AlphaJob")
    create_ready_job(class_name: "BetaJob")

    assert_equal 2, Flightdeck::JobsQuery.new(state: :ready).count
    assert_equal 0, count_queries { Flightdeck::JobsQuery.new(state: :ready).count }

    assert_operator count_queries { Flightdeck::JobsQuery.new(state: :ready, class_name: "AlphaJob").count },
                   :>, 0, "a different filter is a different question"
    assert_equal 1, Flightdeck::JobsQuery.new(state: :ready, class_name: "AlphaJob").count
  end

  test "a stale count is not served inside a bypass block" do
    create_ready_job
    assert_equal 1, Flightdeck::JobsQuery.new(state: :ready).count

    create_ready_job

    assert_equal 1, Flightdeck::JobsQuery.new(state: :ready).count, "still cached"

    Flightdeck::Cache.bypass do
      assert_equal 2, Flightdeck::JobsQuery.new(state: :ready).count
    end

    assert_equal 2, Flightdeck::JobsQuery.new(state: :ready).count,
                 "a bypassed read should have rewritten the entry"
  end

  test "bypass is restored even if the block raises" do
    assert_raises(RuntimeError) { Flightdeck::Cache.bypass { raise "boom" } }

    refute Flightdeck::Cache.bypass?
  end

  # --- degradation ----------------------------------------------------------

  test "works with the null store" do
    with_cache_store(ActiveSupport::Cache::NullStore.new) do
      create_ready_job

      assert_equal 1, Flightdeck::JobsQuery.new(state: :ready).count
      create_ready_job
      assert_equal 2, Flightdeck::JobsQuery.new(state: :ready).count,
                   "with no cache every read must be live"
    end
  end

  test "a cache backend that raises does not take the dashboard down" do
    with_cache_store(ExplodingStore.new) do
      create_ready_job

      assert_equal 1, Flightdeck::JobsQuery.new(state: :ready).count
      assert_equal 24, Flightdeck::Metrics::Series.new(window: "24h", now: NOW).throughput.size
    end
  end

  test "a zero TTL disables caching entirely" do
    create_ready_job

    assert_equal 1, Flightdeck::Cache.fetch("probe", expires_in: 0) { 1 }
    assert_equal 2, Flightdeck::Cache.fetch("probe", expires_in: 0) { 2 }
  end

  # --- keys -----------------------------------------------------------------

  test "keys are namespaced and stable regardless of hash ordering" do
    assert_equal "flightdeck:count:ready", Flightdeck::Cache.key_for([ "count", :ready ])
    assert_equal Flightdeck::Cache.key_for([ { b: 2, a: 1 } ]),
                 Flightdeck::Cache.key_for([ { a: 1, b: 2 } ])
  end

  class ExplodingStore
    def fetch(*, **) = raise(Errno::ECONNREFUSED)
    def clear(*) = nil
  end

  private
    def count_queries
      count = 0
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
        count += 1 unless payload[:name] == "SCHEMA" || payload[:sql].start_with?("TRANSACTION", "begin", "commit")
      end
      yield
      count
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    def with_cache_store(store)
      original = Rails.cache
      Rails.cache = store
      yield
    ensure
      Rails.cache = original
    end
end
