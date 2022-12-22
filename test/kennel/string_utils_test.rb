# frozen_string_literal: true
require_relative "../test_helper"

SingleCov.covered!

describe Kennel::StringUtils do
  describe ".snake_case" do
    it "converts namespaced classes" do
      Kennel::StringUtils.snake_case("Foo::Bar").must_equal "foo_bar"
    end

    it "converts classes with all-caps" do
      Kennel::StringUtils.snake_case("Foo2BarBAZ").must_equal "foo2_bar_baz"
    end

    it "converts dashes for external users" do
      Kennel::StringUtils.snake_case("fo-o-bar").must_equal "fo_o_bar"
    end
  end

  describe ".title_case" do
    it "converts snake case" do
      Kennel::StringUtils.title_case("foo_bar").must_equal "Foo Bar"
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
        Kennel::StringUtils.parameterize(from).must_equal to
      end
    end
  end

  describe ".truncate_lines" do
    def call(text)
      Kennel::StringUtils.truncate_lines(text, to: 2, warning: "SNIP!")
    end

    it "leaves short alone" do
      call("a\nb").must_equal "a\nb"
    end

    it "truncates long" do
      call("a\nb\nc").must_equal "a\nb\nSNIP!"
    end

    it "keeps sequential newlines" do
      call("a\n\nb\nc").must_equal "a\n\nSNIP!"
    end
  end
end
