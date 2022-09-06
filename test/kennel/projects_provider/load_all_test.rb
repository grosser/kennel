# frozen_string_literal: true

require_relative "../../test_helper"

SingleCov.covered! uncovered: 7 # TODO: reduce this

describe Kennel::ProjectsProvider::LoadAll do
  # For now, minimal "testing" just to pass test coverage.
  # The actual logic is currently tested in kennel_test.rb,
  # but should be moved here, with kennel_test.rb using stubs.

  it "runs" do
    Kennel::ProjectsProvider::LoadAll.new.projects
  end
end
