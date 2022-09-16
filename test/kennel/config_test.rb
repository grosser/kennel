# frozen_string_literal: true
require_relative "../test_helper"

SingleCov.covered! uncovered: 7

describe Kennel::Config do
  it "builds" do
    Kennel::Config.new
  end

  # TODO: draw the rest of the owl
end
