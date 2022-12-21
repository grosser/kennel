# frozen_string_literal: true
module Kennel
  module Utils
    COLORS = { red: 31, green: 32, yellow: 33, cyan: 36, magenta: 35, default: 0 }.freeze

    class TeeIO < IO
      def initialize(ios)
        super(0) # called with fake file descriptor 0, so we can call super and get a proper class
        @ios = ios
      end

      def write(string)
        @ios.each { |io| io.write string }
      end
    end

    class << self
      def presence(value)
        value.nil? || value.empty? ? nil : value
      end

      def ask(question)
        Kennel.err.printf color(:red, "#{question} -  press 'y' to continue: ", force: true)
        begin
          STDIN.gets.chomp == "y"
        rescue Interrupt # do not show a backtrace if user decides to Ctrl+C here
          Kennel.err.print "\n"
          exit 1
        end
      end

      def color(color, text, force: false)
        return text unless force || Kennel.out.tty?

        "\e[#{COLORS.fetch(color)}m#{text}\e[0m"
      end

      def capture_stdout
        old = Kennel.out
        Kennel.out = StringIO.new
        yield
        Kennel.out.string
      ensure
        Kennel.out = old
      end

      def capture_stderr
        old = Kennel.err
        Kennel.err = StringIO.new
        yield
        Kennel.err.string
      ensure
        Kennel.err = old
      end

      def tee_output
        old_stdout = Kennel.out
        old_stderr = Kennel.err
        capture = StringIO.new
        Kennel.out = TeeIO.new([capture, Kennel.out])
        Kennel.err = TeeIO.new([capture, Kennel.err])
        yield
        capture.string
      ensure
        Kennel.out = old_stdout
        Kennel.err = old_stderr
      end

      def capture_sh(command)
        result = `#{command} 2>&1`
        raise "Command failed:\n#{command}\n#{result}" unless $CHILD_STATUS.success?
        result
      end

      def path_to_url(path, subdomain: nil)
        subdomain ||= (ENV["DATADOG_SUBDOMAIN"] || "app")
        "https://#{subdomain}.datadoghq.com#{path}"
      end

      def parallel(items, max: 10)
        threads = [items.size, max].min
        work = items.each_with_index.to_a
        done = Array.new(items.size)
        workers = Array.new(threads).map do
          Thread.new do
            loop do
              item, i = work.pop
              break unless i
              done[i] =
                begin
                  yield item
                rescue Exception => e # rubocop:disable Lint/RescueException
                  work.clear
                  e
                end
            end
          end
        end
        workers.each(&:join)
        done.each { |d| raise d if d.is_a?(Exception) }
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

      def inline_resource_metadata(resource, klass)
        resource[:klass] = klass
        resource[:tracking_id] = klass.parse_tracking_id(resource)
      end
    end
  end
end
