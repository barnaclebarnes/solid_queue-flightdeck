# frozen_string_literal: true

module Flightdeck
  module Metrics
    # Time series for the Overview charts, computed live from the Solid Queue
    # tables — no rollup tables, no background aggregation.
    #
    # Every series is gap-filled in Ruby so a chart always has a complete axis:
    # a bucket with no rows is a real zero (or a real "no data"), not a missing
    # point that would make the chart lie about its own shape.
    class Series
      Window = Struct.new(:key, :label, :duration, :bucket_seconds, :subtitle, :tick_every,
                          :tick_format, keyword_init: true) do
        def bucket_count = (duration / bucket_seconds).to_i
      end

      WINDOWS = {
        "1h" => Window.new(key: "1h", label: "1H", duration: 1.hour, bucket_seconds: 5.minutes.to_i,
                           subtitle: "per 5 minutes", tick_every: 3, tick_format: "%H:%M"),
        "24h" => Window.new(key: "24h", label: "24H", duration: 24.hours, bucket_seconds: 1.hour.to_i,
                            subtitle: "per hour", tick_every: 4, tick_format: "%H:%M"),
        "7d" => Window.new(key: "7d", label: "7D", duration: 7.days, bucket_seconds: 6.hours.to_i,
                           subtitle: "per 6 hours", tick_every: 4, tick_format: "%-m/%-d")
      }.freeze

      DEFAULT_WINDOW = "24h"
      SPARKLINE_HOURS = 16
      SPARKLINE_BUCKET = 1.hour.to_i

      Point = Struct.new(:at, :succeeded, :failed, :seconds, keyword_init: true) do
        def total = succeeded.to_i + failed.to_i
        def blank? = seconds.nil?
      end

      attr_reader :window, :now

      def self.window_for(key)
        WINDOWS.fetch(key.to_s, WINDOWS.fetch(DEFAULT_WINDOW))
      end

      def initialize(window: DEFAULT_WINDOW, now: Time.current)
        @window = window.is_a?(Window) ? window : self.class.window_for(window)
        @now = now.utc
      end

      # Bucket start times, aligned to absolute epoch multiples so that the same
      # bucket has the same boundaries in every process and every request.
      def buckets
        @buckets ||= begin
          last = align(@now.to_i)
          count = window.bucket_count
          Array.new(count) { |i| last - ((count - 1 - i) * window.bucket_seconds) }
        end
      end

      def starts_at = Time.at(buckets.first).utc
      def ends_at = Time.at(buckets.last + window.bucket_seconds).utc

      # Jobs finished (succeeded) and executions failed, per bucket.
      #
      # A job that failed has no finished_at — Solid Queue leaves it null and
      # records a failed_executions row — so the two series never double count.
      def throughput
        cached(:throughput) do
          succeeded = grouped_count(SolidQueue::Job.where(finished_at: starts_at..), :finished_at)
          failed = grouped_count(SolidQueue::FailedExecution.where(created_at: starts_at..), :created_at,
                                 table: SolidQueue::FailedExecution.table_name)

          buckets.map do |bucket|
            Point.new(at: Time.at(bucket).utc,
                      succeeded: succeeded.fetch(bucket, 0),
                      failed: failed.fetch(bucket, 0))
          end
        end
      end

      # Average wall-clock time from enqueue to finish, per bucket.
      #
      # This is time *to completion*, not time to start: Solid Queue deletes the
      # claimed_executions row when a job finishes, so the moment a job actually
      # started is not recoverable after the fact and no honest historical
      # time-to-start series can be built from these tables.
      def completion_time
        cached(:completion_time) do
          averages = SolidQueue::Job
            .where(finished_at: starts_at..)
            .group(TimeBucket.sql("#{jobs_table}.finished_at", window.bucket_seconds))
            .average(TimeBucket.elapsed_sql("#{jobs_table}.created_at", "#{jobs_table}.finished_at"))
            .transform_keys(&:to_i)

          buckets.map do |bucket|
            value = averages[bucket]
            Point.new(at: Time.at(bucket).utc, seconds: value&.to_f)
          end
        end
      end

      def total_succeeded = throughput.sum(&:succeeded)
      def total_failed = throughput.sum(&:failed)

      def empty? = throughput.all? { |point| point.total.zero? }

      # Finished-job retention shorter than the window means the oldest buckets
      # are missing rows that really did happen. The chart says so rather than
      # showing a decline that is an artefact of purging.
      def truncated_by_retention?
        retention.present? && retention < window.duration
      end

      def retention
        return nil unless SolidQueue.respond_to?(:clear_finished_jobs_after)
        return nil unless SolidQueue.preserve_finished_jobs?

        SolidQueue.clear_finished_jobs_after
      end

      # One query for every queue's hourly finished count, fanned out in Ruby.
      # Used by the queue cards and the Overview mini-table.
      def self.queue_sparklines(now: Time.current, hours: SPARKLINE_HOURS)
        Flightdeck::Cache.fetch("sparklines", hours, align_to(now.to_i, SPARKLINE_BUCKET),
                                expires_in: Flightdeck.config.chart_cache_ttl) do
          last = align_to(now.to_i, SPARKLINE_BUCKET)
          slots = Array.new(hours) { |i| last - ((hours - 1 - i) * SPARKLINE_BUCKET) }

          counts = SolidQueue::Job
            .where(finished_at: Time.at(slots.first).utc..)
            .group(:queue_name)
            .group(TimeBucket.sql("#{SolidQueue::Job.table_name}.finished_at", SPARKLINE_BUCKET))
            .count

          fanned = Hash.new { |hash, key| hash[key] = Array.new(hours, 0) }
          counts.each do |(queue_name, bucket), count|
            index = slots.index(bucket.to_i)
            next unless index

            fanned[queue_name][index] = count
          end
          fanned.default = nil
          fanned
        end
      end

      def self.align_to(epoch, seconds) = (epoch / seconds) * seconds

      private
        def jobs_table = SolidQueue::Job.table_name

        def align(epoch) = self.class.align_to(epoch, window.bucket_seconds)

        def grouped_count(relation, column, table: SolidQueue::Job.table_name)
          relation
            .group(TimeBucket.sql("#{table}.#{column}", window.bucket_seconds))
            .count
            .transform_keys(&:to_i)
        end

        # Keyed on the aligned bucket so the cache turns over with the buckets
        # themselves rather than at an arbitrary moment.
        def cached(name, &block)
          Flightdeck::Cache.fetch("series", name, window.key, buckets.last,
                                  expires_in: Flightdeck.config.chart_cache_ttl, &block)
        end
    end
  end
end
