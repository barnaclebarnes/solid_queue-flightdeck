# frozen_string_literal: true

module Flightdeck
  class JobsController < ApplicationController
    rescue_from JobsQuery::InvalidState, with: :unknown_state
    rescue_from ActiveRecord::RecordNotFound, with: :job_gone

    def index
      @query = JobsQuery.new(**list_filters, state: state_param, before_id: params[:before_id])
      @rows = @query.rows
      @state_counts = JobsQuery.state_counts(**list_filters)
      @groups = GroupedFailures.build(@rows) if state_param == :failed && group_failures?
    end

    def show
      @job = JobDetail.find(params[:id])
    end

    private
      def state_param
        value = params[:state].presence&.to_sym || :all
        raise JobsQuery::InvalidState, "unknown job state #{params[:state].inspect}" unless JobsQuery::STATES.include?(value)

        value
      end

      def group_failures?
        params[:group_by].blank? || params[:group_by] == "exception_class"
      end

      def unknown_state
        redirect_to jobs_path, alert: "Unknown job state."
      end

      def job_gone
        redirect_to jobs_path(state: params[:state]), alert: "That job no longer exists."
      end
  end
end
