# frozen_string_literal: true
require_relative "../test_helper"
require "kennel/importer"

SingleCov.covered!

describe Kennel::Importer do
  let(:importer) { Kennel::Importer.new(Kennel::Api.new("app", "api")) }

  describe "#import" do
    it "prints simple valid code" do
      response = { id: "abc", title: "hello" }
      stub_datadog_request(:get, "dashboard/abc").to_return(body: response.to_json)
      dash = importer.import("dashboard", "abc")
      dash.must_equal <<~RUBY
        Kennel::Models::Dashboard.new(
          self,
          title: -> { "hello" },
          id: -> { "abc" },
          kennel_id: -> { "hello" }
        )
      RUBY
      code = "TestProject.new(parts: -> {[#{dash}]})"
      project = eval(code, binding, __FILE__, __LINE__) # rubocop:disable Security/Eval
      project.parts.size.must_equal 1
    end

    it "refuses to import deprected screen" do
      assert_raises ArgumentError do
        importer.import("dash", "abc")
      end
    end

    it "refuses to import deprected dash" do
      assert_raises ArgumentError do
        importer.import("screen", "abc")
      end
    end

    it "prints complex elements" do
      response = { id: "abc", title: "a", foo: [1, 2], bar: { baz: ["123", "foo", { a: 1 }] } }
      stub_datadog_request(:get, "dashboard/abc").to_return(body: response.to_json)
      dash = importer.import("dashboard", "abc")
      dash.must_equal <<~RUBY
        Kennel::Models::Dashboard.new(
          self,
          title: -> { "a" },
          id: -> { "abc" },
          kennel_id: -> { "a" },
          bar: -> {
            {
              baz: [
                "123",
                "foo",
                {
                  a: 1
                }
              ]
            }
          },
          foo: -> {
            [
              1,
              2
            ]
          }
        )
      RUBY
    end

    it "prints null as nil" do
      response = { id: "abc", title: "a", bar: { baz: nil } }
      stub_datadog_request(:get, "dashboard/abc").to_return(body: response.to_json)
      dash = importer.import("dashboard", "abc")
      dash.must_equal <<~RUBY
        Kennel::Models::Dashboard.new(
          self,
          title: -> { "a" },
          id: -> { "abc" },
          kennel_id: -> { "a" },
          bar: -> {
            {
              baz: nil
            }
          }
        )
      RUBY
    end

    it "can import a monitor" do
      response = { id: 123, name: "hello", options: {} }
      stub_datadog_request(:get, "monitor/123").to_return(body: response.to_json)
      dash = importer.import("monitor", 123)
      dash.must_equal <<~RUBY
        Kennel::Models::Monitor.new(
          self,
          name: -> { "hello" },
          id: -> { 123 },
          kennel_id: -> { "hello" }
        )
      RUBY
    end

    it "removes monitor default" do
      response = { id: 123, name: "hello", options: { notify_audit: true } }
      stub_datadog_request(:get, "monitor/123").to_return(body: response.to_json)
      dash = importer.import("monitor", "123")
      dash.must_equal <<~RUBY
        Kennel::Models::Monitor.new(
          self,
          name: -> { "hello" },
          id: -> { 123 },
          kennel_id: -> { "hello" }
        )
      RUBY
    end

    it "keeps monitor values that are not the default" do
      response = { id: 123, name: "hello", options: { notify_audit: false } }
      stub_datadog_request(:get, "monitor/123").to_return(body: response.to_json)
      dash = importer.import("monitor", "123")
      dash.must_equal <<~RUBY
        Kennel::Models::Monitor.new(
          self,
          name: -> { "hello" },
          id: -> { 123 },
          kennel_id: -> { "hello" },
          notify_audit: -> { false }
        )
      RUBY
    end

    it "flattens monitor options" do
      response = {
        id: 123,
        name: "hello",
        options: {
          notify_audit: true,
          locked: false,
          timeout_h: 0,
          include_tags: true,
          no_data_timeframe: nil,
          new_host_delay: 300,
          require_full_window: false,
          notify_no_data: false,
          renotify_interval: 120,
          thresholds: {
            critical: 25.0
          }
        }
      }
      stub_datadog_request(:get, "monitor/123").to_return(body: response.to_json)
      dash = importer.import("monitor", 123)
      dash.must_equal <<~RUBY
        Kennel::Models::Monitor.new(
          self,
          name: -> { "hello" },
          id: -> { 123 },
          kennel_id: -> { "hello" },
          critical: -> { 25.0 },
          notify_no_data: -> { false }
        )
      RUBY
    end

    it "adds critical replacement" do
      response = { id: 123, name: "hello", query: "foo = 5", options: { critical: 5 } }
      stub_datadog_request(:get, "monitor/123").to_return(body: response.to_json)
      monitor = importer.import("monitor", 123)
      monitor.must_equal <<~RUBY
        Kennel::Models::Monitor.new(
          self,
          name: -> { "hello" },
          id: -> { 123 },
          kennel_id: -> { "hello" },
          query: -> { "foo = \#{critical}" },
          critical: -> { 5 }
        )
      RUBY
    end

    it "adds critical replacement for different type" do
      response = { id: 123, name: "hello", query: "foo = 5", options: { critical: 5.0 } }
      stub_datadog_request(:get, "monitor/123").to_return(body: response.to_json)
      monitor = importer.import("monitor", 123)
      monitor.must_equal <<~RUBY
        Kennel::Models::Monitor.new(
          self,
          name: -> { "hello" },
          id: -> { 123 },
          kennel_id: -> { "hello" },
          query: -> { "foo = \#{critical}" },
          critical: -> { 5.0 }
        )
      RUBY
    end

    it "prints simple arrays in a single line" do
      response = { id: 123, name: "hello", tags: ["a", "b", "c"], options: {} }
      stub_datadog_request(:get, "monitor/123").to_return(body: response.to_json)
      monitor = importer.import("monitor", 123)
      monitor.must_equal <<~RUBY
        Kennel::Models::Monitor.new(
          self,
          name: -> { "hello" },
          id: -> { 123 },
          kennel_id: -> { "hello" },
          tags: -> { ["a", "b", "c"] }
        )
      RUBY
    end

    it "prints message nicely" do
      response = { id: 123, name: "hello", message: "hello\n\n\nworld", options: {} }
      stub_datadog_request(:get, "monitor/123").to_return(body: response.to_json)
      monitor = importer.import("monitor", 123)
      monitor.must_equal <<~RUBY
        Kennel::Models::Monitor.new(
          self,
          name: -> { "hello" },
          id: -> { 123 },
          kennel_id: -> { "hello" },
          message: -> {
            <<~TEXT
              hello


              world
            TEXT
          }
        )
      RUBY
    end

    it "fails when requesting an unsupported resource" do
      stub_datadog_request(:get, "wut/123").to_return(body: "{}")
      e = assert_raises(ArgumentError) { importer.import("wut", 123) }
      e.message.must_equal "wut is not supported"
    end

    it "simplifies template_variables" do
      response = { id: "abc", title: "hello", template_variables: [{ default: "*", name: "pod", prefix: "pod" }, { nope: true }] }
      stub_datadog_request(:get, "dashboard/abc").to_return(body: response.to_json)
      dash = importer.import("dashboard", "abc")
      dash.must_equal <<~RUBY
        Kennel::Models::Dashboard.new(
          self,
          title: -> { "hello" },
          id: -> { "abc" },
          kennel_id: -> { "hello" },
          template_variables: -> {
            [
              "pod",
              {
                nope: true
              }
            ]
          }
        )
      RUBY
    end

    it "simplifies styles" do
      response = {
        id: "abc",
        title: "hello",
        widgets: [
          {
            definition: {
              requests: [{ foo: "bar", style: { line_width: "normal", palette: "dog_classic", line_type: "solid" } }]
            }
          }
        ]
      }
      stub_datadog_request(:get, "dashboard/abc").to_return(body: response.to_json)
      dash = importer.import("dashboard", "abc")
      dash.must_equal <<~RUBY
        Kennel::Models::Dashboard.new(
          self,
          title: -> { "hello" },
          id: -> { "abc" },
          kennel_id: -> { "hello" },
          widgets: -> {
            [
              {
                definition: {
                  requests: [
                    {
                      foo: "bar"
                    }
                  ]
                }
              }
            ]
          }
        )
      RUBY
    end

    it "can sorts important widgets fields to the top" do
      response = { id: "abc", title: "hello", widgets: [{ definition: { requests: [], title: "T", display_type: "x" } }] }
      stub_datadog_request(:get, "dashboard/abc").to_return(body: response.to_json)
      dash = importer.import("dashboard", "abc")
      dash.must_equal <<~RUBY
        Kennel::Models::Dashboard.new(
          self,
          title: -> { "hello" },
          id: -> { "abc" },
          kennel_id: -> { "hello" },
          widgets: -> {
            [
              {
                definition: {
                  title: "T",
                  display_type: "x",
                  requests: []
                }
              }
            ]
          }
        )
      RUBY
    end

    it "can sorts important nested widgets fields to the top" do
      response = { id: "abc", title: "hello", widgets: [{ definition: { widgets: [{ definition: { requests: [], title: "T", display_type: "x" } }] } }] }
      stub_datadog_request(:get, "dashboard/abc").to_return(body: response.to_json)
      dash = importer.import("dashboard", "abc")
      dash.must_equal <<~RUBY
        Kennel::Models::Dashboard.new(
          self,
          title: -> { "hello" },
          id: -> { "abc" },
          kennel_id: -> { "hello" },
          widgets: -> {
            [
              {
                definition: {
                  widgets: [
                    {
                      definition: {
                        title: "T",
                        display_type: "x",
                        requests: []
                      }
                    }
                  ]
                }
              }
            ]
          }
        )
      RUBY
    end
  end

  describe "#pretty_print" do
    it "prints simple" do
      importer.send(:pretty_print, foo: { bar: "baz" }).must_equal "  foo: -> {\n    {\n      bar: \"baz\"\n    }\n  }"
    end

    it "prints numbers" do
      importer.send(:pretty_print, foo: { "1" => 2 }).must_equal "  foo: -> {\n    {\n      \"1\": 2\n    }\n  }"
    end

    it "prints nils" do
      importer.send(:pretty_print, foo: { bar: nil }).must_equal "  foo: -> {\n    {\n      bar: nil\n    }\n  }"
    end

    it "prints non-symbolizable" do
      importer.send(:pretty_print, foo: { "a-b" => 1 }).must_equal "  foo: -> {\n    {\n      \"a-b\": 1\n    }\n  }"
    end

    it "prints empty arrays as single line" do
      importer.send(:pretty_print, foo: { bar: [] }).must_equal "  foo: -> {\n    {\n      bar: []\n    }\n  }"
    end
  end
end
