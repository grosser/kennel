# frozen_string_literal: true

module Kennel
  module Auth
    module TokenStore
      class << self
        def build(site:, subdomain:, err: Kennel.err)
          file_store = FileStore.new(site: site, subdomain: subdomain)

          case ENV["DD_TOKEN_STORAGE"]
          when "file"
            file_store
          when "keychain"
            KeychainStore.new(site: site, subdomain: subdomain)
          else
            begin
              Fallback.new(primary: KeychainStore.new(site: site, subdomain: subdomain), fallback: file_store, err: err)
            rescue KeychainStore::UnavailableError => e
              err.puts fallback_warning(e.message, file_store)
              file_store
            end
          end
        end

        def fallback_warning(reason, file_store)
          "Warning: Keychain unavailable (#{reason}). " \
            "To enable system keychain storage in downstream repos, add gem \"ruby-keychain\" to the Gemfile and run bundle install. " \
            "Falling back to file token storage at #{file_store.file} with chmod 0600. " \
            "File storage still keeps OAuth access and refresh tokens on disk, so protect the workspace and never commit that file."
        end
      end

      class Fallback
        def initialize(primary:, fallback:, err:)
          @active = primary
          @fallback = fallback
          @err = err
          @warned = false
        end

        def load_state
          with_fallback { @active.load_state }
        end

        def save_state(state)
          with_fallback { @active.save_state(state) }
        end

        private

        def with_fallback
          yield
        rescue KeychainStore::UnavailableError, KeychainStore::StoreError => e
          unless @warned
            @err.puts TokenStore.fallback_warning(e.message, @fallback)
            @warned = true
          end
          @active = @fallback
          yield
        end
      end
    end
  end
end
