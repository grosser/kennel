# frozen_string_literal: true
require_relative "../../test_helper"
require "rake"
require "kennel/tasks"

SingleCov.covered!

describe "dump" do
  enable_api
  capture_std
  in_temp_dir

  let(:api) { Kennel::Api.any_instance }
  let(:dump_output) do
    <<~JSON
      [
      {
        "id": 1,
        "modified_at": 2,
        "name": "N",
        "foo": "bar",
        "api_resource": "dashboard"
      },
      {
        "id": 1,
        "modified_at": 2,
        "name": "N",
        "api_resource": "monitor"
      },
      {
        "id": 1,
        "modified_at": 2,
        "name": "N",
        "api_resource": "slo"
      },
      {
        "id": 1,
        "modified_at": 2,
        "name": "N",
        "api_resource": "synthetics/tests"
      }
      ]
    JSON
  end

  before do
    list = [{ id: 1, modified_at: 2, name: "N" }]
    api.stubs(:list).returns list, deep_dup(list), deep_dup(list)
  end

  describe "kennel:dump" do
    let(:task) { "kennel:dump" }

    it "dumps" do
      execute_task(TYPE: "monitor")
      stdout.string.must_equal <<~JSON
        [
        {
          "id": 1,
          "modified_at": 2,
          "name": "N",
          "api_resource": "monitor"
        }
        ]
      JSON
    end

    it "dumps all" do
      api.expects(:show).returns foo: "bar"
      execute_task
      stdout.string.must_equal dump_output
    end
  end

  describe "kennel:dump_grep" do
    in_temp_dir

    let(:task) { "kennel:dump_grep" }

    before { File.write("dump", dump_output) }

    it "can grep json" do
      with_env(DUMP: "dump", PATTERN: "foo") { execute_task }
      stdout.string.must_equal <<~JSON
        {
          "id": 1,
          "modified_at": 2,
          "name": "N",
          "foo": "bar",
          "api_resource": "dashboard"
        }
      JSON
    end

    it "can grep urls" do
      with_env(DUMP: "dump", PATTERN: "foo", URLS: "true") { execute_task }
      stdout.string.must_equal "https://app.datadoghq.com/dashboard/1 # N\n"
    end

    it "fails when nothing matches" do
      e = assert_raises(RuntimeError) { with_env(DUMP: "dump", PATTERN: "nope") { execute_task } }
      e.message.must_equal "Aborted exit"
    end
  end
end
