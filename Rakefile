# frozen_string_literal: true
require "bundler/setup"
require "bundler/gem_tasks"
require "bump/tasks"
require "json"

require "rubocop/rake_task"
RuboCop::RakeTask.new

desc "Run tests"
task :test do
  sh "forking-test-runner test --merge-coverage --quiet"
end

desc "Run integration tests"
task :integration do
  sh "ruby test/integration.rb"
end

desc "Turn template folder into a play area"
task :play do
  require "./test/integration_helper"
  include IntegrationHelper
  report_fake_metric
  Dir.chdir "template" do
    with_test_keys_in_dotenv do
      with_local_kennel do
        exit! # do not run ensure blocks that clean things up
      end
    end
  end
end

desc "Keep readmes in sync"
task :readme do
  readme = File.read("Readme.md")
  raise "Unable to find ADD" unless readme.gsub!(/<!-- ONLY IN .*?\n(.*?)\n-->/m, "\\1")
  raise "Unable to find REMOVE" unless readme.gsub!(/<!-- NOT IN .*? -->.*?<!-- NOT IN -->\n/m, "")
  raise "Unable to find images" unless readme.gsub!(/template\//, "")
  File.write("template/Readme.md", readme)
  sh "git diff HEAD --exit-code -- template/Readme.md"
end

# make sure we always run what travis runs
require "yaml"
ci = YAML.load_file(".github/workflows/actions.yml").dig("jobs", "build", "strategy", "matrix", "task")
raise if ci.empty?
task default: ci
