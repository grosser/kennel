# frozen_string_literal: true

module Kennel
  module Plans
    class Plan
      class Diff
        class Object
          attr_accessor :id, :value

          def initialize(id:, value:)
            @id = id
            @value = value
          end

          def initialize_copy(original)
            @id = original.id.dup
            @value = original.value.dup
          end
        end

        attr_accessor :left, :right

        def initialize(left:, right:)
          @left = left
          @right = right
        end

        def initialize_copy(original)
          @left = original.left.dup
          @right = original.right.dup
        end

        def create?
          left.nil? && !right.nil?
        end

        def update?
          !left.nil? && !right.nil?
        end

        def delete?
          !left.nil? && right.nil?
        end
      end

      attr_accessor :create, :update, :delete

      def initialize
        @create = []
        @update = []
        @delete = []
      end

      def empty?
        create.empty? && update.empty? && delete.empty?
      end

      def diffs
        result = []

        @create.each do |creation|
          right = Diff::Object.new(id: creation[1].tracking_id, value: creation[1])
          result << Diff.new(left: nil, right: right)
        end

        @update.each do |update|
          left = Diff::Object.new(id: update[1].tracking_id, value: update[1])
          right = Diff::Object.new(id: update[1].tracking_id, value: update[2])
          result << Diff.new(left: left, right: right)
        end

        @delete.each do |deletion|
          left = Diff::Object.new(id: deletion[2][:tracking_id], value: deletion[2])
          result << Diff.new(left: left, right: nil)
        end

        result
      end
    end
  end
end
