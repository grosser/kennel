# frozen_string_literal: true
require "bundler/setup"
require "maxitest/autorun"
require "maxitest/timeout"
require "tmpdir"
require "base64"
require "kennel/utils"
require "English"

Maxitest.timeout = 10

describe "Integration" do
  def sh(script)
    result = `#{script}`
    raise "Failed:\n#{script}\n#{result}" unless $CHILD_STATUS.success?
    result
  end

  around do |test|
    Dir.mktmpdir do |dir|
      FileUtils.cp_r("template", dir)
      Dir.chdir("#{dir}/template") do
        # obfuscated keys so it is harder to find them
        env = "REFUQURPR19BUElfS0VZPThkMDU5MmY4YmE5MDhiNWE2MmRmN2MwMGM3MGUy\nNmYwCkRBVEFET0dfQVBQX0tFWT05YjNkYWQxMzQyMmY5ZGJjMWU1NDY3YTk0\nMTdmNWYxNzk4ZjJmZTcw\n"
        File.write(".env", Base64.decode64(env))

        Bundler.with_clean_env do
          # we need to make sure we use the test credentials
          # so delete real credentials in the users env
          ENV.delete "DATADOG_API_KEY"
          ENV.delete "DATADOG_APP_KEY"

          sh "bundle install --quiet"

          test.call
        end
      end
    end
  end

  it "has an empty diff" do
    result = sh "bundle exec rake plan"
    result.gsub!(/\d\.\d+s/, "0.00s")
    result = Kennel::Utils.strip_shell_control(result)
    result.must_equal <<~TXT
      Generating ... 0.00s
      Downloading definitions ... 0.00s
      Diffing ... 0.00s
      Plan:
      Nothing to do.
    TXT
  end
end
