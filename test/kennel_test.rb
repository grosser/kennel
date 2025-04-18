# frozen_string_literal: true
require_relative "test_helper"
require "tmpdir"

SingleCov.covered!

describe Kennel do
  define_test_classes

  def write(file, content)
    folder = File.dirname(file)
    FileUtils.mkdir_p folder
    File.write file, content
  end

  let(:models_count) { 4 }
  let(:kennel) { Kennel::Engine.new }

  capture_all
  without_cached_projects
  in_temp_dir
  enable_api

  before do
    write "projects/simple.rb", <<~RUBY
      class TempProject < Kennel::Models::Project
        defaults(
          team: -> { TestTeam.new },
          parts: -> { [
            Kennel::Models::Monitor.new(
              self,
              type: -> { "query alert" },
              kennel_id: -> { 'foo' },
              query: -> { "avg(last_5m) > \#{critical}" },
              critical: -> { 1 }
            )
          ] }
        )
      end
    RUBY
  end

  # we need to clean up so new definitions of TempProject trigger subclass addition
  # and leftover classes do not break other tests
  after do
    Kennel::Models::Project.subclasses.delete_if { |c| c.name.match?(/TestProject\d|TempProject/) }
    Object.send(:remove_const, :TempProject) if defined?(TempProject)
    Object.send(:remove_const, :TempProject2) if defined?(TempProject2)
    Object.send(:remove_const, :TempProject3) if defined?(TempProject3)
  end

  describe ".preload" do
    it "prepares" do
      Kennel::Api.any_instance.expects(:list).times(models_count).returns([])
      kennel.preload
      stdout.string.must_equal ""
    end
  end

  describe ".generate" do
    it "stores if requested" do
      writer = "some writer".dup

      Kennel::PartsSerializer.stubs(:new).returns(writer)

      writer.stubs(:write).with do |parts|
        parts.map(&:tracking_id) == ["temp_project:foo"]
      end.once

      with_env(STORE: nil) { kennel.generate }
    end

    it "does not store if requested" do
      writer = "some writer".dup
      Kennel::PartsSerializer.stubs(:new).returns(writer)
      writer.stubs(:write).never

      with_env(STORE: "false") { kennel.generate }
    end

    it "complains when duplicates would be written" do
      write "projects/a.rb", <<~RUBY
        class TestProject2 < Kennel::Models::Project
          defaults(parts: -> { Array.new(2).map { Kennel::Models::Monitor.new(self, kennel_id: -> {"bar"}) } })
        end
      RUBY
      e = assert_raises(RuntimeError) { kennel.generate }
      e.message.must_equal <<~ERROR
        test_project2:bar is defined 2 times

        use a different `kennel_id` when defining multiple projects/monitors/dashboards to avoid this conflict
      ERROR
    end
  end

  describe ".plan" do
    it "plans" do
      stdout.stubs(:tty?).returns(true)
      Kennel::Api.any_instance.expects(:list).times(models_count).returns([])
      kennel.plan
      stdout.string.must_include "Plan:\n\e[32mCreate monitor temp_project:foo\e[0m\n"
    end
  end

  describe ".update" do
    before do
      Kennel.in.expects(:tty?).returns(true)
      Kennel.err.stubs(:tty?).returns(true)
    end

    it "update" do
      Kennel::Api.any_instance.expects(:list).times(models_count).returns([])
      Kennel.in.expects(:gets).returns("y\n") # proceed ? ... yes!
      Kennel::Api.any_instance.expects(:create).returns(Kennel::Api.with_tracking("monitor", id: 123))

      kennel.update

      stderr.string.must_include "press 'y' to continue"
      stdout.string.must_include "Created monitor temp_project:foo https://app.datadoghq.com/monitors/123"
    end

    it "does not update when user does not confirm" do
      Kennel::Api.any_instance.expects(:list).times(models_count).returns([])
      Kennel.in.expects(:gets).returns("n\n") # proceed ? ... no!
      stdout.expects(:tty?).returns(true)
      stderr.expects(:tty?).returns(true)

      kennel.update

      stderr.string.must_match(/press 'y' to continue: \e\[0m\z/m) # nothing after
    end
  end
end
