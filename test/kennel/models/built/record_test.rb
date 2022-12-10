# frozen_string_literal: true
require_relative "../../../test_helper"

SingleCov.covered!

describe Kennel::Models::Built::Record do
  with_test_classes

  let(:built) {
    Kennel::Models::Built::Monitor.new(
      as_json: { message: "Some text" },
      project: TestProject.new,
      unbuilt_class: Kennel::Models::Monitor,
      tracking_id: "test_project:test",
      id: nil,
      unfiltered_validation_errors: []
    )
  }

  let(:id_map) { Kennel::IdMap.new }

  it "has no errors" do
    built.filtered_validation_errors.must_be_empty
  end

  describe "#resolve" do
    it "lets non-tracking-ids through unchanged" do
      built.resolve("foobar", :slo, id_map, force: false).must_equal "foobar"
    end

    it "resolves existing" do
      id_map.set("monitor", "foo:bar", 2)
      id_map.set("monitor", "foo:bar", 2)
      built.resolve("foo:bar", :monitor, id_map, force: false).must_equal 2
    end

    it "warns when trying to resolve" do
      id_map.set("monitor", "foo:bar", Kennel::IdMap::NEW)
      built.resolve("foo:bar", :monitor, id_map, force: false).must_be_nil
    end

    it "fails when forcing resolve because of a circular dependency" do
      id_map.set("monitor", "foo:bar", Kennel::IdMap::NEW)
      e = assert_raises Kennel::UnresolvableIdError do
        built.resolve("foo:bar", :monitor, id_map, force: true)
      end
      e.message.must_include "circular dependency"
    end

    it "fails when trying to resolve but it is unresolvable" do
      id_map.set("monitor", "foo:bar", 1)
      e = assert_raises Kennel::UnresolvableIdError do
        built.resolve("foo:xyz", :monitor, id_map, force: false)
      end
      e.message.must_include "test_project:test Unable to find monitor foo:xyz"
    end
  end

  describe "#add_tracking_id" do
    it "adds" do
      built.as_json[:message].wont_include "kennel"
      built.add_tracking_id
      built.as_json[:message].must_include "kennel"
    end

    it "fails when it would have been added twice (user already added it by mistake)" do
      built.add_tracking_id
      assert_raises(RuntimeError) { built.add_tracking_id }.message.must_include("to copy a resource")
    end
  end

  describe "#remove_tracking_id" do
    it "removes" do
      old = built.as_json[:message].dup
      built.add_tracking_id
      built.remove_tracking_id
      built.as_json[:message].must_equal old
    end
  end

  describe "#invalid_update!" do
    it "raises the right error" do
      error = assert_raises(Kennel::DisallowedUpdateError) { built.invalid_update!(:foo, "bar", "baz") }
      error.message.must_equal("#{built.tracking_id} Datadog does not allow update of foo (\"bar\" -> \"baz\")")
    end
  end

  describe "#diff" do
    # minitest defines diff, do not override it
    def diff_resource(e, a)
      default = { tags: [] }
      b = Kennel::Models::Built::Record.new(
        as_json: default.merge(e),
        project: TestProject.new,
        unbuilt_class: Kennel::Models::Record,
        tracking_id: "a:b",
        id: nil,
        unfiltered_validation_errors: [],
      )
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
      diff_resource({}, klass: String).must_equal []
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
end
