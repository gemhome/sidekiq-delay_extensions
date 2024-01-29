# frozen_string_literal: true

require "yaml"

module Sidekiq
  module DelayExtensions
    SIZE_LIMIT = 8_192

    singleton_class.attr_accessor :use_generic_proxy
    self.use_generic_proxy = false

    class Proxy < BasicObject
      def initialize(performable, target, options = {})
        @performable = performable
        @target = target
        @opts = options.transform_keys(&:to_s)
      end

      def method_missing(name, *args)
        # Sidekiq has a limitation in that its message must be JSON.
        # JSON can't round trip real Ruby objects so we use YAML to
        # serialize the objects to a String.  The YAML will be converted
        # to JSON and then deserialized on the other side back into a
        # Ruby object.
        obj = [@target, name, args]
        marshalled = ::YAML.dump(obj)
        if marshalled.size > SIZE_LIMIT
          ::Sidekiq.logger.warn { "#{@target}.#{name} job argument is #{marshalled.bytesize} bytes, you should refactor it to reduce the size" }
        end
        @performable.client_push({"class" => @performable,
                                  "args" => [marshalled],
                                  "display_class" => "#{@target}.#{name}"}.merge(@opts))
      end
    end

    class GenericProxy < BasicObject
      def initialize(performable, target, options = {})
        @performable = performable
        @target = target
        @opts = options
      end

      def method_missing(name, *args, **kwargs) # rubocop:disable Style/MissingRespondToMissing
        begin
          has_no_kwargs = kwargs.nil? || kwargs.empty?
          valid_json_args =
            if has_no_kwargs
              # if args.last.is_a?(Hash) && args.last.keys.any? { |key| key.is_a?(Symbol) }
              #   kwargs = args.pop.symbolize_keys
              [*args]
            else
              [*args, JSON.parse(JSON.dump(kwargs))]
            end
          obj = [@target.name, name&.to_s, valid_json_args]
          marshalled = ::JSON.dump(obj)
        rescue ::JSON::ParserError
          obj = if kwargs&.any?
            [@target.name, name&.to_s, *args, **kwargs]
          else
            [@target.name, name&.to_s, *args]
          end
          warn "Non-JSON args passed to Sidekiq delayed job. obj=#{obj.inspect}"
          marshalled = ::YAML.dump(obj)
        end
        # marshalled = ::YAML.dump(valid_json_args)
        # marshalled = ::YAML.to_json(valid_json_args)
        # value = {
        #   target_name: @target.name,
        #   name: name,
        #   args: args,
        #   kwargs: kwargs,
        #   valid_json_args: valid_json_args,
        #   obj: obj,
        #   marshalled: marshalled,
        # }
        # ::STDOUT.puts value.inspect
        if marshalled.size > SIZE_LIMIT
          ::Sidekiq.logger.warn { "#{@target}.#{name} job argument is #{marshalled.bytesize} bytes, you should refactor it to reduce the size" }
        end
        valid_opts = @opts.stringify_keys
        @performable.client_push({"class" => @performable,
                                  "args" => [marshalled],
                                  "display_class" => "#{@target}.#{name}"}.merge(valid_opts))
      end
    end
  end
end
