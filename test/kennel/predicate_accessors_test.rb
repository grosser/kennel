# frozen_string_literal: true
require_relative "../test_helper"

SingleCov.covered!

describe Kennel::PredicateAccessors do
  def make_test(happy:)
    Class.new do
      include Kennel::PredicateAccessors
      attr_reader :happy?

      def initialize(happy:)
        @happy = happy
      end
    end.new(happy: happy)
  end

  it "adds predicate accessors" do
    assert make_test(happy: true).happy?
  end

  it "still works for normal accessors" do
    c = Class.new do
      include Kennel::PredicateAccessors
      attr_reader :size

      def initialize
        @size = 9001
      end
    end

    assert_equal c.new.size, 9001
  end

  it "coerces falsey to false" do
    assert_equal make_test(happy: nil).happy?, false
  end

  it "coerces truthy to true" do
    assert_equal make_test(happy: "yes").happy?, true
  end
end
