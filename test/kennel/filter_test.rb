# frozen_string_literal: true
require_relative "../test_helper"

SingleCov.covered!

describe Kennel::Filter do
  describe "#initialize" do
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
      it "works when they agree" do
        f = with_env("PROJECT" => "foo,bar", "TRACKING_ID" => "foo:x,bar:y") do
          Kennel::Filter.new
        end
        f.project_filter.must_equal(["bar", "foo"])
        f.tracking_id_filter.must_equal(["bar:y", "foo:x"])
      end

      it "raises when they disagree" do
        e = assert_raises(RuntimeError) do
          with_env("PROJECT" => "foo,bar", "TRACKING_ID" => "foo:x,baz:y") do
            Kennel::Filter.new
          end
        end
        e.message.must_include("do not set PROJECT= when using TRACKING_ID=")
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
  end

  # test logic that filter_parts and filter_projects share
  describe "#filter_projects!" do
    it "filters nothing when not active" do
      Kennel::Filter.new.filter_projects([1]).must_equal [1]
    end

    it "filters by project id" do
      projects = [stub("P1", kennel_id: "a"), stub("P2", kennel_id: "b")]
      with_env PROJECT: "a" do
        projects = Kennel::Filter.new.filter_projects(projects)
      end
      projects.map(&:kennel_id).must_equal ["a"]
    end
  end

  describe "#filter_parts" do
    it "filters nothing when not active" do
      Kennel::Filter.new.filter_parts([1]).must_equal [1]
    end

    it "filters by project id" do
      parts = [stub("P1", tracking_id: "a"), stub("P2", tracking_id: "b")]
      with_env TRACKING_ID: "a" do
        parts = Kennel::Filter.new.filter_parts(parts)
      end
      parts.map(&:tracking_id).must_equal ["a"]
    end
  end

  describe "#filter_resources!" do
    let(:struct) { Struct.new(:some_property) }
    let(:foo) { struct.new("foo") }
    let(:bar) { struct.new("bar") }
    let(:baz) { struct.new("baz") }
    let(:another_foo) { struct.new("foo") }
    let(:things) { [foo, bar, another_foo] }

    def run_filter(allow)
      Kennel::Filter.new.send(:filter_resources, things, :some_property, allow, "things", "SOME_PROPERTY_ENV_VAR")
    end

    it "is a no-op if the filter is unset" do
      run_filter(nil).must_equal(things)
    end

    it "filters (1 spec, 1 match)" do
      run_filter(["bar"]).must_equal([bar])
    end

    it "filters (1 spec, > 1 match)" do
      run_filter(["foo"]).must_equal([foo, another_foo])
    end

    it "filters (repeated spec, 1 match)" do
      run_filter(["bar", "bar"]).must_equal([bar])
    end

    it "filters (repeated spec, > 1 match)" do
      run_filter(["foo", "foo"]).must_equal([foo, another_foo])
    end

    it "filters (> 1 spec, 1 match each)" do
      things << baz
      run_filter(["bar", "baz"]).must_equal([bar, baz])
    end

    it "filters (> 1 spec, > 1 match for some)" do
      things << baz
      run_filter(["foo", "bar"]).must_equal([foo, bar, another_foo])
    end
  end
end
