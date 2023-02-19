# frozen_string_literal: true
require_relative "../test_helper"

SingleCov.covered!

describe Kennel::AttrPredicate do
  def make_test(happy:)
    Class.new do
      include Kennel::AttrPredicate
      attr_predicate :happy?

      def initialize(happy:)
        @happy = happy
      end
    end.new(happy: happy)
  end

  it "adds predicate accessors" do
    assert make_test(happy: true).happy?
  end

  it "rejects invalid predicate names" do
    assert_raises(NameError) do
      Class.new do
        include Kennel::AttrPredicate
        attr_predicate :size
      end
    end
  end

  it "coerces falsey to false" do
    assert_equal make_test(happy: nil).happy?, false
  end

  it "coerces truthy to true" do
    assert_equal make_test(happy: "yes").happy?, true
  end
end
