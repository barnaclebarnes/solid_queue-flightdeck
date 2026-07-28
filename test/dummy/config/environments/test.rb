# frozen_string_literal: true

Rails.application.configure do
  config.cache_classes = true if config.respond_to?(:cache_classes=)
  config.enable_reloading = false
  config.eager_load = false
  config.consider_all_requests_local = true
  # :rescuable so that routing misses surface as the 404 a real deployment
  # would return, while unexpected errors still blow up the test.
  config.action_dispatch.show_exceptions = :rescuable
  config.active_support.deprecation = :stderr
  config.cache_store = :memory_store
  # test_helper loads db/schema.rb itself; Rails' schema-maintenance hook would
  # otherwise try to shell out to a db:test:prepare task the engine has no use for.
  config.active_record.maintain_test_schema = false

  config.action_controller.perform_caching = false
  # Left on in both CI legs: it is what proves the engine-local session and
  # CSRF machinery work even when the host app is API-only.
  config.action_controller.allow_forgery_protection = true
end
