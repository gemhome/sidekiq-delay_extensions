# frozen_string_literal: true

require "sidekiq/delay_extensions/generic_proxy"

module Sidekiq
  module DelayExtensions
    ##
    # Adds `delay`, `delay_for` and `delay_until` methods to all Classes to offload class method
    # execution to Sidekiq.
    #
    # @example
    #   User.delay.delete_inactive
    #   Wikipedia.delay.download_changes_for(Date.today)
    #
    class DelayedClass < GenericJob
    end

    module Klass
      def sidekiq_delay_proxy
        if Sidekiq::DelayExtensions.use_generic_proxy
          GenericProxy
        else
          Proxy
        end
      end

      def sidekiq_delay(options = {})
        sidekiq_delay_proxy.new(DelayedClass, self, options)
      end

      def sidekiq_delay_for(interval, options = {})
        sidekiq_delay_proxy.new(DelayedClass, self, options.merge("at" => Time.now.to_f + interval.to_f))
      end

      def sidekiq_delay_until(timestamp, options = {})
        sidekiq_delay_proxy.new(DelayedClass, self, options.merge("at" => timestamp.to_f))
      end
      alias_method :delay, :sidekiq_delay
      alias_method :delay_for, :sidekiq_delay_for
      alias_method :delay_until, :sidekiq_delay_until
    end
  end
end

Module.__send__(:include, Sidekiq::DelayExtensions::Klass) unless defined?(::Rails)
