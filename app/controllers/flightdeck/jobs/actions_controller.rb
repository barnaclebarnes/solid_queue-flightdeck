# frozen_string_literal: true

module Flightdeck
  module Jobs
    # Shared machinery for the two destructive jobs actions. Subclasses say what
    # rows they act on and what Solid Queue method does the work; everything
    # about scoping, batching, counting and responding lives here.
    #
    # Three scopes, one action:
    #   * one job          POST /jobs/:id/retry
    #   * selected jobs    POST /jobs/retry   with job_ids[]
    #   * all matching     POST /jobs/retry   with scope=all + the list filters
    class ActionsController < Flightdeck::ApplicationController
      def create
        result =
          if params[:id].present?
            act_on_single
          elsif params[:scope] == "all"
            act_on_all_matching
          else
            act_on_selected
          end

        respond_with(result)
      end

      private
        # --- subclass contract ------------------------------------------------

        # Relation of execution rows this action may act on, already filtered.
        def target_relation
          raise NotImplementedError
        end

        # The Solid Queue call that performs the action on one execution row.
        def apply(execution)
          raise NotImplementedError
        end

        def verb = raise(NotImplementedError)
        def past_tense = raise(NotImplementedError)

        # --- scopes -----------------------------------------------------------

        def find_single(job_id)
          target_relation.find_by(job_id: job_id)
        end

        def act_on_single
          execution = find_single(params[:id])
          return failure("That job is no longer #{blocked_reason}.") unless execution

          apply(execution)
          success("#{past_tense.capitalize} job ##{params[:id]}.")
        rescue SolidQueue::Execution::UndiscardableError => error
          failure(error.message)
        end

        # Selected ids are re-checked against the live relation rather than
        # trusted: between rendering the page and clicking the button a worker
        # may have retried, finished or discarded any of them.
        def act_on_selected
          ids = Array(params[:job_ids]).map { |id| Integer(id, exception: false) }.compact.uniq
          return failure("Nothing selected.") if ids.empty?

          if ids.size > Flightdeck.config.bulk_action_limit
            return failure("Select at most #{number_with_delimiter(Flightdeck.config.bulk_action_limit)} jobs.")
          end

          executions = target_relation.where(job_id: ids).to_a
          return failure("Those jobs are no longer #{blocked_reason}.") if executions.empty?

          applied = 0
          SolidQueue::Record.transaction do
            executions.each do |execution|
              apply(execution)
              applied += 1
            end
          end

          missing = ids.size - applied
          message = "#{past_tense.capitalize} #{pluralize_jobs(applied)}."
          message += " #{missing} had already moved on." if missing.positive?
          success(message)
        end

        def act_on_all_matching
          result = BulkAction.new(relation: target_relation).call { |execution| apply(execution) }

          success(bulk_message(result), continuable: result.remaining?)
        end

        def bulk_message(result)
          if result.stopped_early? && result.remaining?
            "#{past_tense.capitalize} #{number_with_delimiter(result.processed)} of " \
              "~#{result.total_label} — continue?"
          else
            "#{past_tense.capitalize} #{pluralize_jobs(result.processed)}."
          end
        end

        # --- responses --------------------------------------------------------

        def success(message, continuable: false)
          { message: message, level: :success, continuable: continuable }
        end

        def failure(message)
          { message: message, level: :error, continuable: false }
        end

        def respond_with(result)
          @toast = result

          respond_to do |format|
            format.turbo_stream do
              build_refreshed_list
              render "flightdeck/jobs/actions/create", formats: :turbo_stream
            end
            format.html { redirect_back_to_list(result) }
            format.any { redirect_back_to_list(result) }
          end
        end

        # The list the action was launched from, re-queried so the same response
        # that carries the toast also carries settled rows and counts.
        def build_refreshed_list
          # Bypass the count cache: this response exists precisely to show the
          # effect of the action that just ran.
          Flightdeck::Cache.bypass do
            @refreshed_state = refreshed_state
            @refreshed_query = JobsQuery.new(**list_filters, state: @refreshed_state)
            @refreshed_rows = @refreshed_query.rows
            @refreshed_groups = GroupedFailures.build(@refreshed_rows) if @refreshed_state == :failed
          end
        end

        def refreshed_state
          state = params[:state].presence&.to_sym || default_state
          JobsQuery::STATES.include?(state) ? state : :all
        end

        def redirect_back_to_list(result)
          flash[result[:level] == :error ? :alert : :notice] = result[:message]
          redirect_to jobs_path(list_filters.merge(state: params[:state].presence || default_state))
        end

        def default_state = :failed

        def blocked_reason = "eligible"

        def pluralize_jobs(count)
          "#{number_with_delimiter(count)} #{"job".pluralize(count)}"
        end

        def number_with_delimiter(value)
          view_context.number_with_delimiter(value)
        end

        # The filters the list was showing, used to rebuild the exact same set
        # server-side for "apply to all matching".
        def scoped_query(state:)
          JobsQuery.new(**list_filters, state: state)
        end
    end
  end
end
