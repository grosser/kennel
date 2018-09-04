# frozen_string_literal: true
require "bundler/setup"
require "maxitest/autorun"
require "maxitest/timeout"
require "tmpdir"
require "kennel/utils"
require "English"
require "./test/integration_helper"

Maxitest.timeout = 10

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
    result = sh "bundle exec rake plan"
    result.gsub!(/\d\.\d+s/, "0.00s")
    result = Kennel::Utils.strip_shell_control(result)
    result.must_equal <<~TXT
      Generating ... 0.00s
      Downloading definitions ... 0.00s
      Diffing ... 0.00s
      Plan:
      Nothing to do
    TXT
  end
end
