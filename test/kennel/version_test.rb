# frozen_string_literal: true
require_relative "../test_helper"

SingleCov.not_covered! # loaded as part of the Gemfile, so we cannot cover it

describe Kennel::VERSION do
  it "has a VERSION" do
    Kennel::VERSION.must_match(/^[\.\da-z]+$/)
  end
end
