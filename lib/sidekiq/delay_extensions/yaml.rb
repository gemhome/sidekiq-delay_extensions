# frozen_string_literal: true

module Sidekiq
  module DelayExtensions
    module YAML
      STDLIB_YAML = ::YAML

      if STDLIB_YAML.respond_to?(:unsafe_load)
        # https://github.com/ruby/psych/blob/v4.0.3/lib/psych.rb#L271-L323
        # def self.unsafe_load(yaml, filename: nil, fallback: false, symbolize_names: false, freeze: false)
        def self.unsafe_load(yaml, **kwargs)
          STDLIB_YAML.unsafe_load(yaml, **kwargs)
        end

        # def self.safe_load(yaml, permitted_classes: [], permitted_symbols: [], aliases: false, filename: nil, fallback: nil, symbolize_names: false, freeze: false)
        def self.safe_load(yaml, **kwargs)
          STDLIB_YAML.safe_load(yaml, **kwargs)
        end

        # def self.unsafe_load_file(filename, **kwargs)
        def self.unsafe_load_file(filename, **kwargs)
          STDLIB_YAML.unsafe_load_file(filename, **kwargs)
        end

        # def self.safe_load_file(filename, **kwargs)
        def self.safe_load_file(filename, **kwargs)
          STDLIB_YAML.safe_load_file(filename, **kwargs)
        end
      else
        # https://github.com/ruby/psych/blob/v3.1.0/lib/psych.rb#L271-L328
        # vs.
        # https://github.com/ruby/psych/blob/v4.0.3/lib/psych.rb#L271-L323
        # def self.load(       yaml, filename: nil, fallback: false, symbolize_names: false)
        #   vs.
        # def self.unsafe_load(yaml, filename: nil, fallback: false, symbolize_names: false, freeze: false)
        def self.unsafe_load(yaml, **kwargs)
          STDLIB_YAML.load(yaml, **kwargs)
        end

        # def self.safe_load(yaml, permitted_classes: [], permitted_symbols: [], aliases: false, filename: nil, fallback: nil, symbolize_names: false)
        #   vs.
        # def self.safe_load(yaml, permitted_classes: [], permitted_symbols: [], aliases: false, filename: nil, fallback: nil, symbolize_names: false, freeze: false)
        def self.safe_load(yaml, **kwargs)
          STDLIB_YAML.safe_load(yaml, **kwargs)
        end

        # def self.load_file filename, fallback: false
        #    vs.
        # def self.unsafe_load_file(filename, **kwargs)
        def self.unsafe_load_file(filename, **kwargs)
          STDLIB_YAML.load_file(filename, **kwargs)
        end

        # n/a
        #    vs.
        # def self.safe_load_file(filename, **kwargs)
        def self.safe_load_file(filename, **kwargs)
          STDLIB_YAML.load_file(filename, **kwargs)
        end
      end
      # NOTE(BF): In case someone calls YAML.load
      # from within the gem.
      singleton_class.alias_method :load, :unsafe_load
    end
  end
end
