# frozen_string_literal: true

require_relative "lib/sidekiq/delay_extensions/version"

Gem::Specification.new do |spec|
  spec.name = "sidekiq-delay_extensions"
  spec.version = Sidekiq::DelayExtensions::VERSION
  spec.authors = ["Mike Perham", "Benjamin Fleischer"]
  spec.email = ["info@contribsys.com", "github@benjaminfleischer.com"]

  spec.summary = "Sidekiq Delay Extensions"
  spec.description = "Extracted from Sidekiq 6.0, compatible with Sidekiq 7.0"
  spec.homepage = "https://github.com/gemhome/sidekiq-delay_extensions/wiki/Delayed-extensions"
  spec.license = "LGPL-3.0"

  spec.files = Dir.glob("{bin,lib,config}/**/*") + %w[Gemfile sidekiq-delay_extensions.gemspec README.md Changes.md LICENSE]

  spec.bindir = "exe"
  spec.executables = []
  spec.require_paths = ["lib"]
  spec.required_ruby_version = ">= 2.7.0"

  spec.metadata = {
    "homepage_uri" => "https://github.com/gemhome/sidekiq-delay_extensions/wiki/Delayed-extensions",
    "bug_tracker_uri" => "https://github.com/gemhome/sidekiq-delay_extensions/issues",
    "documentation_uri" => "https://github.com/gemhome/sidekiq-delay_extensions/wiki",
    "changelog_uri" => "https://github.com/gemhome/sidekiq-delay_extensions/blob/main/Changes.md",
    "source_code_uri" => "https://github.com/gemhome/sidekiq-delay_extensions"
  }

  spec.add_dependency "sidekiq", ">= 7.0"
end
