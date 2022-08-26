# frozen_string_literal: true

module Kennel
  module Plans
    class Plan
      attr_accessor :create, :update, :delete, :warnings

      def initialize
        @create = []
        @update = []
        @delete = []
        @warnings = []
      end

      def empty?
        diffs.empty?
      end

      def diffs
        result = []

        @create.each do |creation|
          result << Diff.new(from: nil, to: creation[1], from_identifier: nil, to_identifier: creation[1].tracking_id)
        end

        @update.each do |update|
          result << Diff.new(from: update[1], to: update[2], from_identifier: update[1].tracking_id, to_identifier: update[1].tracking_id)
        end

        @delete.each do |deletion|
          result << Diff.new(from: deletion[1], to: nil, from_identifier: deletion[2][:tracking_id], to_identifier: nil)
        end

        result
      end
    end
  end
end
