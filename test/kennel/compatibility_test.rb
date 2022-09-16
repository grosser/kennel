# frozen_string_literal: true
require_relative "../test_helper"

SingleCov.covered!

describe Kennel::Compatibility do
  reset_instance

  it "makes a default instance of kennel" do
    engine = Kennel::Engine.new
    Kennel::Engine.expects(:new).times(1).returns(engine)
    Kennel.instance.config.strict_imports.must_equal(true)
  end

  %I[generate plan update].each do |sym|
    it "can #{sym}" do
      engine = Kennel::Engine.new
      Kennel::Engine.expects(:new).times(1).returns(engine)

      return_value = {}
      engine.expects(sym).times(1).returns(return_value)
      Kennel.public_send(sym).must_equal(return_value)
    end
  end

  it "provides private :api compatibility" do
    with_env({ "DATADOG_APP_KEY" => "x", "DATADOG_API_KEY" => "y" }) do
      api = Kennel::Api.allocate
      Kennel::Api.expects(:new).times(1).returns(api)

      engine = Kennel::Engine.new
      Kennel::Engine.expects(:new).times(1).returns(engine)

      Kennel.send(:api).must_equal(api)
    end
  end
end
