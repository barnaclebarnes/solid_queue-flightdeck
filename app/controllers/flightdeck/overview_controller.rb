# frozen_string_literal: true

module Flightdeck
  class OverviewController < ApplicationController
    def index
      @overview = Overview.new
      @window = Metrics::Series.window_for(params[:range])
      @series = @overview.series(window: @window.key)
    end
  end
end
