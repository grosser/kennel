# frozen_string_literal: true
require "hashdiff"

module Kennel
  module Models
    class Base
      extend SubclassTracking
      include SettingsAsMethods

      SETTING_OVERRIDABLE_METHODS = [:name, :kennel_id].freeze

      def kennel_id
        @kennel_id ||= Utils.snake_case kennel_id_base
      end

      def name
        self.class.name
      end

      def to_json # rubocop:disable Lint/ToJSON
        raise NotImplementedError, "Use working_json"
      end

      private

      # hook to allow overwriting id generation to remove custom module scopes
      def kennel_id_base
        name = self.class.name
        if name.start_with?("Kennel::") # core objects would always generate the same id
          raise_with_location ArgumentError, "Set :kennel_id"
        end
        name
      end
    end
  end
end
