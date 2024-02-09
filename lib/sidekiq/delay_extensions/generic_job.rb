# frozen_string_literal: true

module Sidekiq
  module DelayExtensions
    class GenericJob
      include Sidekiq::Job

      def perform(yml)
        if !Sidekiq::DelayExtensions.use_generic_proxy
          (target, method_name, args) = ::Sidekiq::DelayExtensions::YAML.unsafe_load(yml)
          return _perform(target, method_name, *args)
        end
        (target, method_name, args, kwargs) = ::Sidekiq::DelayExtensions::YAML.unsafe_load(yml)
        if target.is_a?(String)
          target_klass = target.safe_constantize
          if target_klass
            target = target_klass
          else
            fail NameError, "uninitialized constant #{target}. Peforming: #{yml.inspect}"
          end
        end
        has_no_kwargs = kwargs.nil? || kwargs.empty? # rubocop:disable Rails/Blank
        if has_no_kwargs
          if args.is_a?(Array) && args.last.is_a?(Hash) # && args.last.keys.any? { |key| key.is_a?(Symbol) }
            # rehydrate keys
            kwargs = args.pop.symbolize_keys
            has_no_kwargs = kwargs.empty?
          elsif args.is_a?(Hash)
            # rehydrate keys
            kwargs = args.symbolize_keys
            args = []
            has_no_kwargs = kwargs.empty?
          end
        end
        if has_no_kwargs
          _perform(target, method_name, *args)
        else
          _perform(target, method_name, *args, **kwargs)
        end
      end

      def _perform(target, method_name, *args, **kwargs)
        if kwargs.empty?
          target.__send__(method_name, *args)
        else
          target.__send__(method_name, *args, **kwargs)
        end
      end
    end
  end
end
