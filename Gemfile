source "https://rubygems.org"

gemspec

gem "sidekiq", "6.5.12"
gem "rake"
gem "redis"
gem "redis-namespace"
gem "redis-client"
gem "rails", "~> 6.0"
# gem "bumbler"
# gem "debug"

gem "sqlite3", platforms: :ruby
gem "activerecord-jdbcsqlite3-adapter", platforms: :jruby
gem "after_commit_everywhere", require: false
gem "yard"

# mail dependencies
gem "net-smtp", platforms: :mri, require: false

group :test do
  gem "maxitest"
  gem "simplecov"
end

group :development, :test do
  gem "standard", require: false
end

group :load_test do
  gem "toxiproxy"
  gem "ruby-prof"
end
