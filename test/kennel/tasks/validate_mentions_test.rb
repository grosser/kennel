# frozen_string_literal: true
require_relative "../../test_helper"
require "rake"
require "kennel/tasks"

SingleCov.covered!

describe "kennel:validate_mentions" do
  def execute_task(...)
    Tempfile.create do |f|
      f.write(content.to_json)
      f.flush
      Dir.stubs(:[]).returns([f.path])
      super
    end
  end

  enable_api
  capture_std

  let(:content) { { message: "" } }

  before do
    Kennel::Api.any_instance.expects(:request)
      .with(:get, "/api/v2/notifications/handles?group_limit=99999")
      .returns({ data: [{ attributes: { handles: [{ value: "bar" }, { value: "baz" }] } }] })
  end

  it "passes" do
    execute_task
  end

  it "ignores @here" do
    content[:message] = "@here"
    execute_task
  end

  it "ignores known bad" do
    content[:message] = "@oo@ps"
    execute_task KNOWN: "@oo@ps"
  end

  it "ignores non-monitors" do
    content.delete :message
    execute_task
  end

  it "fails when unknown mentions are used" do
    content[:message] = "@oo@ps"
    assert_raises { execute_task }.message.must_equal "Aborted SystemExit"
    stderr.string.must_include "Invalid mentions"
  end

  it "fails when known knowns are ignored" do
    assert_raises { execute_task KNOWN: "bar" }.message.must_equal "Aborted KNOWN=bar values are already known and should be removed"
  end
end
