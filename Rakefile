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
  keep = File.read("Readme.md").scan(/<!-- CUT.*? -->.*?<!-- CUT -->\n/m)
  raise "expected 2 parts, found #{keep.size}" unless keep.size == 2
  template = File.read("template/Readme.md")
  template.sub!("## Structure", "#{keep[0]}\n## Structure")
  template += keep[1]
  template.gsub!("(github/", "(template/github/")
  File.write("Readme.md", template)
  sh "git diff HEAD --exit-code -- Readme.md"
end

# make sure we always run what travis runs
require "yaml"
travis = YAML.load_file(".travis.yml").fetch("env").map { |v| v.delete("TASK=") }
raise if travis.empty?
task default: travis
