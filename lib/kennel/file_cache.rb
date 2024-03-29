# frozen_string_literal: true

require "tempfile"

# cache that reads everything from a single file
# - avoids doing multiple disk reads while iterating all definitions
# - has a global expiry to not keep deleted resources forever
module Kennel
  class FileCache
    def initialize(file, cache_version)
      @file = file
      @cache_version = cache_version
      @now = Time.now.to_i
      @expires = @now + (30 * 24 * 60 * 60) # 1 month
    end

    def open
      @data = load_data || {}
      begin
        expire_old_data
        yield self
      ensure
        persist
      end
    end

    def fetch(key, key_version)
      old_value, old_version = @data[key]
      expected_version = [key_version, @cache_version]
      return old_value if old_version == expected_version

      new_value = yield
      @data[key] = [new_value, expected_version, @expires]
      new_value
    end

    private

    def load_data
      Marshal.load(File.read(@file)) # rubocop:disable Security/MarshalLoad
    rescue Errno::ENOENT, TypeError, ArgumentError
      nil
    end

    def persist
      dir = File.dirname(@file)
      FileUtils.mkdir_p(dir) unless File.directory?(dir)

      Tempfile.create "kennel-file-cache", dir do |tmp|
        Marshal.dump @data, tmp
        tmp.flush
        File.rename tmp.path, @file
      end
    end

    # keep the cache small to make loading it fast (5MB ~= 100ms)
    # - delete expired keys
    # - delete what would be deleted anyway when updating
    def expire_old_data
      @data.reject! do |(_api_resource, _id), (_value, (_key_version, cache_version), expires)|
        expires < @now || cache_version != @cache_version
      end
    end
  end
end
