# frozen_string_literal: true

require "sidekiq"

if Gem::Version.new(Sidekiq::VERSION) >= Gem::Version.new("8.1.1")
  Sidekiq.testing!(:fake) unless defined?(Sidekiq::TestingExtensions)
else
  require "sidekiq/testing"
end

module Sidekiq
  module DelayedTestingExtensions
    include TestingExtensions

    # NOTE(BF): Extend Sidekiq::TestingExtensions
    # to optionally handle unsafely loading YAML
    # for delayed extensions in Sidekiq 7.x.
    def jobs_for(klass, unsafe_load: false)
      return super(klass) unless unsafe_load
      jobs.select do |job|
        marshalled = job["args"][0]
        next unless marshalled.index(klass.to_s)
        ::Sidekiq::DelayExtensions::YAML.unsafe_load(marshalled)
      end
    end
  end
  Sidekiq::DelayExtensions::DelayedMailer.extend(DelayedTestingExtensions) if defined?(Sidekiq::DelayExtensions::DelayedMailer)
  Sidekiq::DelayExtensions::DelayedModel.extend(DelayedTestingExtensions) if defined?(Sidekiq::DelayExtensions::DelayedModel)
end
