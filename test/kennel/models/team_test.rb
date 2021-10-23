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

  describe "#renotify_interval" do
    it "is set to datadogs default" do
      Teams::MyTeam.new.renotify_interval.must_equal 0
    end
  end

  describe "#tag_dashboards" do
    it "is false" do
      Teams::MyTeam.new.tag_dashboards.must_equal false
    end
  end
end
