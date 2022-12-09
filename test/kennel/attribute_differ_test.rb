# frozen_string_literal: true
require_relative "../test_helper"

SingleCov.covered!

describe Kennel::AttributeDiffer do
  let(:printer) { Kennel::AttributeDiffer.new }

  before do
    Kennel.out.stubs(:tty?).returns(false)
  end

  describe "#format" do
    it "prints addition" do
      printer.format("+", "foo", "a", "b").must_equal "  +foo \"b\" -> \"a\""
    end

    it "formats simple change" do
      printer.format("~", "foo", "a", "b").must_equal "  ~foo \"a\" -> \"b\""
    end

    it "prints complex change" do
      printer.format("~", "foo", [1], [2]).must_equal "  ~foo [1] -> [2]"
    end

    it "formats large change" do
      printer.format("~", "foo", "a" * 100, "b" * 100).must_equal <<~DIFF.gsub(/^/, "  ").rstrip
        ~foo
          "#{"a" * 100}" ->
          "#{"b" * 100}"
      DIFF
    end

    describe "diff limit" do
      it "limits the size of diffs" do
        output = printer.format("~", "foo", 100.times.map(&:to_s).join("\n"), "")
        output.must_include "- 48\n"
        output.wont_include "- 49\n"
        output.must_include "(Diff for this item truncated after 50 lines. Rerun with MAX_DIFF_LINES=100 to see more)"
      end

      it "can configure the diff size limit" do
        with_env MAX_DIFF_LINES: "20" do
          output = printer.format("~", "foo", 100.times.map(&:to_s).join("\n"), "")
          output.must_include "- 18\n"
          output.wont_include "- 19\n"
          output.must_include "(Diff for this item truncated after 20 lines. Rerun with MAX_DIFF_LINES=40 to see more)"
        end
      end
    end
  end

  describe "#multiline_diff" do
    def call(a, b)
      printer.send(:multiline_diff, a, b)
    end

    it "can replace" do
      call("a", "b").must_equal ["- a", "+ b"]
    end

    it "can add" do
      call("", "b").must_equal ["+ b"]
    end

    it "can remove" do
      call("a", "").must_equal ["- a"]
    end

    it "can keep" do
      call("a", "a").must_equal ["  a"]
    end

    it "shows newlines" do
      call("\na", "a\n\n").must_equal ["- ", "  a", "+ ", "+ "]
    end
  end

  describe "#pretty_inspect" do
    it "shows hashes that rubocop likes" do
      printer.send(:pretty_inspect, foo: "bar", bar: 1).must_equal "{ foo: \"bar\", bar: 1 }"
    end

    it "supports nesting" do
      printer.send(:pretty_inspect, [{ foo: { bar: "bar" } }]).must_equal "[{ foo: { bar: \"bar\" } }]"
    end
  end
end
