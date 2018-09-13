# frozen_string_literal: true
require_relative "../../test_helper"

SingleCov.covered!

describe Kennel::Models::Project do
  describe ".file_location" do
    it "finds the file" do
      TestProject.file_location.must_equal "test/test_helper.rb"
    end
  end

  describe "#tags" do
    it "adds itself by default" do
      TestProject.new.tags.must_equal ["service:test_project", "team:test_team"]
    end
  end

  describe "#slack" do
    it "uses teams slack" do
      TestProject.new.slack.must_equal "foo"
    end
  end
end
