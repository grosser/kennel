# frozen_string_literal: true
require "base64"

module IntegrationHelper
  def with_test_keys_in_dotenv
    # obfuscated keys so it is harder to find them
    env = "REFUQURPR19BUElfS0VZPThkMDU5MmY4YmE5MDhiNWE2MmRmN2MwMGM3MGUy\nNmYwCkRBVEFET0dfQVBQX0tFWT05YjNkYWQxMzQyMmY5ZGJjMWU1NDY3YTk0\nMTdmNWYxNzk4ZjJmZTcw\n"
    File.write(".env", Base64.decode64(env))
    Bundler.with_clean_env do
      # we need to make sure we use the test credentials
      # so delete real credentials in the users env
      ENV.delete "DATADOG_API_KEY"
      ENV.delete "DATADOG_APP_KEY"
      yield
    end
  ensure
    File.unlink(".env") if File.exist?(".env")
  end

  def with_local_kennel
    old = File.read("Gemfile")
    local = old.sub('"kennel"', "'kennel', path: '#{File.dirname(__dir__)}'")
    raise ".sub failed" if old == local
    File.write("Gemfile", local)
    yield
  ensure
    File.write("Gemfile", old)
  end
end
