# frozen_string_literal: true
require_relative "../../test_helper"
require "rake"
require "kennel/tasks"

SingleCov.covered!

describe "kennel:import" do
  enable_api
  capture_std

  it "can import from RESOURCE/ID" do
    Kennel::Importer.any_instance.expects(:import).with("monitor", 123).returns("X")
    execute_task(RESOURCE: "monitor", ID: "123")
    stdout.string.must_equal "X\n"
  end

  it "can import from URL" do
    Kennel::Importer.any_instance.expects(:import).with("dashboard", "abc").returns("X")
    execute_task(URL: "https://app.datadoghq.com/dashboard/abc")
    stdout.string.must_equal "X\n"
  end

  it "fails when neither is given" do
    e = assert_raises(RuntimeError) { execute_task(ID: "123") }
    e.message.must_equal "Aborted Call with URL= or call with RESOURCE=dashboard or monitor or slo or synthetics/tests and ID="
  end
end
