# frozen_string_literal: true
require_relative "../test_helper"

SingleCov.covered!

describe Kennel::Filter do
  describe ".from" do
    it "works with nil" do
      f = Kennel::Filter.from(nil, nil)
      f.project_filter.must_be_nil
      f.tracking_id_filter.must_be_nil
    end

    it "works with arrays" do
      f = Kennel::Filter.from(["x"], ["y"])
      f.project_filter.must_equal(["x"])
      f.tracking_id_filter.must_equal(["y"])
    end
  end

  describe "#filtering?" do
    it "works without project, without tracking_id" do
      with_env("PROJECT" => nil, "TRACKING_ID" => nil) do
        refute Kennel::Filter.new.filtering?
      end
    end

    it "works with project, without tracking_id" do
      with_env("PROJECT" => "foo", "TRACKING_ID" => nil) do
        assert Kennel::Filter.new.filtering?
      end
    end

    it "works without project, with tracking_id" do
      with_env("PROJECT" => nil, "TRACKING_ID" => "foo:bar") do
        assert Kennel::Filter.new.filtering?
      end
    end
  end

  describe "#project_id_in_scope?" do
    it "works without project, without tracking_id" do
      with_env("PROJECT" => nil, "TRACKING_ID" => nil) do
        assert Kennel::Filter.new.project_id_in_scope?("foo")
      end
    end

    it "works with project, without tracking_id" do
      with_env("PROJECT" => "foo,foo1", "TRACKING_ID" => nil) do
        assert Kennel::Filter.new.project_id_in_scope?("foo")
        assert Kennel::Filter.new.project_id_in_scope?("foo1")
        refute Kennel::Filter.new.project_id_in_scope?("foo2")
      end
    end

    it "works without project, with tracking_id" do
      with_env("PROJECT" => nil, "TRACKING_ID" => "foo:bar,foo1:bar1") do
        assert Kennel::Filter.new.project_id_in_scope?("foo")
        assert Kennel::Filter.new.project_id_in_scope?("foo1")
        refute Kennel::Filter.new.project_id_in_scope?("foo2")
      end
    end
  end

  describe "#tracking_id_in_scope?" do
    it "works without project, without tracking_id" do
      with_env("PROJECT" => nil, "TRACKING_ID" => nil) do
        assert Kennel::Filter.new.tracking_id_in_scope?("foo:bar")
      end
    end

    it "works with project, without tracking_id" do
      with_env("PROJECT" => "foo,foo1", "TRACKING_ID" => nil) do
        assert Kennel::Filter.new.tracking_id_in_scope?("foo:bar")
        assert Kennel::Filter.new.tracking_id_in_scope?("foo1:bar")
        refute Kennel::Filter.new.tracking_id_in_scope?("foo2:bar2")
      end
    end

    it "works without project, with tracking_id" do
      with_env("PROJECT" => nil, "TRACKING_ID" => "foo:bar,foo1:bar1") do
        assert Kennel::Filter.new.tracking_id_in_scope?("foo:bar")
        assert Kennel::Filter.new.tracking_id_in_scope?("foo1:bar1")
        refute Kennel::Filter.new.tracking_id_in_scope?("foo2:bar2")
      end
    end
  end

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
      Kennel::Filter.new.send(:filter_resources, things, :some_property, allow, "things", "SOME_PROPERTY_ENV_VAR", [])
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

  describe "no-match warnings" do
    capture_all

    context "with project, without tracking_id" do
      it "does not warn if all elements match something" do
        with_env("PROJECT" => "foo,bar", "TRACKING_ID" => nil) do
          projects = [stub("P1", kennel_id: "foo")]
          Kennel::PartsSerializer.stubs(:existing_project_ids).returns(["bar"])
          Kennel::Filter.new.filter_projects(projects)
          stderr.string.must_equal ""
        end
      end

      it "warns about elements which match nothing" do
        with_env("PROJECT" => "foo,bar,baz,quux", "TRACKING_ID" => nil) do
          projects = [stub("P1", kennel_id: "foo")]
          Kennel::PartsSerializer.stubs(:existing_project_ids).returns(["bar"])
          Kennel::Filter.new.filter_projects(projects)
          stderr.string.must_equal "Warning: the following filter terms didn't match anything: baz, quux\n"
        end
      end
    end

    context "without project, with tracking_id" do
      it "does not warn if all elements match something" do
        with_env("PROJECT" => nil, "TRACKING_ID" => "foo:x,bar:x") do
          projects = [stub("P1", kennel_id: "foo")]
          Kennel::PartsSerializer.stubs(:existing_project_ids).returns(["bar"])
          Kennel::Filter.new.filter_projects(projects)
          stderr.string.must_equal ""
        end
      end

      it "warns about project id elements which match nothing" do
        with_env("PROJECT" => nil, "TRACKING_ID" => "foo:x,bar:x,baz:x,quux:x") do
          projects = [stub("P1", kennel_id: "foo")]
          Kennel::PartsSerializer.stubs(:existing_project_ids).returns(["bar"])
          Kennel::Filter.new.filter_projects(projects)
          stderr.string.must_equal "Warning: the following filter terms didn't match anything: baz, quux\n"
        end
      end

      it "does not warn about tracking id elements if everything matches something" do
        with_env("PROJECT" => nil, "TRACKING_ID" => "foo:x,bar:x") do
          parts = [stub("P1", tracking_id: "foo:x")]
          Kennel::PartsSerializer.stubs(:existing_tracking_ids).returns(["bar:x"])
          Kennel::Filter.new.filter_parts(parts)
          stderr.string.must_equal ""
        end
      end

      it "warns about tracking id elements which match nothing" do
        with_env("PROJECT" => nil, "TRACKING_ID" => "foo:x,bar:x,baz:x,quux:x") do
          parts = [stub("P1", tracking_id: "foo:x")]
          Kennel::PartsSerializer.stubs(:existing_tracking_ids).returns(["bar:x"])
          Kennel::Filter.new.filter_parts(parts)
          stderr.string.must_equal "Warning: the following filter terms didn't match anything: baz:x, quux:x\n"
        end
      end
    end
  end
end
