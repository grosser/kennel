# frozen_string_literal: true
module Kennel
  module Utils
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
        value.empty? ? nil : value
      end

      def ask(question)
        printf color(:red, "#{question} -  press 'y' to continue: ")
        begin
          STDIN.gets.chomp == "y"
        rescue Interrupt # do not show a backtrace if user decides to Ctrl+C here
          printf "\n"
          exit 1
        end
      end

      def color(color, text)
        code = { red: 31, green: 32, yellow: 33 }.fetch(color)
        "\e[#{code}m#{text}\e[0m"
      end

      def strip_shell_control(text)
        text.gsub(/\e\[\d+m(.*?)\e\[0m/, "\\1").gsub(/.#{Regexp.escape("\b")}/, "")
      end

      def capture_stdout
        old = $stdout
        $stdout = StringIO.new
        yield
        $stdout.string
      ensure
        $stdout = old
      end

      def tee_stdout
        old = $stdout
        string = StringIO.new
        $stdout = TeeIO.new([$stdout, string])
        yield
        string.string
      ensure
        $stdout = old
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

      def parallel(items)
        items.map do |item|
          Thread.new do
            yield item
          rescue StandardError => e
            e
          end
        end.map(&:value).each { |i| raise i if i.is_a?(StandardError) }
      end
    end
  end
end
