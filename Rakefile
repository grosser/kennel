# frozen_string_literal: true
require "bundler/setup"
require "bundler/gem_tasks"
require "bump/tasks"

require "rubocop/rake_task"
RuboCop::RakeTask.new

desc "Run tests"
task :test do
  sh "forking-test-runner test --merge-coverage --quiet"
end

# make sure we always run what travis runs
require "yaml"
travis = YAML.load_file(".travis.yml").fetch("env").map { |v| v.delete("TASK=") }
raise if travis.empty?
task default: travis
