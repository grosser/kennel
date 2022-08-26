# frozen_string_literal: true

module Kennel
  module Plans
    class Diff
      attr_reader :from, :from_identifier, :to, :to_identifier

      def initialize(from:, from_identifier:, to:, to_identifier:)
        @from = from
        @from_identifier = from_identifier
        @to = to
        @to_identifier = to_identifier
      end

      def create?
        from.nil? && !to.nil?
      end

      def update?
        !from.nil? && !to.nil?
      end

      def delete?
        !from.nil? && to.nil?
      end
    end
  end
end
