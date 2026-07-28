# frozen_string_literal: true

Rails.application.routes.draw do
  root to: redirect("/flightdeck")

  mount Flightdeck::Engine => "/flightdeck"

  # A second mount, deeper in the path, proves the engine is entirely
  # mount-relative — every link, form action, asset URL and Turbo root has to
  # come from the request's own script_name rather than from a remembered
  # mount point. A distinct `as:` keeps the two route-helper names apart.
  mount Flightdeck::Engine => "/admin/flightdeck", as: :admin_flightdeck

  get "up", to: proc { [ 200, { "Content-Type" => "text/plain" }, [ "ok" ] ] }
end
