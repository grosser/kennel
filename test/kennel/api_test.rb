# frozen_string_literal: true
require_relative "../test_helper"

SingleCov.covered!

describe Kennel::Api do
  let(:api) { Kennel::Api.new("app", "api") }

  describe "#show" do
    it "fetches monitor" do
      stub_datadog_request(:get, "monitor/1234")
        .with(body: nil, headers: { "Content-Type" => "application/json" })
        .to_return(body: { bar: "foo" }.to_json)
      api.show("monitor", 1234).must_equal bar: "foo"
    end

    it "fetches slo" do
      stub_datadog_request(:get, "slo/1234").to_return(body: { data: { bar: "foo" } }.to_json)
      api.show("slo", "1234").must_equal bar: "foo"
    end

    it "can pass params so external users can filter" do
      stub_datadog_request(:get, "monitor/1234", "&foo=bar")
        .with(body: nil, headers: { "Content-Type" => "application/json" })
        .to_return(body: { bar: "foo" }.to_json)
      api.show("monitor", 1234, foo: "bar").must_equal bar: "foo"
    end

    it "does not ignore 404" do
      stub_datadog_request(:get, "monitor/1234").to_return(status: 404)
      assert_raises RuntimeError do
        api.show("monitor", 1234).must_equal({})
      end.message.must_include "Error 404 during GET"
    end
  end

  describe "#list" do
    it "fetches monitors" do
      stub_datadog_request(:get, "monitor", "&foo=bar")
        .with(body: nil, headers: { "Content-Type" => "application/json" })
        .to_return(body: [{ bar: "foo" }].to_json)
      api.list("monitor", foo: "bar").must_equal [{ bar: "foo" }]
    end

    it "fetches dashboards" do
      stub_datadog_request(:get, "dashboard")
        .to_return(body: { dashboards: [{ bar: "foo" }] }.to_json)
      api.list("dashboard").must_equal [{ bar: "foo" }]
    end

    it "shows a descriptive failure when request fails" do
      stub_datadog_request(:get, "monitor", "&foo=bar")
        .to_return(status: 300, body: "foo")
      e = assert_raises(RuntimeError) { api.list("monitor", foo: "bar") }
      e.message.must_equal "Error 300 during GET /api/v1/monitor?foo=bar\nfoo"
    end

    it "paginates slos" do
      stub_datadog_request(:get, "slo", "&limit=1000&offset=0").to_return(body: { data: Array.new(1000) { { bar: "foo" } } }.to_json)
      stub_datadog_request(:get, "slo", "&limit=1000&offset=1000").to_return(body: { data: [{ bar: "foo"  }] }.to_json)
      api.list("slo").size.must_equal 1001
    end

    it "fails when pagination would not work" do
      assert_raises(ArgumentError) { api.list("slo", limit: 100) }
      assert_raises(ArgumentError) { api.list("slo", offset: 100) }
    end
  end

  describe "#create" do
    it "creates a monitor" do
      stub_datadog_request(:post, "monitor")
        .with(body: "{\"foo\":\"bar\"}").to_return(body: { bar: "foo" }.to_json)
      api.create("monitor", foo: "bar").must_equal bar: "foo"
    end

    it "shows a descriptive failure when request fails" do
      stub_datadog_request(:post, "monitor")
        .with(body: "{\"foo\":\"bar\"}").to_return(body: { bar: "foo" }.to_json, status: 300)
      e = assert_raises(RuntimeError) { api.create("monitor", foo: "bar") }
      e.message.must_equal <<~TEXT.strip
        Error 300 during POST /api/v1/monitor
        request:
        {
          \"foo\": \"bar\"
        }
        response:
        {\"bar\":\"foo\"}
      TEXT
    end

    it "unwraps slo array reply" do
      stub_datadog_request(:post, "slo").to_return(body: { data: [{ bar: "foo" }] }.to_json)
      api.create("slo", foo: "bar").must_equal bar: "foo"
    end
  end

  describe "#update" do
    it "updates a monitor" do
      stub_datadog_request(:put, "monitor/123")
        .with(body: "{\"foo\":\"bar\"}").to_return(body: { bar: "foo" }.to_json)
      api.update("monitor", 123, foo: "bar").must_equal bar: "foo"
    end
  end

  describe "#delete" do
    it "deletes a monitor" do
      stub_datadog_request(:delete, "monitor/123", "&force=true").to_return(body: "{}")
      api.delete("monitor", 123).must_equal({})
    end

    it "deletes a dash" do
      stub_datadog_request(:delete, "dash/123", "&force=true")
        .with(body: nil).to_return(body: "")
      api.delete("dash", 123).must_equal({})
    end

    it "shows a descriptive failure when request fails, without including api keys" do
      stub_datadog_request(:delete, "monitor/123", "&force=true")
        .with(body: nil).to_return(body: "{}", status: 300)
      e = assert_raises(RuntimeError) { api.delete("monitor", 123) }
      e.message.must_equal <<~TEXT.strip
        Error 300 during DELETE /api/v1/monitor/123?force=true
        {}
      TEXT
    end

    it "ignores 404" do
      stub_datadog_request(:delete, "monitor/123", "&force=true").to_return(status: 404)
      api.delete("monitor", 123).must_equal({})
    end
  end

  describe "#fill_details!" do
    in_temp_dir # uses file-cache

    it "does nothing when not needed" do
      api.fill_details!("monitor", {})
    end

    it "fills dashboards" do
      stub_datadog_request(:get, "dashboard/123").to_return(body: { bar: "foo" }.to_json)
      list = [{ id: "123", modified_at: "123" }]
      api.fill_details!("dashboard", list)
      list.must_equal [{ id: "123", modified_at: "123", bar: "foo" }]
    end

    it "caches" do
      show = stub_datadog_request(:get, "dashboard/123").to_return(body: "{}")
      2.times do
        api.fill_details!("dashboard", [{ id: "123", modified_at: "123" }])
      end
      assert_requested show, times: 1
    end

    it "does not cache when modified" do
      show = stub_datadog_request(:get, "dashboard/123").to_return(body: "{}")
      2.times do |i|
        api.fill_details!("dashboard", [{ id: "123", modified_at: i }])
      end
      assert_requested show, times: 2
    end
  end

  describe "retries" do
    capture_all

    it "does not retry successful" do
      request = stub_datadog_request(:get, "monitor/1234").to_return(body: { bar: "foo" }.to_json)
      api.show("monitor", 1234).must_equal bar: "foo"
      assert_requested request
    end

    it "does not retry other failures" do
      request = stub_datadog_request(:get, "monitor/1234").to_return(body: { bar: "foo" }.to_json, status: 400)
      assert_raises(RuntimeError) { api.show("monitor", 1234) }
      assert_requested request
    end

    it "does not retry non-gets" do
      request = stub_datadog_request(:delete, "monitor/1234", "&force=true")
        .to_return(body: { bar: "foo" }.to_json, status: 400)
      assert_raises(RuntimeError) { api.delete("monitor", 1234) }
      assert_requested request
    end

    it "retries on random get 500 errors" do
      request = stub_datadog_request(:get, "monitor/1234").to_return(
        [
          { status: 500 },
          { status: 200, body: { foo: "bar" }.to_json }
        ]
      )
      api.show("monitor", 1234).must_equal foo: "bar"
      assert_requested request, times: 2
      stderr.string.must_equal "Retrying on server error 500 for /api/v1/monitor/1234\n"
    end

    it "retries on timeout" do
      request = stub_datadog_request(:get, "monitor/1234").to_timeout
      assert_raises Faraday::TimeoutError do
        api.show("monitor", 1234).must_equal foo: "bar"
      end
      assert_requested request, times: 3
      stderr.string.scan(/\d retries left/).must_equal ["1 retries left", "0 retries left"]
    end

    it "fails on repeated errors" do
      request = stub_datadog_request(:get, "monitor/1234").to_return(status: 500)
      e = assert_raises(RuntimeError) { api.show("monitor", 1234) }
      e.message.must_equal "Error 500 during GET /api/v1/monitor/1234\n"
      assert_requested request, times: 2
      stderr.string.must_equal "Retrying on server error 500 for /api/v1/monitor/1234\n"
    end
  end

  describe "force get cache" do
    in_temp_dir # uses file-cache
    with_env FORCE_GET_CACHE: "true"

    it "caches" do
      get = stub_datadog_request(:get, "monitor/1234").to_return(body: "{}")
      2.times { api.show("monitor", 1234).must_equal({}) }
      assert_requested get, times: 1
    end
  end
end
