# frozen_string_literal: true

require "sidekiq/testing"

module Sidekiq
  # NOTE(BF): Sidekiq::TestingExtensions changes to use YAML.safe_load in Sidekiq 7.x
  #  module TestingExtensions
  #    def jobs_for(klass)
  #      jobs.select do |job|
  #        marshalled = job["args"][0]
  # -      marshalled.index(klass.to_s) && YAML.load(marshalled)[0] == klass
  # +      marshalled.index(klass.to_s) && YAML.safe_load(marshalled)[0] == klass
  #      end
  #    end
  #  end
  Sidekiq::DelayExtensions::DelayedMailer.extend(TestingExtensions) if defined?(Sidekiq::DelayExtensions::DelayedMailer)
  Sidekiq::DelayExtensions::DelayedModel.extend(TestingExtensions) if defined?(Sidekiq::DelayExtensions::DelayedModel)
end
