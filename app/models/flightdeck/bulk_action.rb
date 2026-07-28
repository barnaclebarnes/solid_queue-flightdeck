# frozen_string_literal: true

module Flightdeck
  # Applies a Solid Queue operation across a filtered relation in bounded,
  # individually-committed batches.
  #
  # Three things keep this safe to run against a live queue:
  #   * a hard record limit (`Flightdeck.config.bulk_action_limit`),
  #   * a wall-clock deadline measured on the monotonic clock, and
  #   * a commit per batch, so stopping early still leaves completed work done.
  #
  # Stopping early is a normal outcome, not an error: the caller reports
  # "Retried 1,000 of ~14,200" and the same request can simply be submitted
  # again to continue.
  class BulkAction
    BATCH_SIZE = 100
    DEADLINE = 10.seconds

    Result = Struct.new(:processed, :failed, :total, :total_capped, :stopped, keyword_init: true) do
      def stopped_early? = stopped.present?
      def remaining = [ total - processed, 0 ].max
      def remaining? = stopped_early? && remaining.positive?
      def total_label = total_capped ? "#{total}+" : total.to_s
    end

    attr_reader :relation, :limit, :deadline, :count_cap

    def initialize(relation:, limit: nil, deadline: DEADLINE, count_cap: nil)
      @relation = relation
      @limit = (limit || Flightdeck.config.bulk_action_limit).to_i
      @deadline = deadline
      @count_cap = (count_cap || Flightdeck.config.count_cap).to_i
    end

    def call(&operation)
      total = relation.limit(count_cap).count
      started_at = monotonic_now
      processed = 0
      failed = 0
      stopped = nil

      relation.in_batches(of: BATCH_SIZE, order: :desc) do |batch|
        SolidQueue::Record.transaction do
          batch.each do |record|
            if processed + failed >= limit
              stopped = :limit
              break
            end

            begin
              operation.call(record)
              processed += 1
            rescue ActiveRecord::RecordNotFound, ActiveRecord::Deadlocked
              # The queue moved under us — a worker finished or retried this job
              # first. Skip it; the caller's counts stay honest.
              failed += 1
            end
          end
        end

        break if stopped

        if monotonic_now - started_at >= deadline
          stopped = :deadline
          break
        end
      end

      Result.new(
        processed: processed,
        failed: failed,
        total: total,
        total_capped: total >= count_cap,
        stopped: stopped
      )
    end

    private
      def monotonic_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
  end
end
