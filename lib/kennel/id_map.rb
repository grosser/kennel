# frozen_string_literal: true
module Kennel
  class IdMap
    NEW = :new # will be created during this run

    def initialize
      @map = Hash.new { |h, k| h[k] = {} }
    end

    def get(type, tracking_id)
      @map[type][tracking_id]
    end

    def set(type, tracking_id, id)
      @map[type][tracking_id] = id
    end

    def new?(type, tracking_id)
      @map[type][tracking_id] == NEW
    end

    def reverse_get(type, id)
      @inverse_map ||= @map.transform_values(&:invert)
      @inverse_map[type][id]
    end
  end
end
