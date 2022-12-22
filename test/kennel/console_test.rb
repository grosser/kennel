# frozen_string_literal: true
require_relative "../test_helper"

SingleCov.covered!

describe Kennel::Console do
  describe ".color" do
    it "colors (with a tty)" do
      Kennel.out.stubs(:tty?).returns(true)
      Kennel::Console.color(:red, "FOO").must_equal "\e[31mFOO\e[0m"
    end

    it "does not color (without a tty)" do
      Kennel.out.stubs(:tty?).returns(false)
      Kennel::Console.color(:red, "FOO").must_equal "FOO"
    end

    it "colors (without a tty, but with force)" do
      Kennel.out.stubs(:tty?).returns(false)
      Kennel::Console.color(:red, "FOO", force: true).must_equal "\e[31mFOO\e[0m"
    end

    it "refuses unknown color" do
      Kennel.out.stubs(:tty?).returns(true)
      assert_raises(KeyError) { Kennel::Console.color(:sdffsd, "FOO") }
    end
  end

  describe ".capture_stdout" do
    it "captures" do
      Kennel::Console.capture_stdout { Kennel.out.puts "hello" }.must_equal "hello\n"
    end
  end

  describe ".capture_stderr" do
    it "captures" do
      Kennel::Console.capture_stderr { Kennel.err.puts "hello" }.must_equal "hello\n"
    end
  end

  describe ".tee_output" do
    it "captures and prints" do
      Kennel::Console.capture_stderr do
        Kennel::Console.capture_stdout do
          Kennel::Console.tee_output do
            Kennel.out.puts "hello"
            Kennel.err.puts "error"
            Kennel.out.puts "world"
          end.must_equal "hello\nerror\nworld\n"
        end.must_equal "hello\nworld\n"
      end.must_equal "error\n"
    end
  end

  describe ".ask?" do
    capture_all

    it "is true on yes" do
      STDIN.expects(:gets).returns("y\n")
      assert Kennel::Console.ask?("foo")
      stderr.string.must_equal "\e[31mfoo -  press 'y' to continue: \e[0m"
    end

    it "is false on no" do
      STDIN.expects(:gets).returns("n\n")
      refute Kennel::Console.ask?("foo")
    end

    it "is false on enter" do
      STDIN.expects(:gets).returns("\n")
      refute Kennel::Console.ask?("foo")
    end

    it "does not print a backtrace when user decides to stop with Ctrl+C" do
      STDIN.expects(:gets).raises(Interrupt)
      Kennel::Console.expects(:exit).with(1)
      refute Kennel::Console.ask?("foo")

      # newline is important or prompt will look weird
      stderr.string.must_equal "\e[31mfoo -  press 'y' to continue: \e[0m\n"
    end
  end
end
