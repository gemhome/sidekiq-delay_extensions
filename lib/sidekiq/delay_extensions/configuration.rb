# frozen_string_literal: true

module Sidekiq
  module DelayExtensions
    ##
    # Storage for gem configuration settings.
    ##
    class Configuration
      # List of classes that used for permitted_classes attribure for Psych#load method (YAML load)
      # Actual for Ruby v3.1.0 and higher
      attr_accessor :yaml_permitted_classes
      # Boolean value that used for aliases attribure for Psych#load method (YAML load)
      # Actual for Ruby v3.1.0 and higher
      attr_accessor :yaml_aliases

      def initialize
        @yaml_permitted_classes = []
        @yaml_aliases = false
      end
    end
  end
end
