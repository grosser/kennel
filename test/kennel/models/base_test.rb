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

    it "stores invocation_location" do
      model = Kennel::Models::Monitor.new(TestProject.new)
      location = model.instance_variable_get(:@invocation_location).sub(/:\d+/, ":123")
      location.must_equal "lib/kennel/models/monitor.rb:123:in `initialize'"
    end

    it "stores invocation_location from first outside project line" do
      Kennel::Models::Monitor.any_instance.expects(:caller).returns(
        [
          "/foo/bar.rb",
          "#{Dir.pwd}/baz.rb"
        ]
      )
      model = Kennel::Models::Monitor.new(TestProject.new)
      location = model.instance_variable_get(:@invocation_location).sub(/:\d+/, ":123")
      location.must_equal "baz.rb"
    end
  end

  describe "#kennel_id" do
    it "snake-cases to work as file/tag" do
      TestBase.new.kennel_id.must_equal "test_base"
    end

    it "does not allow using generic names" do
      e = assert_raises ArgumentError do
        Kennel::Models::Monitor.new(TestProject.new).kennel_id
      end
      message = e.message
      assert message.sub!(/ \S+?:\d+/, " file.rb:123")
      message.must_equal "Set :kennel_id for project test_project on file.rb:123:in `initialize'"
    end

    it "does not allow using generic names for projects" do
      e = assert_raises ArgumentError do
        Kennel::Models::Project.new.kennel_id
      end
      message = e.message
      assert message.sub!(/\S+?:\d+/, "file.rb:123")
      message.must_equal "Set :kennel_id on file.rb:123:in `new'"
    end

    it "does fail when invocation location could not be found" do
      e = assert_raises ArgumentError do
        model = Kennel::Models::Monitor.new(TestProject.new)
        model.instance_variable_set(:@invocation_location, nil)
        model.kennel_id
      end
      message = e.message
      message.must_equal "Set :kennel_id for project test_project"
    end

    it "does not allow using generic names" do
      e = assert_raises ArgumentError do
        Kennel::Models::Monitor.new(TestProject.new, name: -> { "My Bad monitor" }).kennel_id
      end
      message = e.message
      assert message.sub!(/ \S+?:\d+/, " file.rb:123")
      message.must_equal "Set :kennel_id for project test_project on file.rb:123:in `initialize'"
    end
  end

  describe "#name" do
    it "is readable for nice names in the UI" do
      TestBase.new.name.must_equal "TestBase"
    end
  end

  describe "#invalid!" do
    it "raises a validation error whit project name to help when backtrace is generic" do
      e = assert_raises Kennel::Models::Base::ValidationError do
        Kennel::Models::Monitor.new(TestProject.new, name: -> { "My Bad monitor" }, kennel_id: -> { "x" }).send(:invalid!, "X")
      end
      e.message.must_equal "test_project:x X"
    end
  end

  describe ".ignore_request_defaults" do
    let(:valid) { { a: [{ b: { requests: [{ c: 1 }] } }] } }

    it "does not change valid" do
      copy = deep_dup(valid)
      Kennel::Models::Base.send(:ignore_request_defaults, valid, valid, :a, :b)
      valid.must_equal copy
    end

    it "removes defaults" do
      copy = deep_dup(valid)
      valid.dig(:a, 0, :b, :requests, 0)[:conditional_formats] = []
      Kennel::Models::Base.send(:ignore_request_defaults, valid, valid, :a, :b)
      valid.must_equal copy
    end

    it "removes defaults when only a single side is given" do
      copy = deep_dup(valid)
      other = deep_dup(valid)
      copy.dig(:a, 0, :b, :requests, 0)[:conditional_formats] = []
      other.dig(:a, 0, :b, :requests).pop
      Kennel::Models::Base.send(:ignore_request_defaults, copy, other, :a, :b)
      copy.must_equal valid
    end

    it "does not remove non-defaults" do
      valid.dig(:a, 0, :b, :requests, 0)[:conditional_formats] = [111]
      copy = deep_dup(valid)
      Kennel::Models::Base.send(:ignore_request_defaults, valid, valid, :a, :b)
      valid.must_equal copy
    end

    it "skips newly added requests" do
      copy = deep_dup(valid)
      copy.dig(:a, 0, :b, :requests).clear
      Kennel::Models::Base.send(:ignore_request_defaults, valid, copy, :a, :b)
      valid.must_equal a: [{ b: { requests: [c: 1] } }]
      copy.must_equal a: [{ b: { requests: [] } }]
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

    it "does not allow overwriting base methods" do
      e = assert_raises(ArgumentError) { DefaultTestBase.settings(:diff) }
      e.message.must_equal "Settings :diff are already used as methods"
    end
  end

  describe ".diff" do
    # minitest defines diff, do not override it
    def diff_resource(e, a)
      default = { tags: [] }
      Kennel::Models::Base.new(as_json: -> { default.merge(e) }).diff(default.merge(a))
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
      base = TestBase.new
      def base.project
        TestProject.new
      end
      base.tracking_id.must_equal "test_project:test_base"
    end
  end

  describe ".to_json" do
    it "blows up when used by accident instead of rendering unexpected json" do
      assert_raises(NotImplementedError) { TestBase.new.to_json }
    end
  end
end
