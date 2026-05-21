# frozen_string_literal: true

module Kennel
  module Auth
    module TokenStore
      class KeychainStore
        SERVICE = "kennel/datadog/oauth"

        StoreError = Class.new(StandardError)
        UnavailableError = Class.new(StoreError)

        def initialize(site:, subdomain: "app", library_loader: -> { require "keychain" })
          @site = site
          @subdomain = subdomain
          library_loader.call
          ::Keychain.generic_passwords
        rescue LoadError => e
          raise UnavailableError, e.message
        rescue StandardError => e
          raise UnavailableError, e.message
        end

        def load_state
          item = scope.first
          item ||= legacy_scope.first if @subdomain == "app"
          return {} unless item

          JSON.parse(item.password.to_s)
        rescue StandardError => e
          raise StoreError, e.message
        end

        def save_state(state)
          payload = JSON.generate(state)
          item = scope.first
          if item
            item.password = payload
            item.save!
          else
            ::Keychain.generic_passwords.create(service: SERVICE, account: storage_key, password: payload)
          end
        rescue StandardError => e
          raise StoreError, e.message
        end

        private

        def scope
          ::Keychain.generic_passwords.where(service: SERVICE, account: storage_key)
        end

        def legacy_scope
          ::Keychain.generic_passwords.where(service: SERVICE, account: @site)
        end

        def storage_key
          "#{@site}|#{@subdomain}"
        end
      end
    end
  end
end
