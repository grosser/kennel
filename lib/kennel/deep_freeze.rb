# frozen_string_literal: true

module Kennel
  module DeepFreeze
    # There'll be a gem for this somewhere.
    # This code doesn't handle cycles or other reused references.

    def deep_freeze(item)
      case item
      when Hash
        item.map { |k, v| [deep_freeze(k), deep_freeze(v)] }.to_h
      when Array
        item.map { |v| deep_freeze(v) }
      else
        item.dup.freeze
      end.freeze
    end

    def deep_dup_thaw(value)
      case value
      when Array
        value.map { |v| deep_dup_thaw(v) }
      when Hash
        value.map { |k, v| [deep_dup_thaw(k), deep_dup_thaw(v)] }.to_h
      else
        value.dup
      end
    end
  end
end
