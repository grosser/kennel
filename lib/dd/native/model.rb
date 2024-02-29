# frozen_string_literal:true

require_relative "model/monitor"
require_relative "model/slo"
require_relative "model/dashboard"
require_relative "model/synthetics_tests"
require_relative "model/template_variable"
require_relative "model/widget"
require_relative "model/widget_definition"
require_relative "model/widget_layout"

module DD
  module Native
    class Model
      UnhandledType = Data.define(:base, :type)

      def self.from_single(item, type = :default)
        if type == :default
          return new(item) if !const_defined?(:TYPE_FIELD)

          type = item.fetch(self::TYPE_FIELD.to_s)
        end

        klass = self::TYPE_MAP.fetch(type.to_sym, nil)
        klass ? klass.new(item) : UnhandledType.new(base: self, type:)
      end

      def self.from_multi(items, allow_nil:)
        return if items.nil? && allow_nil

        if const_defined?(:TYPE_FIELD) && const_defined?(:TYPE_MAP)
          items.map do |item|
            from_single(item, )
          end
        else
          items.map do |item|
            new(item)
          end
        end
      end

      def initialize(item, &block)
        required_keys = self.class::REQUIRED_KEYS
        optional_keys = self.class::OPTIONAL_KEYS

        missing_keys = required_keys - item.keys
        alien_keys = item.keys - required_keys - optional_keys

        raise "Missing required keys #{missing_keys.sort}" unless missing_keys.empty?
        raise "Alien keys #{alien_keys.sort}" unless alien_keys.empty?

        (required_keys + optional_keys).each do |k|
          value = item.fetch(k, :absent)
          next if value == :absent

          # if $t && (value.is_a?(Hash) || value.is_a?(Array))
          #   stat_key = [self.class, k, value.class]
          #   $t[stat_key] = $t.fetch(stat_key, 0) + 1
          # end

          instance_variable_set("@#{k}", value.dup.freeze)
        end

        instance_eval(&block) if block

        freeze
      end

      def present?(key)
        required_keys = self.class::REQUIRED_KEYS
        optional_keys = self.class::OPTIONAL_KEYS

        raise "Bad key #{key}" unless (required_keys + optional_keys).include?(key)

        instance_variable_set?("@#{key}")
      end
    end
  end
end
