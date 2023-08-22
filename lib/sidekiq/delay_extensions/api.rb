# frozen_string_literal: true

require "sidekiq/api"

module Sidekiq
  module DelayExtensions
    module JobRecord
      def display_class
        # Unwrap known wrappers so they show up in a human-friendly manner in the Web UI
        @klass ||= self["display_class"] || begin
          case klass
          when /\ASidekiq::DelayExtensions::Delayed/
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
                  when /\ASidekiq::DelayExtensions::Delayed/
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

      def safe_load(content, default)
        yield(*YAML.load(content))
      rescue => ex
        # #1761 in dev mode, it's possible to have jobs enqueued which haven't been loaded into
        # memory yet so the YAML can't be loaded.
        # TODO is this still necessary? Zeitwerk reloader should handle?
        Sidekiq.logger.warn "Unable to load YAML: #{ex.message}" unless Sidekiq.options[:environment] == "development"
        default
      end
    end
  end
end
