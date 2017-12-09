# frozen_string_literal: true
require_relative "../test_helper"

SingleCov.covered!

describe Kennel::GithubReporter do
  let(:reporter) { Kennel::GithubReporter.new("TOKEN") }
  let(:remote_response) { +"origin	git@github.com:foo/bar.git (fetch)" }

  before do
    Kennel::Utils.expects(:capture_sh).with("git rev-parse HEAD").returns("abcd")
    Kennel::Utils.expects(:capture_sh).with("git remote -v").returns(remote_response)
  end

  describe "#report" do
    it "reports success" do
      stub_request(:post, "https://api.github.com/repos/foo/bar/commits/abcd/comments")
        .with(body: { body: "```\nHELLOOOO\n```" }.to_json)
        .to_return(status: 201)
      reporter.report { puts "HELLOOOO" }
    end

    it "can parse https remote" do
      remote_response.replace("origin	https://github.com/foo/bar.git (fetch)")
      reporter.instance_variable_get(:@repo_part).must_equal "foo/bar"
    end

    it "can parse remote from env as samson provides it" do
      Kennel::Utils.unstub(:capture_sh)
      Kennel::Utils.expects(:capture_sh).with("git rev-parse HEAD").returns("abcd")

      with_env PROJECT_REPOSITORY: "git@github.com:bar/baz" do
        reporter.instance_variable_get(:@repo_part).must_equal "bar/baz"
      end
    end

    it "reports error" do
      stub_request(:post, "https://api.github.com/repos/foo/bar/commits/abcd/comments")
        .with(body: { body: "```\nError\n```" }.to_json)
        .to_return(status: 201)
      e = assert_raises(RuntimeError) { reporter.report { raise "whoops" } }
      e.message.must_equal "whoops"
    end
  end
end
