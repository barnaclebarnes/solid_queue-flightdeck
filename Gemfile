# frozen_string_literal: true

source "https://rubygems.org"

gemspec

gem "sqlite3"
gem "puma"

group :development, :test do
  gem "rake"
  gem "minitest"
  gem "tailwindcss-ruby", "~> 4.0"
end

# System tests only. They are a separate rake task (`rake test:system`) and skip
# themselves when no Chrome is installed, so the fast suite never needs these.
group :test do
  gem "capybara"
  gem "selenium-webdriver"
end

group :development, :test do
  gem "rubocop-rails-omakase", require: false
end

# Database drivers for the CI matrix. SQLite is the default everywhere, so with
# FLIGHTDECK_DB unset this Gemfile — and therefore Gemfile.lock — is exactly what
# a developer resolves. CI opts a leg in rather than rewriting the Gemfile,
# which bundler refuses to do in the frozen mode that setup-ruby configures.
case ENV["FLIGHTDECK_DB"]
when "postgres" then gem "pg", "~> 1.5"
when "mysql" then gem "mysql2", "~> 0.5"
end
