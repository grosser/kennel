# frozen_string_literal: true
require "bundler/setup"

require "maxitest/global_must"
require "maxitest/autorun"
require "maxitest/timeout"

require "tmpdir"
require "kennel/utils"
require "English"

require "./test/integration_helper"

Maxitest.timeout = 30

describe "Integration" do
  include IntegrationHelper

  def sh(script)
    result = `#{script}`
    raise "Failed:\n#{script}\n#{result}" unless $CHILD_STATUS.success?
    result
  end

  around do |test|
    Dir.mktmpdir do |dir|
      FileUtils.cp_r("template", dir)
      Dir.chdir("#{dir}/template") do
        with_test_keys_in_dotenv do
          with_local_kennel do
            sh "bundle install --quiet"
            test.call
          end
        end
      end
    end
  end

  it "has an empty diff" do
    # result = sh "echo y | bundle exec rake kennel:update_datadog" # Uncomment this to apply know good diff
    result = sh "bundle exec rake plan 2>&1"
    result.gsub!(/\d\.\d+s/, "0.00s")
    result.must_equal <<~TXT
      Finding parts ...
      Finding parts ... 0.00s
      Building json ...
      Building json ... 0.00s
      Storing ...
      Storing ... 0.00s
      Downloading definitions ...
      Downloading definitions ... 0.00s
      Diffing ...
      Diffing ... 0.00s
      Plan:
      Nothing to do
    TXT
  end
end
