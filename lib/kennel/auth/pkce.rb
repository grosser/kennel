# frozen_string_literal: true

require "base64"
require "digest"
require "securerandom"

module Kennel
  module Auth
    module Pkce
      Challenge = Struct.new(:verifier, :challenge, :challenge_method, keyword_init: true)

      class << self
        def generate_challenge
          verifier = random_string(128)
          challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
          Challenge.new(verifier: verifier, challenge: challenge, challenge_method: "S256")
        end

        def generate_state
          random_string(32)
        end

        private

        def random_string(length)
          SecureRandom.urlsafe_base64(length)[0, length]
        end
      end
    end
  end
end
