# frozen_string_literal: true
require_relative "../test_helper"

SingleCov.covered!

describe Kennel::Compatibility do
  reset_instance

  it "provides private :api compatibility" do
    enable_api do
      api = Kennel::Api.allocate
      Kennel::Api.expects(:new).times(1).returns(api)

      engine = Kennel::Engine.new
      Kennel::Engine.expects(:new).times(1).returns(engine)

      Kennel.send(:api).must_equal(api)
    end
  end
end
