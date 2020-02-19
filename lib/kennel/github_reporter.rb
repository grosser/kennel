# frozen_string_literal: true
module Kennel
  class GithubReporter
    MAX_COMMENT_SIZE = 65536
    TRUNCATED_MSG = "\n```\n... (truncated)" # finish the code block so it look nice

    class << self
      def report(token, &block)
        return yield unless token
        new(token, Utils.capture_sh("git rev-parse HEAD").strip).report(&block)
      end
    end

    def initialize(token, git_sha)
      @token = token
      @git_sha = git_sha
      origin = ENV["PROJECT_REPOSITORY"] || Utils.capture_sh("git remote -v").split("\n").first
      @repo_part = origin[%r{github\.com[:/](.+?)(\.git|$)}, 1] || raise("no origin found")
    end

    def report(&block)
      output = Utils.strip_shell_control(Utils.tee_output(&block).strip)
    rescue StandardError
      output = "Error:\n#{$ERROR_INFO.message}"
      raise
    ensure
      comment "```\n#{output || "Error"}\n```"
    end

    # https://developer.github.com/v3/repos/comments/#create-a-commit-comment
    def comment(body)
      # truncate to maximum allowed comment size for github to avoid 422
      if body.bytesize > MAX_COMMENT_SIZE
        body = body.byteslice(0, MAX_COMMENT_SIZE - TRUNCATED_MSG.bytesize) + TRUNCATED_MSG
      end

      post "commits/#{@git_sha}/comments", body: body
    end

    private

    def post(path, data)
      url = "https://api.github.com/repos/#{@repo_part}/#{path}"
      response = Faraday.post(url, data.to_json, authorization: "token #{@token}")
      raise "failed to POST to github:\n#{url} -> #{response.status}\n#{response.body}" unless response.status == 201
    end
  end
end
