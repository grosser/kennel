# frozen_string_literal: true

module Kennel
  module DependencyChecker
    class ItemUtils
      class Base

        def initialize(key, object)
          @resource = key.resource.to_s
          @id = key.id
          @object = object
        end

        attr_reader :resource, :id, :object

        def kennel_id
          text = kennel_id_text
          return unless text

          m = text.match(/Managed by kennel (\S+) in ([^,]+),/)
          m or return

          KennelId.new(id: m[1], in: m[2])
        end

      end
    end
  end
end
