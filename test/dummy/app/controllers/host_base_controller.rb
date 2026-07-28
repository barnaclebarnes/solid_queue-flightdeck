# frozen_string_literal: true

# Stands in for a host application's own authenticated base controller. Used by
# test/boot_test.rb to prove that `config.base_controller_class` really does put
# the host's filters in front of every Flightdeck action.
class HostBaseController < ActionController::Base
  before_action :require_host_token

  private
    def require_host_token
      return if request.headers["X-Host-Token"] == "hosted"

      render plain: "host says no", status: :forbidden
    end
end
