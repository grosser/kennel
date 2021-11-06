# frozen_string_literal: true
module Kennel
  class IdMap
    NEW = :new

    def initialize
      @map = Hash.new { |h, k| h[k] = {} }
    end

    def add(type, tracking_id, id)
      @map[type][tracking_id] = id
    end

    def add_new(type, tracking_id)
      @map[type][tracking_id] = NEW
    end

    def new?(type, tracking_id)
      @map[type][tracking_id] == NEW
    end

    def get(type, tracking_id)
      @map[type][tracking_id]
    end
  end
end
