# frozen_string_literal: true
require_relative "../test_helper"

SingleCov.covered!

describe Kennel::TagsValidation do
  define_test_classes

  describe "#validate_json" do
    let(:tags) { ["team:bar"] }
    let(:dashboard) do
      local_tags = tags
      Kennel::Models::Dashboard.new(
        TestProject.new,
        kennel_id: -> { "test" },
        tags: -> { local_tags },
        layout_type: "foo",
        title: "bar"
      )
    end

    def call
      tags = dashboard.build[:tags]
      [tags, dashboard.filtered_validation_errors.map(&:tag)]
    end

    it "is valid" do
      call.must_equal [["team:bar"], []]
    end

    it "dedupes" do
      tags << "team:bar"
      call.must_equal [["team:bar"], []]
    end

    it "fails on invalid" do
      tags << "team:B A R"
      call[1].must_equal [:tags_invalid]
    end
  end
end
