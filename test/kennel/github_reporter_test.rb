# frozen_string_literal: true
require_relative "../test_helper"

SingleCov.covered!

describe Kennel::GithubReporter do
  let(:remote_response) { +"origin	git@github.com:foo/bar.git (fetch)" }
  let(:show_response) { +"commit abcd" }

  before do
    @git_remote = Kennel::Utils.expects(:capture_sh).with("git remote -v").returns(remote_response)
    Kennel::Utils.expects(:capture_sh).with("git show HEAD").returns(show_response)
  end

  describe ".report" do
    it "does not report when no token was given" do
      Kennel::Utils.unstub(:capture_sh)
      Kennel::Utils.expects(:capture_sh).never
      a = nil
      Kennel::GithubReporter.report(nil) { a = 1 }
      a.must_equal 1
    end

    it "reports when token was given" do
      request = stub_request(:post, "https://api.github.com/repos/foo/bar/commits/abcd/comments").to_return(status: 201)
      a = nil
      Kennel::GithubReporter.report("foo") { a = 1 }
      a.must_equal 1
      assert_requested request
    end
  end

  describe "#report" do
    let(:reporter) { Kennel::GithubReporter.new("TOKEN") }

    it "reports success" do
      request = stub_request(:post, "https://api.github.com/repos/foo/bar/commits/abcd/comments")
        .with(body: { body: "```\nHELLOOOO\n```" }.to_json)
        .to_return(status: 201)
      Kennel::Console.capture_stdout { reporter.report { Kennel.out.puts "HELLOOOO" } }.must_equal "HELLOOOO\n"
      assert_requested request
    end

    it "truncates long comments" do
      msg = "a" * 2 * Kennel::GithubReporter::MAX_COMMENT_SIZE
      body = nil
      request = stub_request(:post, "https://api.github.com/repos/foo/bar/commits/abcd/comments")
        .with { |r| body = JSON.parse(r.body).fetch("body") }
        .to_return(status: 201)
      Kennel::Console.capture_stdout { reporter.report { Kennel.out.puts msg } }
      assert_requested request
      body.bytesize.must_equal Kennel::GithubReporter::MAX_COMMENT_SIZE
      body.must_match(/\A```.*#{Regexp.escape(Kennel::GithubReporter::TRUNCATED_MSG)}\z/m)
    end

    it "can parse https remote" do
      remote_response.replace("origin	https://github.com/foo/bar.git (fetch)")
      reporter.instance_variable_get(:@repo_part).must_equal "foo/bar"
    end

    it "can create PR comments for squash" do
      show_response << "\n  foo (#123)"
      request = stub_request(:post, "https://api.github.com/repos/foo/bar/issues/123/comments").to_return(status: 201)
      Kennel::Console.capture_stdout { reporter.report { Kennel.out.puts "HEY" } }
      assert_requested request
    end

    it "can create PR comments for merge" do
      show_response << "\n  Merge pull request #123"
      request = stub_request(:post, "https://api.github.com/repos/foo/bar/issues/123/comments").to_return(status: 201)
      Kennel::Console.capture_stdout { reporter.report { Kennel.out.puts "HEY" } }
      assert_requested request
    end

    it "can create merge comments" do
      show_response.replace "commit: nope\nMerge: foo abcd"
      request = stub_request(:post, "https://api.github.com/repos/foo/bar/commits/abcd/comments").to_return(status: 201)
      Kennel::Console.capture_stdout { reporter.report { Kennel.out.puts "HEY" } }
      assert_requested request
    end

    it "can parse remote from env via custom var" do
      @git_remote.never

      with_env PROJECT_REPOSITORY: "git@github.com:bar/baz" do
        reporter.instance_variable_get(:@repo_part).must_equal "bar/baz"
      end
    end

    it "can take remote from env as github actions provides it" do
      @git_remote.never

      with_env GITHUB_REPOSITORY: "bar/baz" do
        reporter.instance_variable_get(:@repo_part).must_equal "bar/baz"
      end
    end

    it "shows user errors" do
      request = stub_request(:post, "https://api.github.com/repos/foo/bar/commits/abcd/comments")
        .with(body: { body: "```\nError:\nwhoops\n```" }.to_json)
        .to_return(status: 201)
      e = assert_raises(RuntimeError) { reporter.report { raise "whoops" } }
      e.message.must_equal "whoops"
      assert_requested request
    end

    it "shows api errors" do
      request = stub_request(:post, "https://api.github.com/repos/foo/bar/commits/abcd/comments")
        .to_return(status: 301, body: "Nope")
      e = assert_raises(RuntimeError) { reporter.report {} }
      e.message.must_equal <<~TEXT.strip
        failed to POST to github:
        https://api.github.com/repos/foo/bar/commits/abcd/comments -> 301
        Nope
      TEXT
      assert_requested request
    end
  end
end
