# frozen_string_literal: true
require "bundler/setup"

require "single_cov"
SingleCov.setup :minitest

ENV.delete("CI") # make travis and local behave the same

require "maxitest/autorun"
require "maxitest/timeout"
require "webmock/minitest"
require "mocha/setup"

$LOAD_PATH.unshift "lib"

require "kennel"

class TestProject < Kennel::Models::Project
  defaults(
    team: -> { TestTeam.new },
    parts: -> { [] }
  )
end

class SubTestProject < TestProject
end

class TestTeam < Kennel::Models::Team
  defaults(mention: -> { "@slack-foo" })
end

module Teams
  class MyTeam < Kennel::Models::Team
    defaults(mention: -> { "@slack-my" })
  end
end

Minitest::Test.class_eval do
  def with_env(hash)
    old = ENV.to_h
    hash.each { |k, v| ENV[k.to_s] = v }
    yield
  ensure
    ENV.replace(old)
  end

  def self.with_env(hash)
    around { |t| with_env(hash, &t) }
  end

  def self.capture_all
    let(:stdout) { StringIO.new }
    let(:stderr) { StringIO.new }

    around do |t|
      Kennel.out = stdout
      Kennel.err = stderr
      t.call
    ensure
      Kennel.out = STDOUT
      Kennel.err = STDERR
    end
  end

  def self.in_temp_dir(&block)
    around do |t|
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          instance_eval(&block) if block
          t.call
        end
      end
    end
  end

  def deep_dup(value)
    Marshal.load(Marshal.dump(value))
  end

  def stub_datadog_request(method, path, extra = "")
    stub_request(method, "https://app.datadoghq.com/api/v1/#{path}?api_key=api&application_key=app#{extra}")
  end
end
