# frozen_string_literal: true
require_relative "../../test_helper"

require "net/http"
require "uri"

SingleCov.covered!

describe Kennel::Auth::CallbackServer do
  def free_redirect_port
    Kennel::Auth::CallbackServer::REDIRECT_PORTS.find do |port|
      server = TCPServer.new("127.0.0.1", port)
      server.close
      true
    rescue Errno::EADDRINUSE
      false
    end
  end

  def callback_server(**options)
    Kennel::Auth::CallbackServer.new(
      pinned_port: free_redirect_port || raise("no redirect ports available for test"),
      **options
    )
  end

  def request_in_thread(url)
    Thread.new { Net::HTTP.get_response(URI(url)) }
  end

  it "lists redirect uris for all supported ports" do
    Kennel::Auth::CallbackServer.redirect_uris.must_equal(
      [8000, 8080, 8888, 9000].map { |port| "http://127.0.0.1:#{port}/oauth/callback" }
    )
  end

  it "builds a redirect uri from the selected port" do
    port = free_redirect_port || raise("no redirect ports available for test")
    server = Kennel::Auth::CallbackServer.new(pinned_port: port)

    server.redirect_uri.must_equal "http://127.0.0.1:#{port}/oauth/callback"
  ensure
    server&.close
  end

  it "raises on unsupported pinned ports" do
    error = assert_raises(ArgumentError) { Kennel::Auth::CallbackServer.new(pinned_port: 9999) }

    error.message.must_include "Unsupported callback port"
  end

  it "raises a clear error when webrick is unavailable" do
    error = assert_raises(Kennel::Auth::CallbackServer::UnavailableError) do
      Kennel::Auth::CallbackServer.new(library_loader: -> { raise LoadError, "cannot load such file -- webrick" })
    end

    error.message.must_include 'add gem "webrick" to the Gemfile and run bundle install'
  end

  it "times out when no callback arrives" do
    server = callback_server

    error = assert_raises(RuntimeError) { server.wait_for_callback(timeout: 0.01) }
    error.message.must_include "timed out"
  ensure
    server&.close
  end

  it "raises when no callback ports are available" do
    Kennel::Auth::CallbackServer.any_instance.stubs(:build_server).raises(Errno::EADDRINUSE)

    error = assert_raises(RuntimeError) { Kennel::Auth::CallbackServer.new }
    error.message.must_include "could not bind to any OAuth callback port"
  ensure
    Kennel::Auth::CallbackServer.any_instance.unstub(:build_server)
  end

  it "captures callback params" do
    server = callback_server

    WebMock.disable_net_connect!(allow_localhost: true)
    request_thread = request_in_thread("http://127.0.0.1:#{server.port}/oauth/callback?code=abc&state=xyz")
    result = server.wait_for_callback(timeout: 2)

    request_thread.join
    result.must_equal("code" => "abc", "state" => "xyz")
  ensure
    WebMock.disable_net_connect!
    server&.close
    request_thread&.kill
  end

  it "captures oauth errors and returns a 400 response" do
    server = callback_server

    WebMock.disable_net_connect!(allow_localhost: true)
    request_thread = request_in_thread(
      "http://127.0.0.1:#{server.port}/oauth/callback?error=access_denied&error_description=denied"
    )
    result = server.wait_for_callback(timeout: 2)
    response = request_thread.value

    response.code.must_equal "400"
    response.body.must_include "Authentication Failed"
    result.must_equal("error" => "access_denied", "error_description" => "denied")
  ensure
    WebMock.disable_net_connect!
    server&.close
    request_thread&.kill
  end

  it "can be closed before it is started" do
    server = callback_server

    server.close
    server.close
  end

  it "ignores close when the server is already gone" do
    server = callback_server
    server.instance_variable_set(:@server, nil)

    server.close
  end
end
