# frozen_string_literal: true
require "hashdiff"

module Kennel
  module Models
    class Base
      extend SubclassTracking
      include SettingsAsMethods

      SETTING_OVERRIDABLE_METHODS = [:name, :kennel_id].freeze

      def kennel_id
        name = self.class.name
        if name.start_with?("Kennel::") # core objects would always generate the same id
          raise_with_location ArgumentError, "Set :kennel_id"
        end
        @kennel_id ||= Utils.snake_case name
      end

      def name
        self.class.name
      end

      def to_json # rubocop:disable Lint/ToJSON
        raise NotImplementedError, "Use as_json"
      end
    end
  end
end
