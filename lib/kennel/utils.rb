# frozen_string_literal: true
module Kennel
  module Utils
    COLORS = { red: 31, green: 32, yellow: 33, cyan: 36, magenta: 35, default: 0 }.freeze

    class TeeIO < IO
      def initialize(ios)
        @ios = ios
      end

      def write(string)
        @ios.each { |io| io.write string }
      end
    end

    class << self
      def snake_case(string)
        string.gsub(/::/, "_") # Foo::Bar -> foo_bar
          .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2') # FOOBar -> foo_bar
          .gsub(/([a-z\d])([A-Z])/, '\1_\2') # fooBar -> foo_bar
          .downcase
      end

      def presence(value)
        value.nil? || value.empty? ? nil : value
      end

      def ask(question)
        Kennel.err.printf color(:red, "#{question} -  press 'y' to continue: ")
        begin
          STDIN.gets.chomp == "y"
        rescue Interrupt # do not show a backtrace if user decides to Ctrl+C here
          Kennel.err.print "\n"
          exit 1
        end
      end

      def color(color, text)
        "\e[#{COLORS.fetch(color)}m#{text}\e[0m"
      end

      def strip_shell_control(text)
        text.gsub(/\e\[\d+m(.*?)\e\[0m/, "\\1").gsub(/.#{Regexp.escape("\b")}/, "")
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

      def path_to_url(path)
        if subdomain = ENV["DATADOG_SUBDOMAIN"]
          "https://#{subdomain}.datadoghq.com#{path}"
        else
          path
        end
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
                rescue StandardError => e
                  e
                end
            end
          end
        end
        workers.each(&:join)
        done.each { |d| raise d if d.is_a?(StandardError) }
      end

      def natural_order(name)
        name.split(/(\d+)/).each_with_index.map { |x, i| i.odd? ? x.to_i : x }
      end
    end
  end
end
