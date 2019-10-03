# frozen_string_literal: true
require_relative "../../test_helper"

SingleCov.covered!

describe Kennel::Models::Base do
  class TestBase < Kennel::Models::Base
    settings :foo, :bar, :unset
    defaults(
      foo: -> { "foo" },
      bar: -> { "bar" }
    )
  end

  describe "#kennel_id" do
    it "snake-cases to work as file/tag" do
      TestBase.new.kennel_id.must_equal "test_base"
    end

    it "does not allow using generic names" do
      e = assert_raises ArgumentError do
        Kennel::Models::Monitor.new(TestProject.new).kennel_id
      end
      message = e.message
      assert message.sub!(/ \S+?:\d+/, " file.rb:123")
      message.must_equal "Set :kennel_id for project test_project on file.rb:123:in `initialize'"
    end

    it "does not allow using generic names for projects" do
      e = assert_raises ArgumentError do
        Kennel::Models::Project.new.kennel_id
      end
      message = e.message
      assert message.sub!(/\S+?:\d+/, "file.rb:123")
      message.must_equal "Set :kennel_id on file.rb:123:in `new'"
    end

    it "does not allow using generic names" do
      e = assert_raises ArgumentError do
        Kennel::Models::Monitor.new(TestProject.new, name: -> { "My Bad monitor" }).kennel_id
      end
      message = e.message
      assert message.sub!(/ \S+?:\d+/, " file.rb:123")
      message.must_equal "Set :kennel_id for project test_project on file.rb:123:in `initialize'"
    end
  end

  describe "#name" do
    it "is readable for nice names in the UI" do
      TestBase.new.name.must_equal "TestBase"
    end
  end

  describe ".to_json" do
    it "blows up when used by accident instead of rendering unexpected json" do
      assert_raises(NotImplementedError) { TestBase.new.to_json }
    end
  end
end
