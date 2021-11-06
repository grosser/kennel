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

    def set_new(type, tracking_id)
      @map[type][tracking_id] = NEW
    end

    def new?(type, tracking_id)
      @map[type][tracking_id] == NEW
    end
  end
end
