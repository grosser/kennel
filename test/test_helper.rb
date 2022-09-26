# frozen_string_literal: true
require "bundler/setup"

require "single_cov"
SingleCov.setup :minitest

# make CI and local behave the same
ENV.delete("CI")
ENV.delete("GITHUB_REPOSITORY")

require "maxitest/global_must"
require "maxitest/autorun"
require "maxitest/timeout"
require "webmock/minitest"
require "mocha/minitest"

$LOAD_PATH.unshift "lib"

require "kennel"

Minitest::Test.class_eval do
  def self.with_test_classes
    eval <<~'RUBY', nil, "test/test_helper.rb", __LINE__ + 1
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
    RUBY
  end

  def reset_instance
    Kennel.instance_variable_set(:@instance, nil)
  end

  def self.reset_instance
    after { reset_instance }
  end

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

    before do
      Kennel.out = stdout
      Kennel.err = stderr
    end

    reset_instance
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
    stub_request(method, "https://app.datadoghq.com/api/v1/#{path}?#{extra}")
  end

  # generate readables diffs when things are not equal
  def assert_json_equal(a, b)
    JSON.pretty_generate(a).must_equal JSON.pretty_generate(b)
  end

  def validation_error_message(&block)
    assert_raises(Kennel::ValidationError, &block).message
  end
end
