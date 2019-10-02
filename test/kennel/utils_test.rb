# frozen_string_literal: true
require_relative "../test_helper"

SingleCov.covered!

describe Kennel::Utils do
  describe ".snake_case" do
    it "converts namespaced classes" do
      Kennel::Utils.snake_case("Foo::Bar").must_equal "foo_bar"
    end

    it "converts classes with all-caps" do
      Kennel::Utils.snake_case("Foo2BarBAZ").must_equal "foo2_bar_baz"
    end
  end

  describe ".parameterize" do
    {
      "--" => "",
      "aøb" => "a-b",
      "" => "",
      "a1_Bc" => "a1_bc",
      "øabcøødefø" => "abc-def"
    }.each do |from, to|
      it "coverts #{from} to #{to}" do
        Kennel::Utils.parameterize(from).must_equal to
      end
    end
  end

  describe ".presence" do
    it "returns regular values" do
      Kennel::Utils.presence("a").must_equal "a"
    end

    it "does not return empty values" do
      Kennel::Utils.presence("").must_be_nil
    end
  end

  describe ".color" do
    it "colors" do
      Kennel::Utils.color(:red, "FOO").must_equal "\e[31mFOO\e[0m"
    end

    it "refuses unknown color" do
      assert_raises(KeyError) { Kennel::Utils.color(:sdffsd, "FOO") }
    end
  end

  describe ".strip_shell_control" do
    it "removes color" do
      text = "#{Kennel::Utils.color(:red, "abc")}--#{Kennel::Utils.color(:green, "efg")}"
      Kennel::Utils.strip_shell_control(text).must_equal "abc--efg"
    end

    it "removes control characters from progress" do
      text = Kennel::Utils.capture_stderr { Kennel::Progress.progress("Foo") { sleep 0.01 } }
      text.must_include "\b"
      text.gsub!(/\d+/, "0")
      Kennel::Utils.strip_shell_control(text).must_equal "Foo ... 0.0s\n"
    end
  end

  describe ".capture_stdout" do
    it "captures" do
      Kennel::Utils.capture_stdout { Kennel.out.puts "hello" }.must_equal "hello\n"
    end
  end

  describe ".capture_stderr" do
    it "captures" do
      Kennel::Utils.capture_stderr { Kennel.err.puts "hello" }.must_equal "hello\n"
    end
  end

  describe ".tee_output" do
    it "captures and prints" do
      Kennel::Utils.capture_stderr do
        Kennel::Utils.capture_stdout do
          Kennel::Utils.tee_output do
            Kennel.out.puts "hello"
            Kennel.err.puts "error"
            Kennel.out.puts "world"
          end.must_equal "hello\nerror\nworld\n"
        end.must_equal "hello\nworld\n"
      end.must_equal "error\n"
    end
  end

  describe ".capture_sh" do
    it "captures" do
      Kennel::Utils.capture_sh("echo 111").must_equal "111\n"
    end

    it "fails on failure" do
      e = assert_raises(RuntimeError) { Kennel::Utils.capture_sh("whooops") }
      e.message.must_include "whooops"
    end
  end

  describe ".ask" do
    capture_all

    it "is true on yes" do
      STDIN.expects(:gets).returns("y\n")
      assert Kennel::Utils.ask("foo")
      stderr.string.must_equal "\e[31mfoo -  press 'y' to continue: \e[0m"
    end

    it "is false on no" do
      STDIN.expects(:gets).returns("n\n")
      refute Kennel::Utils.ask("foo")
    end

    it "is false on enter" do
      STDIN.expects(:gets).returns("\n")
      refute Kennel::Utils.ask("foo")
    end

    it "does not print a backtrace when user decides to stop with Ctrl+C" do
      STDIN.expects(:gets).raises(Interrupt)
      Kennel::Utils.expects(:exit).with(1)
      refute Kennel::Utils.ask("foo")

      # newline is important or prompt will look weird
      stderr.string.must_equal "\e[31mfoo -  press 'y' to continue: \e[0m\n"
    end
  end

  describe ".path_to_url" do
    it "shows path" do
      Kennel::Utils.path_to_url("/111").must_equal "/111"
    end

    it "shows full url" do
      with_env DATADOG_SUBDOMAIN: "foobar" do
        Kennel::Utils.path_to_url("/111").must_equal "https://foobar.datadoghq.com/111"
      end
    end
  end

  describe ".parallel" do
    it "executes in parallel" do
      Benchmark.realtime do
        Kennel::Utils.parallel([1, 2, 3, 4, 5]) do |i|
          sleep 0.1
          i * 2
        end.must_equal [2, 4, 6, 8, 10]
      end.must_be :<, 0.2
    end

    it "raises exceptions" do
      assert_raises ArgumentError do
        Kennel::Utils.parallel([1, 2, 3, 4, 5]) do
          raise ArgumentError
        end
      end
    end

    it "finishes fast when exception happens" do
      called = []
      all = [1, 2, 3, 4, 5]
      assert_raises ArgumentError do
        Kennel::Utils.parallel(all, max: 2) do |i|
          called << i
          raise ArgumentError
        end
      end
      called.size.must_be :<, all.size
    end
  end

  describe ".natural_order" do
    def sort(list)
      list.sort_by { |x| Kennel::Utils.natural_order(x) }
    end

    it "sorts naturally" do
      sort(["a11", "a1", "a22", "b1", "a12", "a9"]).must_equal ["a1", "a9", "a11", "a12", "a22", "b1"]
    end

    it "sorts pure numbers" do
      sort(["11", "1", "22", "12", "9"]).must_equal ["1", "9", "11", "12", "22"]
    end

    it "sorts pure words" do
      sort(["bb", "ab", "aa", "a", "b"]).must_equal ["a", "aa", "ab", "b", "bb"]
    end
  end

  describe ".retry" do
    it "succeeds" do
      Kennel.err.expects(:puts).never
      Kennel::Utils.retry(RuntimeError, times: 2) { :a }.must_equal :a
    end

    it "retries and raises on persistent error" do
      Kennel.err.expects(:puts).times(2)
      call = []
      assert_raises(RuntimeError) do
        Kennel::Utils.retry(RuntimeError, times: 2) do
          call << :a
          raise
        end
      end
      call.must_equal [:a, :a, :a]
    end

    it "can succeed after retrying" do
      Kennel.err.expects(:puts).times(2)
      call = []
      Kennel::Utils.retry(RuntimeError, times: 2) do
        call << :a
        raise if call.size <= 2
        call
      end.must_equal [:a, :a, :a]
    end
  end

  describe ".all_keys" do
    it "finds keys for hash" do
      Kennel::Utils.all_keys(foo: 1).must_equal [:foo]
    end

    it "finds keys for hash in array" do
      Kennel::Utils.all_keys([{ foo: 1 }]).must_equal [:foo]
    end

    it "finds keys for multiple" do
      Kennel::Utils.all_keys([{ foo: 1 }, [[[{ bar: 2 }]]]]).must_equal [:foo, :bar]
    end
  end
end
