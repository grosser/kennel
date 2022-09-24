# frozen_string_literal: true
require_relative "../test_helper"

SingleCov.covered!

describe Kennel::Filter do
  context "without project, without tracking_id" do
    with_env("PROJECT" => nil, "TRACKING_ID" => nil)

    it "works" do
      f = Kennel::Filter.new
      f.project_filter.must_be_nil
      f.tracking_id_filter.must_be_nil
    end
  end

  context "with project, without tracking_id" do
    it "works" do
      with_env("PROJECT" => "foo,bar", "TRACKING_ID" => nil) do
        f = Kennel::Filter.new
        f.project_filter.must_equal(["bar", "foo"])
        f.tracking_id_filter.must_be_nil
      end
    end
  end

  context "with project, with tracking_id" do
    context "they agree" do
      it "works" do
        with_env("PROJECT" => "foo,bar", "TRACKING_ID" => "foo:x,bar:y") do
          f = Kennel::Filter.new
          f.project_filter.must_equal(["bar", "foo"])
          f.tracking_id_filter.must_equal(["bar:y", "foo:x"])
        end
      end
    end

    context "they disagree" do
      with_env("PROJECT" => "foo,bar", "TRACKING_ID" => "foo:x,baz:y")

      it "raises on .new" do
        e = assert_raises(RuntimeError) do
          Kennel::Filter.new
        end

        e.message.must_include("do not set PROJECT= when using TRACKING_ID=")
      end
    end
  end

  context "without project, with tracking_id" do
    it "works" do
      with_env("PROJECT" => nil, "TRACKING_ID" => "foo:x,bar:y") do
        f = Kennel::Filter.new
        f.project_filter.must_equal(["bar", "foo"])
        f.tracking_id_filter.must_equal(["bar:y", "foo:x"])
      end
    end
  end

  describe ".filter_resources!" do
    let(:struct) { Struct.new(:some_property) }

    let(:foo) { struct.new("foo") }
    let(:bar) { struct.new("bar") }
    let(:baz) { struct.new("baz") }
    let(:another_foo) { struct.new("foo") }
    let(:things) { [foo, bar, another_foo] }

    let(:input) { things.dup }

    def run_filter(allow)
      Kennel::Filter.filter_resources!(things, :some_property, allow, "things", "SOME_PROPERTY_ENV_VAR")
    end

    it "is a no-op if the filter is unset" do
      run_filter nil
      things.must_equal(input)
    end

    it "filters (1 spec, 1 match)" do
      run_filter ["bar"]
      things.must_equal([bar])
    end

    it "filters (1 spec, > 1 match)" do
      run_filter ["foo"]
      things.must_equal([foo, another_foo])
    end

    it "filters (repeated spec, 1 match)" do
      run_filter ["bar", "bar"]
      things.must_equal([bar])
    end

    it "filters (repeated spec, > 1 match)" do
      run_filter ["foo", "foo"]
      things.must_equal([foo, another_foo])
    end

    it "filters (> 1 spec, 1 match each)" do
      things << baz
      run_filter ["bar", "baz"]
      things.must_equal([bar, baz])
    end

    it "filters (> 1 spec, > 1 match for some)" do
      things << baz
      run_filter ["foo", "bar"]
      things.must_equal([foo, bar, another_foo])
    end

    it "raises if nothing matched (1 spec)" do
      e = assert_raises(RuntimeError) do
        run_filter ["baz"]
      end

      e.message.must_include("SOME_PROPERTY_ENV_VAR")
      e.message.must_include("things")
    end

    it "raises if nothing matched (> 1 spec)" do
      e = assert_raises(RuntimeError) do
        run_filter ["foo", "baz"]
      end

      e.message.must_include("SOME_PROPERTY_ENV_VAR")
      e.message.must_include("things")
    end
  end
end
