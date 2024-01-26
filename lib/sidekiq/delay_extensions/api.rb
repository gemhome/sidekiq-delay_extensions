# frozen_string_literal: true

require "sidekiq/api"

module Sidekiq
  module DelayExtensions
    module JobRecord
      def display_class
        # Unwrap known wrappers so they show up in a human-friendly manner in the Web UI
        @klass ||= self["display_class"] || begin
          case klass
          when /\ASidekiq::DelayExtensions::Delayed/, /\ASidekiq::Extensions::Delayed/
            safe_load(args[0], klass) do |target, method, _|
              "#{target}.#{method}"
            end
          else
            super
          end
        end
      end

      def display_args
        # Unwrap known wrappers so they show up in a human-friendly manner in the Web UI
        @display_args ||= case klass
        when /\ASidekiq::DelayExtensions::Delayed/, /\ASidekiq::Extensions::Delayed/
          safe_load(args[0], args) do |_, _, arg, kwarg|
            if !kwarg || kwarg.empty?
              arg
            else
              [arg, kwarg]
            end
          end
        else
          super
        end
      end

      private

      # per https://github.com/mperham/sidekiq/blob/v6.5.8/lib/sidekiq/api.rb#L492-L502
      # vs.
      # https://github.com/mperham/sidekiq/blob/v7.0.1/lib/sidekiq/api.rb#L374-L411
      def safe_load(content, default)
        yield(*Sidekiq::DelayExtensions::YAML.unsafe_load(content))
      rescue => ex
        # #1761 in dev mode, it's possible to have jobs enqueued which haven't been loaded into
        # memory yet so the YAML can't be loaded.
        # TODO is this still necessary? Zeitwerk reloader should handle?
        sidekiq_env = ::Sidekiq.default_configuration[:environment] || ENV["APP_ENV"] || ENV["RAILS_ENV"] || ENV["RACK_ENV"]
        ::Sidekiq.logger.warn "Unable to load YAML: #{ex.message}" unless sidekiq_env == "development"
        default
      end
    end
  end
end
