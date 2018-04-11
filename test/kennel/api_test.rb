# frozen_string_literal: true
require_relative "../test_helper"

SingleCov.covered!

describe Kennel::Api do
  let(:api) { Kennel::Api.new("app", "api") }

  describe "#show" do
    it "fetches monitor" do
      stub_request(:get, "https://app.datadoghq.com/api/v1/monitor/1234?api_key=api&application_key=app")
        .with(body: nil, headers: { "Content-Type" => "application/json" })
        .to_return(body: { bar: "foo" }.to_json)
      api.show("monitor", 1234).must_equal bar: "foo"
    end
  end

  describe "#list" do
    it "fetches monitors" do
      stub_request(:get, "https://app.datadoghq.com/api/v1/monitor?api_key=api&application_key=app&foo=bar")
        .with(body: nil, headers: { "Content-Type" => "application/json" })
        .to_return(body: [{ bar: "foo" }].to_json)
      api.list("monitor", foo: "bar").must_equal [{ bar: "foo" }]
    end

    it "shows a descriptive failure when request fails" do
      stub_request(:get, "https://app.datadoghq.com/api/v1/monitor?api_key=api&application_key=app&foo=bar")
        .to_return(status: 300, body: "foo")
      e = assert_raises(RuntimeError) { api.list("monitor", foo: "bar") }
      e.message.must_equal "Error 300 during GET /api/v1/monitor\nfoo"
    end
  end

  describe "#create" do
    it "creates a monitor" do
      stub_request(:post, "https://app.datadoghq.com/api/v1/monitor?api_key=api&application_key=app")
        .with(body: "{\"foo\":\"bar\"}").to_return(body: { bar: "foo" }.to_json)
      api.create("monitor", foo: "bar").must_equal bar: "foo"
    end

    it "shows a descriptive failure when request fails" do
      stub_request(:post, "https://app.datadoghq.com/api/v1/monitor?api_key=api&application_key=app")
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
  end

  describe "#update" do
    it "updates a monitor" do
      stub_request(:put, "https://app.datadoghq.com/api/v1/monitor/123?api_key=api&application_key=app")
        .with(body: "{\"foo\":\"bar\"}").to_return(body: { bar: "foo" }.to_json)
      api.update("monitor", 123, foo: "bar").must_equal bar: "foo"
    end
  end

  describe "#delete" do
    it "deletes a monitor" do
      stub_request(:delete, "https://app.datadoghq.com/api/v1/monitor/123?api_key=api&application_key=app")
        .with(body: nil).to_return(body: "{}")
      api.delete("monitor", 123).must_equal({})
    end

    it "deletes a dash" do
      stub_request(:delete, "https://app.datadoghq.com/api/v1/dash/123?api_key=api&application_key=app")
        .with(body: nil).to_return(body: "")
      api.delete("dash", 123).must_equal({})
    end

    it "shows a descriptive failure when request fails" do
      stub_request(:delete, "https://app.datadoghq.com/api/v1/monitor/123?api_key=api&application_key=app")
        .with(body: nil).to_return(body: "{}", status: 300)
      e = assert_raises(RuntimeError) { api.delete("monitor", 123) }
      e.message.must_equal <<~TEXT.strip
        Error 300 during DELETE /api/v1/monitor/123
        {}
      TEXT
    end
  end
end
