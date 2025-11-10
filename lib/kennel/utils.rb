# frozen_string_literal: true
module Kennel
  module Utils
    class << self
      def presence(value)
        value.nil? || value.empty? ? nil : value
      end

      def capture_sh(command)
        result = `#{command} 2>&1`
        raise "Command failed:\n#{command}\n#{result}" unless $CHILD_STATUS.success?
        result
      end

      def path_to_url(path)
        subdomain = (ENV["DATADOG_SUBDOMAIN"] || "app")
        "https://#{subdomain}.datadoghq.com#{path}"
      end

      def parallel(items, max: 10)
        threads = [items.size, max].min
        work = items.each_with_index.to_a
        done = Array.new(items.size)
        workers = Array.new(threads).map do
          Thread.new do
            loop do
              item, i = work.shift
              break unless i
              done[i] =
                begin
                  yield item
                rescue Exception => e # rubocop:disable Lint/RescueException
                  work.clear # prevent new work
                  (workers - [Thread.current]).each(&:kill) # stop ongoing work
                  e
                end
            end
          end
        end
        workers.each(&:join)
        done.each { |d| raise d if d.is_a?(Exception) }
      end

      def natural_order(name)
        name.split(/(\d+)/).each_with_index.map { |x, i| i.odd? ? x.to_i : x }
      end

      def retry(*errors, times:)
        yield
      rescue *errors => e
        times -= 1
        raise if times < 0
        Kennel.err.puts "Error #{e}, #{times} retries left"
        retry
      end

      # https://stackoverflow.com/questions/20235206/ruby-get-all-keys-in-a-hash-including-sub-keys/53876255#53876255
      def all_keys(items)
        case items
        when Hash then items.keys + items.values.flat_map { |v| all_keys(v) }
        when Array then items.flat_map { |i| all_keys(i) }
        else []
        end
      end
    end
  end
end
