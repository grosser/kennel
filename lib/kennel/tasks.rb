# frozen_string_literal: true
require "English"
require "kennel"
require "kennel/unmuted_alerts"
require "kennel/importer"
require "json"

Dir.children("#{__dir__}/tasks").each { |f| require_relative "tasks/#{File.basename(f, ".rb")}" }

module Kennel
  module Tasks
    class << self
      def kennel
        @kennel ||= Kennel::Engine.new
      end

      def abort(message = nil)
        Kennel.err.puts message if message
        raise SystemExit.new(1), message
      end

      def load_environment
        @load_environment ||= begin
          require "kennel"
          gem "dotenv"
          require "dotenv"
          source = ".env"

          # warn when users have things like DATADOG_TOKEN already set and it will not be loaded from .env
          # (KENNEL_SILENCE_UPDATED_ENV is intentionally not documented - users see it when needed)
          unless ENV["KENNEL_SILENCE_UPDATED_ENV"]
            updated = Dotenv.parse(source).select { |k, v| ENV[k] && ENV[k] != v }
            warn "Environment variables #{updated.keys.join(", ")} need to be unset to be sourced from #{source}" if updated.any?
          end

          Dotenv.load(source)
          true
        end
      end

      def ci
        load_environment

        if on_default_branch? && git_push?
          Kennel::Tasks.kennel.strict_imports = false
          Kennel::Tasks.kennel.update
        else
          Kennel::Tasks.kennel.plan # show plan in CI logs
        end
      end

      def on_default_branch?
        branch = (ENV["TRAVIS_BRANCH"] || ENV["GITHUB_REF"]).to_s.sub(/^refs\/heads\//, "")
        if (default = ENV["DEFAULT_BRANCH"])
          branch == default
        else
          ["main", "master"].include?(branch)
        end
      end

      def git_push?
        (ENV["TRAVIS_PULL_REQUEST"] == "false" || ENV["GITHUB_EVENT_NAME"] == "push")
      end
    end
  end
end

namespace :kennel do
  desc "Ensure there are no uncommited changes that would be hidden from PR reviewers"
  task no_diff: :generate do
    result = `git status --porcelain generated/`.strip
    Kennel::Tasks.abort "Diff found:\n#{result}\nrun `rake generate` and commit the diff to fix" unless result == ""
    Kennel::Tasks.abort "Error during diffing" unless $CHILD_STATUS.success?
  end

  desc "store definitions in generated/"
  task generate: :environment do
    Kennel::Tasks.kennel.generate
  end

  # also generate parts so users see and commit updated generated automatically
  # (generate must run after plan to enable parallel .download+.generate inside of .plan)
  desc "show planned datadog changes (scope with PROJECT=name)"
  task plan: :environment do
    Kennel::Tasks.kennel.preload
    Kennel::Tasks.kennel.generate unless ENV["KENNEL_NO_GENERATE"]
    Kennel::Tasks.kennel.plan
  end

  desc "update datadog (scope with PROJECT=name)"
  task update_datadog: :environment do
    Kennel::Tasks.kennel.preload
    Kennel::Tasks.kennel.generate unless ENV["KENNEL_NO_GENERATE"]
    Kennel::Tasks.kennel.update
  end

  desc "update on push to the default branch, otherwise show plan"
  task :ci do
    Kennel::Tasks.ci
  end

  desc "show unmuted alerts filtered by TAG, for example TAG=team:foo"
  task alerts: :environment do
    tag = ENV["TAG"] || Kennel::Tasks.abort("Call with TAG=foo:bar")
    Kennel::UnmutedAlerts.print(Kennel::Api.new, tag)
  end

  task :environment do
    Kennel::Tasks.load_environment
  end
end
