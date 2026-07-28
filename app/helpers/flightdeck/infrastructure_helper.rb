# frozen_string_literal: true

module Flightdeck
  module InfrastructureHelper
    RECURRING_STATUS = {
      ok: [ "OK", "finished" ],
      failed: [ "LAST RUN FAILED", "failed" ],
      unknown: [ "PURGED", "scheduled" ]
    }.freeze

    def dom_id_for_queue(name) = "fd-queue-#{name.parameterize.presence || Digest::MD5.hexdigest(name)}"
    def dom_id_for_process(id) = "fd-process-#{id}"
    def dom_id_for_recurring_task(id) = "fd-recurring-task-#{id}"

    # A task that has never run has no status to report, and a task whose job has
    # been purged is reported as purged rather than as a success we did not see.
    def fd_recurring_status_pill(status)
      return tag.span("—", class: "dim") if status.nil?

      label, pill = RECURRING_STATUS.fetch(status, [ status.to_s.upcase, "scheduled" ])
      tag.span(label, class: "fd-pill #{pill}")
    end
  end
end
