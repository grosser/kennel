# frozen_string_literal: true
require_relative "../test_helper"
require "kennel/importer"

SingleCov.covered!

describe Kennel::Importer do
  let(:importer) { Kennel::Importer.new(Kennel::Api.new("app", "api")) }

  describe "#import" do
    it "prints simple valid code" do
      response = { dash: { id: 123, title: "hello", created_by: "me", deleted: "yes" } }
      stub_datadog_request(:get, "dash/123").to_return(body: response.to_json)
      dash = importer.import("dash", 123)
      dash.must_equal <<~RUBY
        Kennel::Models::Dash.new(
          self,
          title: -> { "hello" },
          id: -> { 123 }
        )
      RUBY
      code = "TestProject.new(parts: -> {[#{dash}]})"
      project = eval(code, binding, __FILE__, __LINE__) # rubocop:disable Security/Eval
      project.parts.size.must_equal 1
    end

    it "prints complex elements" do
      response = { dash: { foo: [1, 2], bar: { baz: ["123", "foo", { a: 1 }] } } }
      stub_datadog_request(:get, "dash/123").to_return(body: response.to_json)
      dash = importer.import("dash", 123)
      dash.must_equal <<~RUBY
        Kennel::Models::Dash.new(
          self,
          id: -> { 123 },
          foo: -> {
            [
              1,
              2
            ]
          },
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
          }
        )
      RUBY
    end

    it "removes boring default values" do
      response = { dash: { id: 123, graphs: [{ definition: { foo: "bar", autoscale: true } }] } }
      stub_datadog_request(:get, "dash/123").to_return(body: response.to_json)
      dash = importer.import("dash", 123)
      dash.must_equal <<~RUBY
        Kennel::Models::Dash.new(
          self,
          id: -> { 123 },
          graphs: -> {
            [
              {
                definition: {
                  foo: "bar"
                }
              }
            ]
          }
        )
      RUBY
    end

    it "fails when requesting an unsupported resource" do
      stub_datadog_request(:get, "wut/123").to_return(body: "{}")
      e = assert_raises(ArgumentError) { importer.import("wut", 123) }
      e.message.must_equal "wut is not supported"
    end
  end
end
