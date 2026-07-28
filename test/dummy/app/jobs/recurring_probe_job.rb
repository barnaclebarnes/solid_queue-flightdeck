# frozen_string_literal: true

# A real ActiveJob class for the recurring-task tests to point at.
# SolidQueue::RecurringTask validates that class_name constantizes, and "Run now"
# genuinely enqueues through it.
class RecurringProbeJob < ActiveJob::Base
  queue_as :default

  def perform(*); end
end
