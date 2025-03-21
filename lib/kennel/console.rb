# frozen_string_literal: true
module Kennel
  module Console
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
      def tty?
        !ENV["CI"] && (Kennel.in.tty? || Kennel.err.tty?)
      end

      def ask?(question)
        Kennel.err.printf color(:red, "#{question} -  press 'y' to continue: ", force: true)
        begin
          Kennel.in.gets.chomp == "y"
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
    end
  end
end
