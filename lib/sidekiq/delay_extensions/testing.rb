# frozen_string_literal: true

require "sidekiq/testing"

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
        YAML.load(marshalled)
      end
    end
  end
  Sidekiq::DelayExtensions::DelayedMailer.extend(DelayedTestingExtensions) if defined?(Sidekiq::DelayExtensions::DelayedMailer)
  Sidekiq::DelayExtensions::DelayedModel.extend(DelayedTestingExtensions) if defined?(Sidekiq::DelayExtensions::DelayedModel)
end
