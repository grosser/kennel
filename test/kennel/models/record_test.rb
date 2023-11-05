# frozen_string_literal: true
require_relative "../../test_helper"

SingleCov.covered!

describe Kennel::Models::Record do
  define_test_classes

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

  describe "#build" do
    it "works normally on valid json" do
      record = Kennel::Models::Record.new(TestProject.new, kennel_id: "x")
      some_json = { some: "json" }
      record.define_singleton_method(:build_json) { some_json }
      record.define_singleton_method(:validate_json) { |data| data.must_equal(some_json) }
      record.build
      record.validation_errors.must_equal []
      record.as_json.must_equal some_json
    end

    it "is capable of collecting multiple errors" do
      record = Kennel::Models::Record.new(TestProject.new, kennel_id: "x")
      record.define_singleton_method(:validate_json) do |_data|
        invalid! :one, "one"
        invalid! :two, "two"
      end
      record.build
      record.validation_errors.map(&:text).must_equal ["one", "two"]
      assert record.instance_variable_get(:@as_json) # for debugging
    end
  end

  describe "#validate_json" do
    def expect_error(bad)
      errors.length.must_equal 1
      errors[0].text.must_match(/Only use Symbols as hash keys/)
      errors[0].text.must_match(/'foo' => 1 --> 'foo': 1/)
      found = errors[0].text.scan(/^"(.*?)"$/m).flatten
      found.must_equal(bad)
    end

    let(:item) { TestRecord.new(TestProject.new) }
    let(:errors) { item.validation_errors }

    before { item.instance_variable_set(:@validation_errors, []) } # what `build` does

    it "passes on symbols" do
      item.send(:validate_json, { some_key: "bar" })
      errors.must_equal []
    end

    it "fails on strings" do
      item.send(:validate_json, { "some_key" => "bar" })
      expect_error(["some_key"])
    end

    it "checks inside hashes" do
      item.send(:validate_json, { outer: { "some_key" => "bar" } })
      expect_error(["some_key"])
    end

    it "checks inside arrays" do
      item.send(:validate_json, { outer: [{ "some_key" => "bar" }] })
      expect_error(["some_key"])
    end

    it "reports all bad keys" do
      data = {
        "bad_y" => 1,
        :good => {
          "bad_x" => 1,
          :good_z => { "bad_y" => 0 }
        }
      }
      item.send(:validate_json, data)
      expect_error(["bad_x", "bad_y"])
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

  describe "#safe_tracking_id" do
    it "shows something useful when crashing" do
      monitor.stubs(:tracking_id).raises("foo")
      monitor.safe_tracking_id.must_equal "<unknown; #tracking_id crashed>"
    end
  end

  describe "#add_tracking_id" do
    it "adds" do
      monitor.build
      monitor.as_json[:message].wont_include "kennel"
      monitor.add_tracking_id
      monitor.as_json[:message].must_include "kennel"
    end

    it "fails when it would have been added twice (user already added it by mistake)" do
      monitor.build
      monitor.add_tracking_id
      assert_raises(RuntimeError) { monitor.add_tracking_id }.message.must_include("to copy a resource")
    end
  end

  describe "#remove_tracking_id" do
    it "removes" do
      monitor.build
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

    it "alerts when guard condition is ineffective" do
      # if something is "diff equal" but not "==" then we are leaving speed on the table
      Hashdiff.expects(:diff).returns []
      e = assert_raises(RuntimeError) { diff_resource({ a: 1 }, a: 2) }
      e.message.must_include "Empty diff detected"
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
