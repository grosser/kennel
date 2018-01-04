# frozen_string_literal: true
require_relative "../test_helper"

SingleCov.covered!

describe Kennel::OptionalValidations do
  class TestVariables < Kennel::Models::Base
    include Kennel::OptionalValidations
  end

  it "adds settings" do
    TestVariables.new(validate: -> { false }).validate.must_equal false
  end
end
