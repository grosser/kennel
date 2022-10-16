# frozen_string_literal: true
require_relative "../../test_helper"

SingleCov.covered!

describe Kennel::Models::Record do
  with_test_classes

  class TestRecord < Kennel::Models::Record
    settings :foo, :bar, :override, :unset
    defaults(
      foo: -> { "foo" },
      bar: -> { "bar" },
      override: -> { "parent" }
    )

    def self.api_resource
      "test"
    end

    def self.parse_url(*)
      nil
    end
  end

  # pretend that TestRecord doesn't exist so as not to break other tests
  Kennel::Models::Record.subclasses.pop

  let(:monitor) do
    Kennel::Models::Monitor.new(
      TestProject.new,
      kennel_id: -> { "test" },
      type: -> { "query" },
      query: -> { "meh" },
      critical: -> { 10 }
    )
  end

  let(:id_map) { Kennel::IdMap.new }

  describe "#initialize" do
    it "complains when passing invalid project" do
      e = assert_raises(ArgumentError) { TestRecord.new(123) }
      e.message.must_equal "First argument must be a project, not Integer"
    end
  end

  describe "#invalid!" do
    it "raises a validation error whit project name to help when backtrace is generic" do
      e = assert_raises Kennel::ValidationError do
        Kennel::Models::Monitor.new(TestProject.new, name: -> { "My Bad monitor" }, kennel_id: -> { "x" }).send(:invalid!, :some_tag, "X")
      end
      e.tag.must_equal :some_tag
      e.base_message.must_equal "X"
    end
  end

  describe "#resolve" do
    let(:base) { Kennel::Models::Monitor.new(TestProject.new, kennel_id: -> { "test" }) }

    it "lets non-tracking-ids through unchanged" do
      base.send(:resolve, "foobar", :slo, id_map, force: false).must_equal "foobar"
    end

    it "resolves existing" do
      id_map.set("monitor", "foo:bar", 2)
      id_map.set("monitor", "foo:bar", 2)
      base.send(:resolve, "foo:bar", :monitor, id_map, force: false).must_equal 2
    end

    it "warns when trying to resolve" do
      id_map.set("monitor", "foo:bar", Kennel::IdMap::NEW)
      base.send(:resolve, "foo:bar", :monitor, id_map, force: false).must_be_nil
    end

    it "fails when forcing resolve because of a circular dependency" do
      id_map.set("monitor", "foo:bar", Kennel::IdMap::NEW)
      e = assert_raises Kennel::UnresolvableIdError do
        base.send(:resolve, "foo:bar", :monitor, id_map, force: true)
      end
      e.message.must_include "circular dependency"
    end

    it "fails when trying to resolve but it is unresolvable" do
      id_map.set("monitor", "foo:bar", 1)
      e = assert_raises Kennel::UnresolvableIdError do
        base.send(:resolve, "foo:xyz", :monitor, id_map, force: false)
      end
      e.message.must_include "test_project:test Unable to find monitor foo:xyz"
    end
  end

  describe "#add_tracking_id" do
    it "adds" do
      monitor.as_json[:message].wont_include "kennel"
      monitor.add_tracking_id
      monitor.as_json[:message].must_include "kennel"
    end

    it "fails when it would have been added twice (user already added it by mistake)" do
      monitor.add_tracking_id
      assert_raises(RuntimeError) { monitor.add_tracking_id }.message.must_include("to copy a resource")
    end
  end

  describe "#remove_tracking_id" do
    it "removes" do
      old = monitor.as_json[:message].dup
      monitor.add_tracking_id
      monitor.remove_tracking_id
      monitor.as_json[:message].must_equal old
    end
  end

  describe "#invalid_update!" do
    it "raises the right error" do
      error = assert_raises(Kennel::DisallowedUpdateError) { monitor.invalid_update!(:foo, "bar", "baz") }
      error.message.must_equal("#{monitor.tracking_id} Datadog does not allow update of foo (\"bar\" -> \"baz\")")
    end
  end

  describe "#diff" do
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

    it "ignores klass attribute that syncer adds" do
      diff_resource({}, klass: TestRecord).must_equal []
    end

    it "makes tag diffs look neat" do
      diff_resource({ tags: ["a", "b"] }, tags: ["b", "c"]).must_equal([["~", "tags[0]", "b", "a"], ["~", "tags[1]", "c", "b"]])
    end

    it "makes graph diffs look neat" do
      diff_resource({ graphs: [{ requests: [{ foo: "bar" }] }] }, graphs: [{ requests: [{ foo: "baz" }] }]).must_equal(
        [["~", "graphs[0].requests[0].foo", "baz", "bar"]]
      )
    end

    it "ignores numeric class difference since the api is semi random on these" do
      diff_resource({ a: 1 }, a: 1.0).must_equal []
    end
  end

  describe "#tracking_id" do
    it "combines project and id into a human-readable string" do
      base = TestRecord.new TestProject.new
      base.tracking_id.must_equal "test_project:test_record"
    end

    it "fails when adding unparsable characters" do
      project = TestProject.new
      def project.kennel_id
        "hey ho"
      end
      base = TestRecord.new project
      assert_raises(RuntimeError) { base.tracking_id }
    end
  end

  describe "#as_json" do
    let(:record) do
      r = Kennel::Models::Record.new(TestProject.new, kennel_id: "x")

      r.define_singleton_method(:build_json) do
        super().merge(some_field: "some value")
      end

      r
    end

    it "calls build_json" do
      assert_json_equal(record.as_json, { some_field: "some value" })
    end

    it "includes the id if set" do
      record.define_singleton_method(:id) { 123 }
      assert_json_equal(record.as_json, { id: 123, some_field: "some value" })
    end

    it "only calls build_json once" do
      record.stubs(:build_json).once.returns({})
      record.as_json
      record.as_json
    end

    describe "validation" do
      context "no error" do
        it "validates the json" do
          record.stubs(:validate_json).once.with(some_field: "some value")
          record.as_json
        end

        it "rejects unnecessary :skip_validations" do
          record.stubs(:skip_validations).returns([:never_happens])
          e = assert_raises(Kennel::ValidationError) { record.as_json }
          e.tag.must_equal :skip_validations_must_be_unset
        end

        it "rejects unnecessary validate: false" do
          record.stubs(:validate).returns(false)
          e = assert_raises(Kennel::ValidationError) { record.as_json }
          e.tag.must_equal :validate_must_be_unset
        end
      end

      context "an error" do
        before do
          record.define_singleton_method(:validate_json) do |_data|
            invalid! :some_error, "Some error"
          end
        end

        it "throws an error on validation" do
          assert_raises(Kennel::ValidationError) { record.as_json }
        end

        it "can be suppressed via skip_validations" do
          record.define_singleton_method(:skip_validations) { [:some_error] }
          record.as_json
        end

        it "can be suppressed via validate: false" do
          record.define_singleton_method(:validate) { false }
          out, _err = capture_io { with_env("SHOW_VALIDATE_DEPRECATION" => "true") { record.as_json } }
          out.must_include "`validate` is deprecated"
        end
      end
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

  describe ".parse_any_url" do
    it "finds monitor" do
      Kennel::Models::Record.parse_any_url("https://app.datadoghq.com/monitors/123").must_equal ["monitor", 123]
    end

    it "is nil when not found" do
      Kennel::Models::Record.parse_any_url("https://app.datadoghq.com/wut/123").must_be_nil
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

  describe ".api_resource_map" do
    it "builds" do
      Kennel::Models::Record.api_resource_map.must_equal(
        "dashboard" => Kennel::Models::Dashboard,
        "monitor" => Kennel::Models::Monitor,
        "slo" => Kennel::Models::Slo,
        "synthetics/tests" => Kennel::Models::SyntheticTest
      )
    end
  end
end
