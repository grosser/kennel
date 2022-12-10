# frozen_string_literal: true
module Kennel
  module SubclassTracking
    TRACKED_CLASSES = []

    def recursive_subclasses
      subclasses + subclasses.flat_map(&:recursive_subclasses)
    end

    def subclasses
      @subclasses ||= []
    end

    private

    def inherited(child)
      super
      TRACKED_CLASSES << child
      subclasses << child
    end
  end
end
