# frozen_string_literal: true
require_relative "../../test_helper"

SingleCov.covered!

describe Kennel::Auth::Pkce do
  it "generates a valid challenge" do
    challenge = Kennel::Auth::Pkce.generate_challenge
    challenge.verifier.length.must_equal 128
    challenge.challenge.wont_be_nil
    challenge.challenge_method.must_equal "S256"
  end

  it "generates random states" do
    a = Kennel::Auth::Pkce.generate_state
    b = Kennel::Auth::Pkce.generate_state
    a.length.must_equal 32
    a.wont_equal b
  end
end
