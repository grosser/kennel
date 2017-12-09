# frozen_string_literal: true

# cache that reads everything from a single file
# to avoid doing multiple disk reads while interating all definitions
# it also replaces updated keys and has an overall expiry to not keep deleted things forever
module Kennel
  class FileCache
    def initialize(file)
      @file = file
      @data =
        begin
          Marshal.load(File.read(@file)) # rubocop:disable Security/MarshalLoad
        rescue StandardError
          {}
        end
      @now = Time.now.to_i
      @expires = @now + (30 * 24 * 60 * 60) # 1 month
      @data.reject! { |_, (_, _, ex)| ex < @now } # expire old data
    end

    def fetch(key, version)
      old_value, old_version = @data[key]
      return old_value if old_version == version

      new_value = yield
      @data[key] = [new_value, version, @expires]
      new_value
    end

    def persist
      FileUtils.mkdir_p(File.dirname(@file))
      File.write(@file, Marshal.dump(@data))
    end
  end
end
