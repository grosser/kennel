# frozen_string_literal: true
require_relative "../test_helper"

SingleCov.covered!

describe Kennel::Utils do
  describe ".presence" do
    it "returns regular values" do
      Kennel::Utils.presence("a").must_equal "a"
    end

    it "does not return empty values" do
      Kennel::Utils.presence("").must_be_nil
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

  describe ".path_to_url" do
    it "shows app." do
      Kennel::Utils.path_to_url("/111").must_equal "https://app.datadoghq.com/111"
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

    it "raises runtime errors" do
      assert_raises ArgumentError do
        Kennel::Utils.parallel([1, 2, 3, 4, 5]) do
          raise ArgumentError
        end
      end
    end

    it "raises exceptions" do
      assert_raises Interrupt do
        Kennel::Utils.parallel([1, 2, 3, 4, 5]) do
          raise Interrupt
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

  describe ".inline_resource_metadata" do
    it "adds klass and tracking_id" do
      resource = { message: "-- Managed by kennel a:b" }
      Kennel::Utils.inline_resource_metadata(resource, Kennel::Models::Monitor)
      resource[:tracking_id].must_equal "a:b"
      resource[:klass].must_equal Kennel::Models::Monitor
    end
  end
end
