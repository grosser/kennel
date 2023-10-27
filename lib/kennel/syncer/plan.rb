# frozen_string_literal: true
module Kennel
  class Syncer
    Plan = Struct.new(:creates, :updates, :deletes) do
      attr_writer :changes

      def changes
        @changes || (deletes + creates + updates).map(&:change) # roughly ordered in the way that update works
      end

      def empty?
        (creates + updates + deletes).empty?
      end
    end

    Change = Struct.new(:type, :api_resource, :tracking_id, :id)
  end
end
