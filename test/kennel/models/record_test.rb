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

  describe "#initialize" do
    it "complains when passing invalid project" do
      e = assert_raises(ArgumentError) { TestRecord.new(123) }
      e.message.must_equal "First argument must be a project, not Integer"
    end
  end

  describe "#invalid!" do
    it "raises a validation error whit project name to help when backtrace is generic" do
      e = assert_raises Kennel::ValidationError do
        Kennel::Models::Monitor.new(TestProject.new, name: -> { "My Bad monitor" }, kennel_id: -> { "x" }).send(:invalid!, "X")
      end
      e.message.must_equal "test_project:x X"
    end
  end

  describe "#resolve_link" do
    let(:base) { Kennel::Models::Monitor.new(TestProject.new, kennel_id: -> { "test" }) }

    it "resolves" do
      base.send(:resolve_link, "foo", :monitor, "foo" => 2).must_equal 2
    end

    it "warns when new but not required" do
      err = Kennel::Utils.capture_stderr do
        base.send(:resolve_link, "foo", :monitor, "foo" => :new).must_equal Kennel::MISSING_ID
      end
      err.must_include "Monitor foo will be created in the current run"
    end

    it "fails when new but required" do
      e = assert_raises Kennel::ValidationError do
        base.send(:resolve_link, "foo", :monitor, { "foo" => :new }, force: true)
      end
      e.message.must_include "test_project:test Monitor foo will be created"
    end

    it "fails when missing" do
      e = assert_raises Kennel::ValidationError do
        base.send(:resolve_link, "foo", :monitor, "bar" => 1)
      end
      e.message.must_include "test_project:test Unable to find monitor foo"
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

  describe ".ignore_default" do
    it "ignores defaults" do
      a = { a: 1 }
      b = { a: 1 }
      Kennel::Models::Dashboard.send(:ignore_default, a, b, a: 1)
      a.must_equal({})
      a.must_equal b
    end

    it "ignores missing left" do
      a = { a: 1 }
      b = {}
      Kennel::Models::Dashboard.send(:ignore_default, a, b, a: 1)
      a.must_equal({})
      b.must_equal a
    end

    it "ignores missing right" do
      a = {}
      b = { a: 1 }
      Kennel::Models::Dashboard.send(:ignore_default, a, b, a: 1)
      a.must_equal({})
      b.must_equal a
    end

    it "keeps uncommon" do
      a = {}
      b = { a: 2 }
      Kennel::Models::Dashboard.send(:ignore_default, a, b, a: 1)
      a.must_equal({})
      b.must_equal a: 2
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
