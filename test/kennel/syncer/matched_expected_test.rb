# frozen_string_literal: true

require_relative "../../test_helper"

# Covered by syncer_test.rb
SingleCov.covered!

describe Kennel::Syncer::MatchedExpected do
  let(:monitor) { Kennel::Models::Monitor }
  let(:dashboard) { Kennel::Models::Dashboard }

  let(:expected_class) { Struct.new(:tracking_id, :class, :id) } # rubocop:disable Lint/StructNewOverride

  let(:expected) { [] }
  let(:actual) { [] }

  let(:result) { Kennel::Syncer::MatchedExpected.partition(expected, actual) }

  let(:matched) { result[0] }
  let(:unmatched_expected) { result[1] }
  let(:unmatched_actual) { result[2] }

  def make_expected(tracking_id, klass, id)
    expected_class.new(tracking_id, klass, id)
  end

  def make_actual(tracking_id, klass, id)
    { tracking_id: tracking_id, klass: klass, id: id }
  end

  describe "basic matching" do
    it "create" do
      e = make_expected("foo:bar", monitor, nil)
      expected << e

      matched.must_be_empty
      unmatched_expected.must_equal [e]
      unmatched_actual.must_be_empty
    end

    it "update" do
      e = make_expected("foo:bar", monitor, nil)
      a = make_actual("foo:bar", monitor, 999)
      expected << e
      actual << a

      matched.must_equal [[e, a]]
      unmatched_expected.must_be_empty
      unmatched_actual.must_be_empty
    end

    it "delete" do
      a = make_actual("foo:bar", monitor, 999)
      actual << a

      matched.must_be_empty
      unmatched_expected.must_be_empty
      unmatched_actual.must_equal [a]
    end
  end

  describe "expected with id" do
    it "can import" do
      e = make_expected("foo:bar", monitor, 999)
      a = make_actual(nil, monitor, 999)
      expected << e
      actual << a

      matched.must_equal [[e, a]]
      unmatched_expected.must_be_empty
      unmatched_actual.must_be_empty
    end

    it "ignores id if no match" do
      e = make_expected("foo:bar", monitor, 999)
      expected << e

      matched.must_be_empty
      unmatched_expected.must_equal [e]
      unmatched_actual.must_be_empty
    end

    it "matches on id" do
      e = make_expected("foo:bar", monitor, 999)
      a = make_actual(nil, monitor, 777)
      b = make_actual(nil, monitor, 999)
      expected << e
      actual << a
      actual << b

      matched.must_equal [[e, b]]
      unmatched_expected.must_be_empty
      unmatched_actual.must_equal [a]
    end

    it "matches on api_resource" do
      e = make_expected("foo:bar", monitor, 999)
      a = make_actual(nil, dashboard, 999)
      b = make_actual(nil, monitor, 999)
      expected << e
      actual << a
      actual << b

      matched.must_equal [[e, b]]
      unmatched_expected.must_be_empty
      unmatched_actual.must_equal [a]
    end
  end

  describe "duplicate tracking ids / import ids" do
    it "raises on duplicate tracking_id in expected" do
      expected << make_expected("foo:bar", monitor, nil)
      expected << make_expected("foo:bar", dashboard, nil)

      assert_raises(RuntimeError) { result }.message.must_equal "Lookup foo:bar is duplicated"
    end

    it "raises on duplicate id in expected" do
      expected << make_expected("foo:bar", monitor, 999)
      expected << make_expected("foo:baz", monitor, 999)

      assert_raises(RuntimeError) { result }.message.must_equal "Lookup monitor:999 is duplicated"
    end

    it "does not raise on duplicate tracking_id in actual" do
      actual << make_actual("foo:bar", monitor, nil)
      actual << make_actual("foo:bar", dashboard, nil)

      result
    end
  end

  describe "resolution order" do
    it "prefers tracking_id over id" do
      e0 = make_expected("a:a", monitor, 999)
      e1 = make_expected("b:b", monitor, 777)
      a = make_actual("a:a", monitor, 777)
      expected << e0
      expected << e1
      actual << a

      matched.must_equal [[e0, a]]
      unmatched_expected.must_equal [e1]
      unmatched_actual.must_be_empty
    end
  end

  it "refuses to match on tracking_id if the api_resource is different" do
    e = make_expected("a:a", monitor, nil)
    a = make_actual("a:a", dashboard, 999)
    expected << e
    actual << a

    matched.must_be_empty
    unmatched_expected.must_equal [e]
    unmatched_actual.must_equal [a]
  end
end
