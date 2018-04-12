# frozen_string_literal: true
require_relative "test_helper"
require "tmpdir"

SingleCov.covered!

describe Kennel do
  def write(file, content)
    folder = File.dirname(file)
    FileUtils.mkdir folder unless File.exist?(folder)
    File.write file, content
  end

  capture_stdout
  in_temp_dir do
    write "projects/simple.rb", <<~RUBY
      class TempProject < Kennel::Models::Project
        defaults(
          team: -> { TestTeam.new },
          parts: -> { [
            Kennel::Models::Monitor.new(
              self,
              kennel_id: -> { 'foo' },
              query: -> { "avg(last_5m) > \#{critical}" },
              critical: -> { 1 }
            )
          ] }
        )
      end
    RUBY
  end
  with_env DATADOG_APP_KEY: "app", DATADOG_API_KEY: "api"

  before do
    Kennel.instance_variable_set(:@generated, nil)
    Kennel.instance_variable_set(:@api, nil)
    Kennel.instance_variable_set(:@syncer, nil)
  end

  # we need to clean up so new definitions of TempProject trigger subclass addition
  # and leftover classes do not break other tests
  after do
    Kennel::Models::Project.subclasses.clear
    Object.send(:remove_const, :TempProject) if defined?(TempProject)
  end

  describe ".generate" do
    it "generates" do
      Kennel.generate
      content = File.read("generated/temp_project/foo.json")
      assert content.start_with?("{\n") # pretty generated
      json = JSON.parse(content, symbolize_names: true)
      json[:query].must_equal "avg(last_5m) > 1"
    end

    it "requires in order" do
      write "teams/a.rb", "AAA = 1"
      write "parts/a.rb", "BBB = AAA"
      write "parts/b.rb", "CCC = BBB"
      write "projects/a.rb", "DDD = CCC"
      Kennel.generate
    end

    it "cleans up old stuff" do
      write "generated/bar.json", "HO"
      Kennel.generate
      refute File.exist?("generated/bar.json")
    end

    it "complains when duplicates would be written" do
      write "projects/a.rb", <<~RUBY
        class Foo < Kennel::Models::Project
          defaults(parts: -> { Array.new(2).map { Kennel::Models::Monitor.new(self, kennel_id: -> {"bar"}) } })
        end
      RUBY
      e = assert_raises(RuntimeError) { Kennel.generate }
      e.message.must_equal "foo:bar is defined 2 times"
    end
  end

  describe ".plan" do
    it "plans" do
      Kennel::Api.any_instance.expects(:list).times(3).returns([])
      Kennel.plan
      stdout.string.must_include "Plan:\n\e[32mCreate temp_project:foo\e[0m\n"
    end
  end

  describe ".update" do
    it "update" do
      Kennel::Api.any_instance.expects(:list).times(3).returns([])
      STDIN.expects(:gets).returns("y\n") # proceed ? ... yes!
      Kennel::Api.any_instance.expects(:create).returns(id: 123)

      Kennel.update

      stdout.string.must_include "press 'y' to continue"
      stdout.string.must_include "Created monitor temp_project:foo /monitors#123"
    end

    it "does not update when user does not confirm" do
      Kennel::Api.any_instance.expects(:list).times(3).returns([])
      STDIN.expects(:gets).returns("n\n") # proceed ? ... no!

      Kennel.update

      stdout.string.must_match(/press 'y' to continue: \e\[0m\z/m) # nothing after
    end
  end
end
