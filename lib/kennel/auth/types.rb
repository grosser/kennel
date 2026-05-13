# frozen_string_literal: true

require "time"

module Kennel
  module Auth
    class TokenSet
      EXPIRATION_BUFFER = 300

      ATTRIBUTES = %i[
        access_token
        refresh_token
        token_type
        expires_in
        issued_at
        scope
        client_id
      ].freeze

      attr_accessor(*ATTRIBUTES)

      def initialize(access_token:, refresh_token:, expires_in:, issued_at:, token_type: "Bearer", scope: "", client_id: "")
        @access_token = access_token
        @refresh_token = refresh_token
        @token_type = token_type
        @expires_in = expires_in.to_i
        @issued_at = issued_at.to_i
        @scope = scope
        @client_id = client_id
      end

      def self.from_h(hash)
        return unless hash

        new(**hash.transform_keys(&:to_sym))
      end

      def expired?
        Time.now.to_i >= expires_at - EXPIRATION_BUFFER
      end

      def expires_at
        issued_at + expires_in
      end

      def to_h
        ATTRIBUTES.to_h { |attribute| [attribute.to_s, public_send(attribute)] }
      end
    end

    class ClientCredentials
      ATTRIBUTES = %i[
        client_id
        client_name
        redirect_uris
        registered_at
        subdomain
        site
      ].freeze

      attr_accessor(*ATTRIBUTES)

      def initialize(client_id:, client_name:, redirect_uris:, registered_at:, site:, subdomain: "app")
        @client_id = client_id
        @client_name = client_name
        @redirect_uris = redirect_uris
        @registered_at = registered_at.to_i
        @subdomain = subdomain
        @site = site
      end

      def self.from_h(hash)
        return unless hash

        new(**{ "subdomain" => "app" }.merge(hash).transform_keys(&:to_sym))
      end

      def to_h
        ATTRIBUTES.to_h { |attribute| [attribute.to_s, public_send(attribute)] }
      end
    end
  end
end
