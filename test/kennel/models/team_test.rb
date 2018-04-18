# frozen_string_literal: true
require_relative "../../test_helper"

SingleCov.covered!

describe Kennel::Models::Team do
  describe "#tags" do
    it "is a nice searchable name" do
      TestTeam.new.tags.must_equal ["team:test_team"]
    end
  end
end
