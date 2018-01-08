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
  end

  describe ".report_plan_to_github" do
    with_env GITHUB_TOKEN: "abc", DEPLOY_URL: "foo"

    it "reports" do
      Kennel::Utils.stubs(capture_sh: "foo github.com:sdfsfd/sdfsd.git")
      Kennel::GithubReporter.any_instance.expects(:report)
      Kennel.report_plan_to_github
    end
  end
end
