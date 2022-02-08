# frozen_string_literal: true

require "sidekiq/testing"

module Sidekiq
  Sidekiq::DelayExtensions::DelayedMailer.extend(TestingExtensions) if defined?(Sidekiq::DelayExtensions::DelayedMailer)
  Sidekiq::DelayExtensions::DelayedModel.extend(TestingExtensions) if defined?(Sidekiq::DelayExtensions::DelayedModel)
end
