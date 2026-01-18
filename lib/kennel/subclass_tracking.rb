# frozen_string_literal: true
module Kennel
  module SubclassTracking
    def recursive_subclasses
      subclasses + subclasses.flat_map(&:recursive_subclasses)
    end

    def subclasses
      @subclasses ||= []
    end

    def abstract_class?
      !!@abstract_class
    end

    private

    def abstract_class!
      @abstract_class = true # not inherited by children
    end

    def inherited(child)
      super
      subclasses << child
    end
  end
end
