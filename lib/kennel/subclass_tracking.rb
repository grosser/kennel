# frozen_string_literal: true
module Kennel
  module SubclassTracking
    def recursive_subclasses
      subclasses + subclasses.flat_map(&:recursive_subclasses)
    end

    def subclasses
      @subclasses ||= []
    end

    private

    def inherited(child)
      super
      subclasses << child
    end
  end
end
