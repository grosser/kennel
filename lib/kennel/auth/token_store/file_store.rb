# frozen_string_literal: true

module Kennel
  module Auth
    module TokenStore
      class FileStore
        DEFAULT_FILE = "~/.kennel/oauth_auth.json"

        attr_reader :file

        def initialize(site:, subdomain: "app", file: ENV.fetch("KENNEL_OAUTH_CACHE_FILE", DEFAULT_FILE))
          @site = site
          @subdomain = subdomain
          @file = File.expand_path(file)
        end

        def load_state
          all = load_all
          all.fetch(storage_key) { legacy_state(all) }
        end

        def save_state(state)
          all = load_all
          all[storage_key] = state
          persist(all)
        end

        private

        def load_all
          JSON.parse(File.read(@file))
        rescue Errno::ENOENT
          {}
        end

        def persist(all)
          dir = File.dirname(@file)
          FileUtils.mkdir_p(dir) unless File.directory?(dir)
          File.write(@file, JSON.pretty_generate(all))
          File.chmod(0o600, @file)
        end

        def storage_key
          "#{@site}|#{@subdomain}"
        end

        def legacy_state(all)
          return {} unless @subdomain == "app"

          all.fetch(@site, {})
        end
      end
    end
  end
end
