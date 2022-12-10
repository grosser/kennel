# frozen_string_literal: true
require_relative "../../test_helper"

SingleCov.covered!

describe Kennel::Models::Record do
  with_preserved_subclass_tracking
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

  describe "#build" do
    it "works normally on valid json" do
      record = Kennel::Models::Record.new(TestProject.new, kennel_id: "x")
      some_json = { some: "json" }
      record.define_singleton_method(:build_json) { some_json }
      record.define_singleton_method(:validate_json) { |data| data.must_equal(some_json) }
      built = record.build
      built.unfiltered_validation_errors.must_equal []
      built.as_json.must_equal some_json
    end

    it "throws if build_json throws, and there were no validation errors" do
      record = Kennel::Models::Record.new(TestProject.new, kennel_id: "x")
      record.define_singleton_method(:build_json) { raise "I crashed :-(" }
      assert_raises("I crashed :-(") { record.build }
    end

    it "throws if validate_json throws, and there were no validation errors" do
      record = Kennel::Models::Record.new(TestProject.new, kennel_id: "x")
      record.define_singleton_method(:validate_json) { |_data| raise "I crashed :-(" }
      assert_raises("I crashed :-(") { record.build }
    end

    it "does not throw if build_json throws after a validation error" do
      record = Kennel::Models::Record.new(TestProject.new, kennel_id: "x")
      record.define_singleton_method(:build_json) do
        invalid! :wrong, "This is all wrong"
        raise "I crashed :-("
      end
      record.build
    end

    it "does not throw if validate_json throws after a validation error" do
      record = Kennel::Models::Record.new(TestProject.new, kennel_id: "x")
      record.define_singleton_method(:validate_json) do |_data|
        invalid! :wrong, "This is all wrong"
        raise "I crashed :-("
      end
      built = record.build
      built.unfiltered_validation_errors.map(&:text).must_equal ["This is all wrong"]
      built.json.wont_be_nil # for debugging
    end

    it "is capable of collecting multiple errors" do
      record = Kennel::Models::Record.new(TestProject.new, kennel_id: "x")
      record.define_singleton_method(:validate_json) do |_data|
        invalid! :one, "one"
        invalid! :two, "two"
      end
      built = record.build
      built.filtered_validation_errors.map(&:text).must_equal ["one", "two"]
      built.json.wont_be_nil # for debugging
    end

    it "can skip validation entirely" do
      record = Kennel::Models::Record.new(TestProject.new, kennel_id: "x", ignored_errors: [:bang])
      record.define_singleton_method(:validate_json) do |_data|
        invalid! :bang, "bang"
      end
      built = record.build

      built.filtered_validation_errors.must_be_empty
      built.as_json.wont_be_nil # it's valid
    end
  end

  describe "#as_json" do
    it "includes the id if set" do
      record = Kennel::Models::Record.new(TestProject.new, kennel_id: "x", id: 123)
      record.build!.as_json.must_equal({ id: 123 })
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

  describe ".parse_tracking_id" do
    let(:klass) do
      Class.new(Kennel::Models::Record).tap do |k|
        k.const_set(:TRACKING_FIELD, :details)
      end
    end

    it "returns the tracking_id if present" do
      text = <<~TEXT
        Hello
        -- Managed by kennel foo:bar in some/file.rb, do not modify manually
      TEXT
      klass.parse_tracking_id(details: text).must_equal "foo:bar"
    end

    it "returns nil otherwise" do
      klass.parse_tracking_id(details: "Hello").must_be_nil
    end
  end

  describe ".remove_tracking_id" do
    let(:klass) do
      Class.new(Kennel::Models::Record).tap do |k|
        k.const_set(:TRACKING_FIELD, :details)
      end
    end

    it "returns the tracking_id if present" do
      text = <<~TEXT
        Hello
        -- Managed by kennel foo:bar in some/file.rb, do not modify manually
        there
      TEXT
      klass.remove_tracking_id(details: text).must_equal "Hello\nthere\n"
    end

    it "raises otherwise" do
      assert_raises do
        klass.remove_tracking_id(details: "Hello")
      end.message.must_include "did not find tracking id"
    end
  end

  describe ".normalize" do
    let(:klass) do
      Class.new(Kennel::Models::Record).tap do |k|
        k.const_set(:READONLY_ATTRIBUTES, [:foo])
      end
    end

    let(:actual) { {foo: 1, bar:  2} }
    let(:expected) { {foo: 3, bar:  4} }

    it "deletes read-only attributes from actual" do
      klass.normalize(expected, actual)
      actual.must_equal(bar: 2)
    end

    it "does not delete read-only attributes from expected" do
      klass.normalize(expected, actual)
      expected.must_equal(foo: 3, bar: 4)
    end
  end

  describe "#build!" do
    it "returns a built part if there were no errors" do
      monitor.build!.must_be_kind_of(Kennel::Models::Built::Record)
    end

    it "raises if there were errors" do
      monitor.define_singleton_method(:validate_json) do |_|
        invalid! :foo, "Foo"
      end

      assert_raises do
        monitor.build!
      end.message.must_include("Invalid record")
    end
  end

  describe "#safe_tracking_id" do
    it "returns tracking id if possible" do
      monitor.safe_tracking_id.must_equal monitor.tracking_id
    end

    it "returns some error text if tracking_id crashes" do
      monitor.define_singleton_method(:tracking_id) { raise "Bang!" }
      monitor.safe_tracking_id.must_equal "<unknown; #tracking_id crashed>"
    end
  end
end
