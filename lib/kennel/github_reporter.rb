# frozen_string_literal: true
# Not used in here, but in our templated repo ... so keeping it around for now.
module Kennel
  class GithubReporter
    MAX_COMMENT_SIZE = 65536
    TRUNCATED_MSG = "\n```\n... (truncated)" # finish the code block so it look nice

    class << self
      def report(token, &block)
        return yield unless token
        new(token).report(&block)
      end
    end

    def initialize(token, ref: "HEAD")
      @token = token
      commit = Utils.capture_sh("git show #{ref}")
      @sha = commit[/^Merge: \S+ (\S+)/, 1] || commit[/\Acommit (\S+)/, 1] || raise("Unable to find commit")
      @pr = commit[/^\s+.*\(#(\d+)\)/, 1] # from squash
      @repo_part = ENV["GITHUB_REPOSITORY"] || begin
        origin = ENV["PROJECT_REPOSITORY"] || Utils.capture_sh("git remote -v").split("\n").first
        origin[%r{github\.com[:/](\S+?)(\.git|$)}, 1] || raise("no origin found in #{origin}")
      end
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

      path = (@pr ? "/repos/#{@repo_part}/issues/#{@pr}/comments" : "/repos/#{@repo_part}/commits/#{@sha}/comments")
      post path, body: body
    end

    private

    def post(path, data)
      url = "https://api.github.com#{path}"
      response = Faraday.post(url, data.to_json, authorization: "token #{@token}")
      raise "failed to POST to github:\n#{url} -> #{response.status}\n#{response.body}" unless response.status == 201
    end
  end
end
