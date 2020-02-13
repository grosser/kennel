# frozen_string_literal: true

# cache that reads everything from a single file
# to avoid doing multiple disk reads while iterating all definitions
# it also replaces updated keys and has an overall expiry to not keep deleted things forever
module Kennel
  class FileCache
    def initialize(file, cache_version)
      @file = file
      @cache_version = cache_version
      @now = Time.now.to_i
      @expires = @now + (30 * 24 * 60 * 60) # 1 month
    end

    def open
      load_data
      expire_old_data
      yield self
    ensure
      persist
    end

    def fetch(key, key_version)
      old_value, old_version = @data[key]
      return old_value if old_version == [key_version, @cache_version]

      new_value = yield
      @data[key] = [new_value, [key_version, @cache_version], @expires]
      new_value
    end

    private

    def load_data
      @data =
        begin
          Marshal.load(File.read(@file)) # rubocop:disable Security/MarshalLoad
        rescue StandardError
          {}
        end
    end

    def persist
      dir = File.dirname(@file)
      FileUtils.mkdir_p(dir) unless File.directory?(dir)
      File.write(@file, Marshal.dump(@data))
    end

    def expire_old_data
      @data.reject! { |_, (_, _, ex)| ex < @now }
    end
  end
end
