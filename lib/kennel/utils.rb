# frozen_string_literal: true
module Kennel
  module Utils
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
        text.gsub(/\e\[\d+m(.*?)\e\[0m/, "\\1").tr("\b", "")
      end

      def capture_stdout
        $stdout = StringIO.new
        yield
        $stdout.string
      ensure
        $stdout = STDOUT
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
    end
  end
end
