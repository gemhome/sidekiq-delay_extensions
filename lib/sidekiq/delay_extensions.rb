# frozen_string_literal: true

require "sidekiq"
require "sidekiq/delay_extensions/configuration"

module Sidekiq
  module DelayExtensions
    class << self
      attr_accessor :configuration
    end

    # Call this method to modify default settings in your initializers.
    #
    # @example
    #   Sidekiq::DelayExtensions.configure do |config|
    #     config.setting_name = 'value'
    #   end
    def self.configure
      self.configuration ||= Configuration.new
      yield(configuration)
    end

    def self.enable_delay!
      if defined?(::ActiveSupport)
        require "sidekiq/delay_extensions/active_record"
        require "sidekiq/delay_extensions/action_mailer"

        # Need to patch Psych so it can autoload classes whose names are serialized
        # in the delayed YAML.
        Psych::Visitors::ToRuby.prepend(Sidekiq::DelayExtensions::PsychAutoload)

        ActiveSupport.on_load(:active_record) do
          include Sidekiq::DelayExtensions::ActiveRecord
        end
        ActiveSupport.on_load(:action_mailer) do
          extend Sidekiq::DelayExtensions::ActionMailer
        end
      end

      require "sidekiq/delay_extensions/class_methods"
      Module.__send__(:include, Sidekiq::DelayExtensions::Klass)

      require "sidekiq/delay_extensions/api"
      Sidekiq::JobRecord.prepend(Sidekiq::DelayExtensions::JobRecord)
    end

    module PsychAutoload
      def resolve_class(klass_name)
        return nil if !klass_name || klass_name.empty?
        # constantize
        names = klass_name.split("::")
        names.shift if names.empty? || names.first.empty?

        names.inject(Object) do |constant, name|
          constant.const_defined?(name) ? constant.const_get(name) : constant.const_missing(name)
        end
      rescue NameError
        super
      end
    end
  end
end
