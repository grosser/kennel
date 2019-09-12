# frozen_string_literal: true
require_relative "../../test_helper"

SingleCov.covered!

describe Kennel::Models::Team do
  describe "#tags" do
    it "is a nice searchable name" do
      TestTeam.new.tags.must_equal ["team:test_team"]
    end

    it "does not prefix teams with folder name if it is teams too" do
      Teams::MyTeam.new.tags.must_equal ["team:my_team"]
    end
  end

  describe "#slack" do
    it "is invalid when using leading #" do
      assert_raises(Kennel::Models::Base::ValidationError) { Teams::MyTeam.new(slack: -> { "#foo" }) }
    end
  end

  describe "#renotify_interval" do
    it "is set to datadogs default" do
      Teams::MyTeam.new.renotify_interval.must_equal 0
    end
  end
end
