# frozen_string_literal: true
require_relative "../../test_helper"

SingleCov.covered!

describe Kennel::Models::Record do
  class TestRecord < Kennel::Models::Record
    settings :foo, :bar, :override, :unset
    defaults(
      foo: -> { "foo" },
      bar: -> { "bar" },
      override: -> { "parent" }
    )
  end

  describe "#invalid!" do
    it "raises a validation error whit project name to help when backtrace is generic" do
      e = assert_raises Kennel::Models::Record::ValidationError do
        Kennel::Models::Monitor.new(TestProject.new, name: -> { "My Bad monitor" }, kennel_id: -> { "x" }).send(:invalid!, "X")
      end
      e.message.must_equal "test_project:x X"
    end
  end

  describe "#resolve_link" do
    let(:base) { Kennel::Models::Monitor.new(TestProject.new, kennel_id: -> { "test" }) }

    it "resolves" do
      base.send(:resolve_link, "foo", { "foo" => 1 }, force: false).must_equal 1
    end

    it "fails with warning" do
      err = Kennel::Utils.capture_stderr do
        base.send(:resolve_link, "bar", { "foo" => 1 }, force: false).must_be_nil
      end
      err.must_include "Unable to find bar in existing monitors"
    end

    it "fails with error" do
      e = assert_raises Kennel::Models::Record::ValidationError do
        base.send(:resolve_link, "bar", { "foo" => 1 }, force: true)
      end
      e.message.must_include "Unable to find bar in existing monitors"
    end
  end

  describe ".ignore_request_defaults" do
    let(:valid) { { a: [{ b: { requests: [{ c: 1 }] } }] } }

    it "does not change valid" do
      copy = deep_dup(valid)
      Kennel::Models::Record.send(:ignore_request_defaults, valid, valid, :a, :b)
      valid.must_equal copy
    end

    it "removes defaults" do
      copy = deep_dup(valid)
      valid.dig(:a, 0, :b, :requests, 0)[:conditional_formats] = []
      Kennel::Models::Record.send(:ignore_request_defaults, valid, valid, :a, :b)
      valid.must_equal copy
    end

    it "removes defaults when only a single side is given" do
      copy = deep_dup(valid)
      other = deep_dup(valid)
      copy.dig(:a, 0, :b, :requests, 0)[:conditional_formats] = []
      other.dig(:a, 0, :b, :requests).pop
      Kennel::Models::Record.send(:ignore_request_defaults, copy, other, :a, :b)
      copy.must_equal valid
    end

    it "does not remove non-defaults" do
      valid.dig(:a, 0, :b, :requests, 0)[:conditional_formats] = [111]
      copy = deep_dup(valid)
      Kennel::Models::Record.send(:ignore_request_defaults, valid, valid, :a, :b)
      valid.must_equal copy
    end

    it "skips newly added requests" do
      copy = deep_dup(valid)
      copy.dig(:a, 0, :b, :requests).clear
      Kennel::Models::Record.send(:ignore_request_defaults, valid, copy, :a, :b)
      valid.must_equal a: [{ b: { requests: [c: 1] } }]
      copy.must_equal a: [{ b: { requests: [] } }]
    end
  end

  describe ".diff" do
    # minitest defines diff, do not override it
    def diff_resource(e, a)
      default = { tags: [] }
      b = Kennel::Models::Record.new TestProject.new
      b.define_singleton_method(:as_json) { default.merge(e) }
      b.diff(default.merge(a))
    end

    it "is empty when empty" do
      diff_resource({}, {}).must_equal []
    end

    it "ignores readonly attributes" do
      diff_resource({}, deleted: true).must_equal []
    end

    it "ignores ids" do
      diff_resource({ id: 123 }, id: 234).must_equal []
    end

    it "ignores api_resource that syncer adds as a hack to get delete to work" do
      diff_resource({}, api_resource: 234).must_equal []
    end

    it "makes tag diffs look neat" do
      diff_resource({ tags: ["a", "b"] }, tags: ["b", "c"]).must_equal([["~", "tags[0]", "b", "a"], ["~", "tags[1]", "c", "b"]])
    end

    it "makes graph diffs look neat" do
      diff_resource({ graphs: [{ requests: [{ foo: "bar" }] }] }, graphs: [{ requests: [{ foo: "baz" }] }]).must_equal(
        [["~", "graphs[0].requests[0].foo", "baz", "bar"]]
      )
    end
  end

  describe ".tracking_id" do
    it "combines project and id into a human-readable string" do
      base = TestRecord.new TestProject.new
      base.tracking_id.must_equal "test_project:test_record"
    end
  end

  describe "#raise_with_location" do
    it "adds project" do
      e = assert_raises ArgumentError do
        TestRecord.new(TestProject.new).send(:raise_with_location, ArgumentError, "hey")
      end
      e.message.must_include "hey for project test_project on lib/kennel/"
    end
  end
end
