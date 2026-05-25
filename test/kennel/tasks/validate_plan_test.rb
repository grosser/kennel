# frozen_string_literal: true
require_relative "../../test_helper"
require "rake"
require "kennel/tasks"

SingleCov.covered! uncovered: 3 # rake task part

describe Kennel::ValidatePlan do
  def build_create(api_resource: "monitor", expected: self.expected)
    klass = stub("klass", api_resource: api_resource)
    expected.stubs(:class).returns(klass)
    Kennel::Syncer::Types::PlannedCreate.new(expected)
  end

  def build_update(api_resource: "monitor", expected: self.expected, diff: [["~", "query", "old", "new"]])
    klass = stub("klass", api_resource: api_resource)
    expected.stubs(:class).returns(klass)
    actual = { id: 123, klass: klass, tracking_id: "team:my-monitor" }
    Kennel::Syncer::Types::PlannedUpdate.new(expected, actual, diff)
  end

  def build_plan(creates: [], updates: [])
    stub("plan", creates: creates, updates: updates)
  end

  let(:api) { stub("API") }
  let(:expected) { stub("expected", as_json: { "query" => "avg:foo{*}" }, tracking_id: "team:my-monitor") }

  describe Kennel::ValidatePlan::MonitorValidator do
    let(:validator) { Kennel::ValidatePlan::MonitorValidator.new(build_create) }

    describe "#validate" do
      it "succeeds" do
        api.expects(:request).with(:post, "/api/v1/monitor/validate", body: expected.as_json)
        validator.validate(api).must_be_nil
      end

      it "returns error message on failure" do
        api.expects(:request).raises(RuntimeError.new("bad query"))
        result = validator.validate(api)
        result.must_include "monitor team:my-monitor"
        result.must_include "bad query"
      end

      it "skips composite monitors with unresolved ids" do
        expected.stubs(:as_json).returns(type: "composite", query: "%{foo} && %{bar}") # rubocop:disable Style/FormatStringToken
        api.expects(:request).never
        validator.validate(api).must_be_nil
      end

      it "validates composite monitors with resolved ids" do
        expected.stubs(:as_json).returns(type: "composite", query: "123 && 456")
        api.expects(:request).with(:post, "/api/v1/monitor/validate", body: { type: "composite", query: "123 && 456" })
        validator.validate(api).must_be_nil
      end
    end
  end

  describe Kennel::ValidatePlan::DashboardValidator do
    let(:validator) { Kennel::ValidatePlan::DashboardValidator.new(item) }
    let(:item) { build_create(api_resource: "dashboard", expected: expected) }
    let(:expected) { stub("dashboard_expected", as_json: { widgets: [] }, tracking_id: "team:my-dashboard") }
    let(:placeholder_error) do
      RuntimeError.new(
        %(request:\n{}\nresponse:\n{"errors":["unable to parse invalid_metric_do_not_update"]})
      )
    end

    describe "#validate" do
      it "succeeds when api rejects the placeholder widget" do
        api.expects(:create).with("dashboard", includes(:widgets)).raises(placeholder_error)
        validator.validate(api).must_be_nil
      end

      it "returns error message when the api rejects widgets other than the placeholder" do
        api.expects(:create)
          .raises(RuntimeError.new('{"errors":["bad widget","unable to parse invalid_metric_do_not_update"]}'))
        validator.validate(api).must_include "team:my-dashboard:"
      end

      it "raises when the error is not json" do
        api.expects(:create).raises(RuntimeError.new("bad widget"))
        e = assert_raises(RuntimeError) { validator.validate(api) }
        e.message.must_include "Unreadable error format: bad widget"
      end

      it "raises when the error json has no errors key" do
        api.expects(:create).raises(RuntimeError.new('{"errors":1}{"foo":"bar"}'))
        e = assert_raises(RuntimeError) { validator.validate(api) }
        e.message.must_include "Unreadable error format"
      end

      it "calls update for existing" do
        create = build_update(api_resource: "dashboard", expected: expected)
        api.expects(:update).with("dashboard", 123, includes(:widgets)).raises(placeholder_error)
        Kennel::ValidatePlan::DashboardValidator.new(create).validate(api).must_be_nil
      end

      it "fails descriptively when the api accepts the invalid dashboard" do
        api.expects(:create).returns({})
        e = assert_raises(RuntimeError) { validator.validate(api) }
        e.message.must_include "should have failed"
      end

      it "does not mutate the expected json" do
        json = { widgets: [] }
        expected.stubs(:as_json).returns(json)
        api.expects(:create).raises(placeholder_error)
        validator.validate(api)
        json[:widgets].must_equal []
      end
    end
  end

  describe ".validate" do
    before do
      Kennel::Api.stubs(:new).returns(api)
    end

    it "does nothing with an empty plan" do
      Kennel::ValidatePlan.validate(build_plan)
    end

    it "skips resources without a validator" do
      Kennel::ValidatePlan.validate(build_plan(creates: [build_create(api_resource: "slo")]))
    end

    it "validates creates" do
      api.expects(:request).with(:post, "/api/v1/monitor/validate", body: expected.as_json)
      Kennel::ValidatePlan.validate(build_plan(creates: [build_create]))
    end

    it "validates updates with non-cosmetic changes" do
      api.expects(:request).with(:post, "/api/v1/monitor/validate", body: expected.as_json)
      Kennel::ValidatePlan.validate(build_plan(updates: [build_update(diff: [["~", "query", "old", "new"]])]))
    end

    it "skips updates with only cosmetic changes" do
      api.expects(:request).never
      Kennel::ValidatePlan.validate(build_plan(updates: [build_update(diff: [["~", "name", "old", "new"]])]))
    end

    it "aborts with a user-readable error when validation fails" do
      api.expects(:request).raises(RuntimeError.new("bad query"))
      capture_stderr do
        e = assert_raises(SystemExit) do
          Kennel::ValidatePlan.validate(build_plan(creates: [build_create]))
        end
        e.status.must_equal 1
      end.must_include "bad query"
    end
  end
end
