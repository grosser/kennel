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

  def self.reset_instance
    after do
      Kennel.instance_variable_set(:@instance, nil)
      Kennel::ProjectsProvider.remove_class_variable(:@@load_all) if Kennel::ProjectsProvider.class_variable_defined?(:@@load_all)
    end
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

  def self.enable_api
    around { |t| enable_api(&t) }
  end

  def enable_api(&block)
    with_env("DATADOG_APP_KEY" => "x", "DATADOG_API_KEY" => "y", &block)
  end

  def stub_datadog_request(method, path, extra = "")
    stub_request(method, "https://app.datadoghq.com/api/v1/#{path}?#{extra}")
  end

  def with_sorted_hash_keys(value)
    case value
    when Hash
      value.entries.sort_by(&:first).to_h.transform_values { |v| with_sorted_hash_keys(v) }
    when Array
      value.map { |v| with_sorted_hash_keys(v) }
    else
      value
    end
  end

  # generate readables diffs when things are not equal
  def assert_json_equal(a, b)
    a = with_sorted_hash_keys(a)
    b = with_sorted_hash_keys(b)
    JSON.pretty_generate(a).must_equal JSON.pretty_generate(b)
  end

  def validation_errors_from(part)
    part.build
    part.unfiltered_validation_errors.map(&:text)
  end

  def validation_error_from(part)
    errors = validation_errors_from(part)
    errors.length.must_equal(1, "Expected 1 error, got #{errors.inspect}")
    errors.first
  end
end
