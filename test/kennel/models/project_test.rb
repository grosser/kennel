# frozen_string_literal: true
require_relative "../../test_helper"

SingleCov.covered!

describe Kennel::Models::Project do
  define_test_classes

  describe ".file_location" do
    let(:plain_project_class) do
      Class.new(Kennel::Models::Project) do
        def self.to_s
          "PlainProject" # to make debugging less confusing
        end
      end
    end

    it "finds the file" do
      TestProject.file_location.must_equal "test/test_helper.rb"
    end

    it "cannot detect if there are no methods" do
      Class.new(Kennel::Models::Project).file_location.must_be_nil
    end

    it "detects the file location when defaults-plain is used" do
      eval <<~EVAL, nil, "dir/foo.rb", 1
        plain_project_class.instance_eval do
          defaults(name: 'bar')
        end
      EVAL
      plain_project_class.file_location.must_equal("dir/foo.rb")
    end

    it "detects the file location when defaults-proc is used" do
      eval <<~EVAL, nil, "dir/foo.rb", 1
        plain_project_class.instance_eval do
          defaults(name: -> { 'bar' })
        end
      EVAL
      plain_project_class.file_location.must_equal("dir/foo.rb")
    end

    it "detects the file location when a custom method is used" do
      eval <<~EVAL, nil, "dir/foo.rb", 1
        plain_project_class.define_method(:my_method) { }
      EVAL
      plain_project_class.file_location.must_equal("dir/foo.rb")
    end

    it "removes bundler root if absolute" do
      eval <<~EVAL, nil, "#{Bundler.root}/dir/foo.rb", 1
        plain_project_class.define_method(:my_method) { }
      EVAL
      plain_project_class.file_location.must_equal "dir/foo.rb"
    end

    it "removes Dir.pwd root if absolute" do
      Bundler.expects(:root).returns("/other")
      eval <<~EVAL, nil, "#{Dir.pwd}/dir/foo.rb", 1
        plain_project_class.define_method(:my_method) { }
      EVAL
      plain_project_class.file_location.must_equal "dir/foo.rb"
    end

    it "fails if no relative root can be found and the resource would have no trace of where it came from" do
      assert_raises(RuntimeError) do
        eval <<~EVAL, nil, "/nix/will/break/you/dir/foo.rb", 1
          plain_project_class.define_method(:my_method) { }
        EVAL
        plain_project_class.file_location
      end
    end

    it "caches failure" do
      c = Class.new(Kennel::Models::Project)
      c.expects(:instance_methods).times(1).returns []
      2.times { c.file_location.must_be_nil }
    end

    it "caches success" do
      c = TestProject
      c.remove_instance_variable(:@file_location) rescue false # rubocop:disable Style/RescueModifier
      original = c.instance_methods(false)
      c.expects(:instance_methods).times(1).returns original
      2.times { c.file_location.must_equal "test/test_helper.rb" }
    end
  end

  describe "#tags" do
    it "uses team" do
      TestProject.new.tags.must_equal ["team:test-team"]
    end
  end

  describe "#mention" do
    it "uses teams mention" do
      TestProject.new.mention.must_equal "@slack-foo"
    end
  end

  describe "#validated_parts" do
    it "returns parts" do
      TestProject.new.validated_parts.size.must_equal 0
    end

    it "raises an error if parts did not return an array" do
      bad_project = TestProject.new(parts: -> {
        Kennel::Models::Monitor.new(self)
      })
      assert_raises(RuntimeError) { bad_project.validated_parts }
        .message.must_equal "Project test_project #parts must return an array of Records"
    end
  end
end
