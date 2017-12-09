# frozen_string_literal: true
require_relative "../../test_helper"

SingleCov.covered!

describe Kennel::Models::Base do
  class TestBase < Kennel::Models::Base
    settings :foo, :bar, :override, :unset
    defaults(
      foo: -> { "foo" },
      bar: -> { "bar" },
      override: -> { "parent" }
    )
  end

  class ChildTestBase < TestBase
    settings :baz
    defaults(
      foo: -> { "foo-child" },
      override: -> { "child-#{super()}" }
    )
  end

  class DefaultTestBase < TestBase
    settings :name
  end

  describe "#initialize" do
    it "can set options" do
      TestBase.new(foo: -> { 111 }).foo.must_equal 111
    end

    it "fails when setting unsupported options" do
      e = assert_raises(ArgumentError) { TestBase.new(nope: -> { 111 }) }
      e.message.must_equal "Unsupported setting :nope, supported settings are :foo, :bar, :override, :unset"
    end

    it "fails nicely when given non-hash" do
      e = assert_raises(ArgumentError) { TestBase.new("FOOO") }
      e.message.must_equal "Expected TestBase.new options to be a Hash, got a String"
    end

    it "fails nicely when given non-procs" do
      e = assert_raises(ArgumentError) { TestBase.new(id: 12345) }
      e.message.must_equal "Expected TestBase.new option :id to be Proc, for example `id: -> { 12 }`"
    end
  end

  describe "#kennel_id" do
    it "snaek-cases to work as file/tag" do
      TestBase.new.kennel_id.must_equal "test_base"
    end
  end

  describe "#name" do
    it "is readable for nice names in the UI" do
      TestBase.new.name.must_equal "TestBase"
    end
  end

  describe ".defaults" do
    it "returns defaults" do
      TestBase.new.foo.must_equal "foo"
    end

    it "inherits" do
      ChildTestBase.new.bar.must_equal "bar"
    end

    it "can override" do
      ChildTestBase.new.foo.must_equal "foo-child"
    end

    it "can call super" do
      ChildTestBase.new.override.must_equal "child-parent"
    end

    it "explains when user forgets to set an option" do
      e = assert_raises(ArgumentError) { TestBase.new.unset }
      e.message.must_include "unset for TestBase"
    end

    it "cannot set unknown settings on base" do
      e = assert_raises(ArgumentError) { TestBase.defaults(baz: -> {}) }
      e.message.must_include "Unsupported setting :baz, supported settings are :foo, :bar, :override, :unset"
    end

    it "cannot set unknown settings on child" do
      e = assert_raises(ArgumentError) { ChildTestBase.defaults(nope: -> {}) }
      e.message.must_include "Unsupported setting :nope, supported settings are :foo, :bar, :override, :unset, :baz"
    end
  end

  describe ".settings" do
    it "fails when already defined to avoid confusion and typos" do
      e = assert_raises(ArgumentError) { TestBase.settings :foo }
      e.message.must_equal "Settings :foo are already defined"
    end

    it "does not override defined methods" do
      DefaultTestBase.new.name.must_equal "DefaultTestBase"
    end
  end

  describe ".diff" do
    # minitest defines diff, do not override it
    def diff_resource(e, a)
      default = { tags: [] }
      Kennel::Models::Base.new(as_json: -> { default.merge(e) }).diff(default.merge(a))
    end

    it "is empty when empty" do
      diff_resource({}, {}).must_be_nil
    end

    it "ignores readonly attributes" do
      diff_resource({}, deleted: true).must_be_nil
    end

    it "ignores ids" do
      diff_resource({ id: 123 }, id: 234).must_be_nil
    end

    it "ignores api_resource that syncer adds as a hack to get delete to work" do
      diff_resource({}, api_resource: 234).must_be_nil
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
      base = TestBase.new
      def base.project
        TestProject.new
      end
      base.tracking_id.must_equal "test_project:test_base"
    end
  end
end
