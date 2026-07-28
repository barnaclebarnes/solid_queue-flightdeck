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
