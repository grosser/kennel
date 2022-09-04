# frozen_string_literal: true
require_relative "../test_helper"

SingleCov.covered!

describe Kennel::Compatibility do
  reset_default_instance

  it "makes a default instance of kennel" do
    engine = Kennel::Engine.new
    Kennel::Engine.expects(:new).times(1).returns(engine)

    out = StringIO.new
    err = StringIO.new
    engine.out = out
    engine.err = err
    Kennel.out.must_equal(out)
    Kennel.err.must_equal(err)
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
