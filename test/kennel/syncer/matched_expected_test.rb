# frozen_string_literal: true

require_relative "../../test_helper"

# Covered by syncer_test.rb
SingleCov.covered!

describe Kennel::Syncer::MatchedExpected do
  let(:monitor) { Kennel::Models::Monitor }
  let(:dashboard) { Kennel::Models::Dashboard }
  let(:expected) { [] }
  let(:actual) { [] }
  let(:result) { Kennel::Syncer::MatchedExpected.partition(expected, actual) }
  let(:matched) { result[0] }
  let(:unmatched_expected) { result[1] }
  let(:unmatched_actual) { result[2] }

  def make_expected(tracking_id, klass, id)
    stub("expected", tracking_id: tracking_id, class: klass, id: id, allowed_update_error: nil)
  end

  def make_actual(tracking_id, klass, id)
    raise "actual object always have an id" unless id
    { tracking_id: tracking_id, klass: klass, id: id }
  end

  describe "basic matching" do
    it "creates when nothing maches" do
      e = make_expected("foo:bar", monitor, nil)
      expected << e

      matched.must_be_empty
      unmatched_expected.must_equal [e]
      unmatched_actual.must_be_empty
    end

    it "updates when matching by tracking id" do
      e = make_expected("foo:bar", monitor, nil)
      a = make_actual("foo:bar", monitor, 999)
      expected << e
      actual << a

      matched.must_equal [[e, a]]
      unmatched_expected.must_be_empty
      unmatched_actual.must_be_empty
    end

    it "deletes when removed" do
      a = make_actual("foo:bar", monitor, 999)
      actual << a

      matched.must_be_empty
      unmatched_expected.must_be_empty
      unmatched_actual.must_equal [a]
    end

    it "does triggers a re-create when the update would be rejected by datadog" do
      e = make_expected("foo:bar", monitor, nil)
      a = make_actual("foo:bar", monitor, 999)
      e.stubs(:allowed_update_error).returns("nope")
      expected << e
      actual << a

      matched.must_equal []
    end
  end

  describe "expected with id" do
    it "can matches even when tracking id does not match" do
      e = make_expected("foo:bar", monitor, 999)
      a = make_actual(nil, monitor, 999)
      expected << e
      actual << a

      matched.must_equal [[e, a]]
      unmatched_expected.must_be_empty
      unmatched_actual.must_be_empty
    end

    # the id will not match on the next update, but this blocks errors when something was deleted via UI
    it "matches even when resource was deleted" do
      e = make_expected("foo:bar", monitor, 999)
      expected << e

      matched.must_be_empty
      unmatched_expected.must_equal [e]
      unmatched_actual.must_be_empty
    end

    it "matches" do
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

    it "matches on api_resource and id" do
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

    it "does not allow updating when the update would be rejected by datadog" do
      e = make_expected("foo:bar", monitor, 999)
      a = make_actual("foo:bar", monitor, 999)
      e.stubs(:allowed_update_error).returns("nope")
      expected << e
      actual << a

      assert_raises(Kennel::DisallowedUpdateError) { matched }
    end
  end

  describe "duplicate tracking ids / import ids" do
    # for example bad naming or copy-paste
    it "raises on duplicate tracking_id in expected" do
      expected << make_expected("foo:bar", monitor, nil)
      expected << make_expected("foo:bar", dashboard, nil)

      assert_raises(RuntimeError) { result }.message.must_equal "Lookup foo:bar is duplicated"
    end

    # for example user copy-pasted or imported and existing monitor definition
    it "raises on duplicate id in expected" do
      expected << make_expected("foo:bar", monitor, 999)
      expected << make_expected("foo:baz", monitor, 999)

      assert_raises(RuntimeError) { result }.message.must_equal "Lookup monitor:999 is duplicated"
    end

    # this happens when users clone a resource
    it "does not raise on duplicate tracking_id in actual" do
      actual << make_actual("foo:bar", monitor, 111)
      actual << make_actual("foo:bar", dashboard, 222)

      result
    end
  end
end
