# frozen_string_literal: true
require_relative "../test_helper"
require "rake"
require "kennel/tasks"

SingleCov.covered! uncovered: 25 # TODO: reduce this

main = self

# task tests do not call dependencies
describe "tasks" do
  enable_api
  capture_std

  describe "kennel:generate" do
    let(:task) { "kennel:generate" }

    it "runs" do
      Kennel::Engine.any_instance.expects(:generate)
      execute_task
    end
  end

  describe "kennel:no_diff" do
    let(:task) { "kennel:no_diff" }

    it "does not complain when there is no diff" do
      `true` # fake success signal
      main.expects(:`).returns ""
      execute_task
    end

    it "complains on diff" do
      `true` # fake success signal
      main.expects(:`).returns "foo"
      assert_raises { execute_task }.message.must_include "Aborted Diff found"
    end

    it "complains on error" do
      `false` # fake success signal
      main.expects(:`).returns ""
      assert_raises { execute_task }.message.must_include "Error during diffing"
    end
  end

  describe "kennel:plan" do
    let(:task) { "kennel:plan" }

    it "plans" do
      Kennel::Engine.any_instance.expects(:preload)
      Kennel::Engine.any_instance.expects(:generate)
      Kennel::Engine.any_instance.expects(:plan)
      execute_task
    end

    it "does not generate when asked" do
      Kennel::Engine.any_instance.expects(:preload)
      Kennel::Engine.any_instance.expects(:generate).never
      Kennel::Engine.any_instance.expects(:plan)
      execute_task KENNEL_NO_GENERATE: "true"
    end
  end

  describe "kennel:update_datadog" do
    let(:task) { "kennel:update_datadog" }

    it "updates" do
      Kennel::Engine.any_instance.expects(:preload)
      Kennel::Engine.any_instance.expects(:generate)
      Kennel::Engine.any_instance.expects(:update)
      execute_task
    end

    it "does not generate when asked" do
      Kennel::Engine.any_instance.expects(:preload)
      Kennel::Engine.any_instance.expects(:generate).never
      Kennel::Engine.any_instance.expects(:update)
      execute_task KENNEL_NO_GENERATE: "true"
    end
  end
end
