# frozen_string_literal: true

module Kennel
  class Syncer
    module Types
      class PlannedChange
        def initialize(klass, tracking_id)
          @klass = klass
          @tracking_id = tracking_id
        end

        def api_resource
          klass.api_resource
        end

        def url(id = nil)
          klass.url(id || self.id)
        end

        def change(id = nil)
          Change.new(self.class::TYPE, api_resource, tracking_id, id)
        end

        attr_reader :klass, :tracking_id
      end

      class PlannedCreate < PlannedChange
        TYPE = :create

        def initialize(expected)
          super(expected.class, expected.tracking_id)
          @expected = expected
        end

        attr_reader :expected
      end

      class PlannedUpdate < PlannedChange
        TYPE = :update

        def initialize(expected, actual, diff)
          super(expected.class, expected.tracking_id)
          @expected = expected
          @actual = actual
          @diff = diff
          @id = actual.fetch(:id)
        end

        def change
          super(id)
        end

        attr_reader :expected, :actual, :diff, :id
      end

      class PlannedDelete < PlannedChange
        TYPE = :delete

        def initialize(actual)
          super(actual.fetch(:klass), actual.fetch(:tracking_id))
          @actual = actual
          @id = actual.fetch(:id)
        end

        def change
          super(id)
        end

        attr_reader :actual, :id
      end
    end
  end
end
