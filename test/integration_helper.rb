# frozen_string_literal: true
require "base64"
require "faraday"

module IntegrationHelper
  # obfuscated keys so it is harder to find them
  TEST_KEYS = Base64.decode64("REFUQURPR19BUElfS0VZPThkMDU5MmY4YmE5MDhiNWE2MmRmN2MwMGM3MGUy\nNmYwCkRBVEFET0dfQVBQX0tFWT05YjNkYWQxMzQyMmY5ZGJjMWU1NDY3YTk0\nMTdmNWYxNzk4ZjJmZTcw\n")

  def with_test_keys_in_dotenv
    File.write(".env", TEST_KEYS)
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
    example = "projects/example.rb"
    File.write("Gemfile", local)
    File.write(example, <<~RUBY)
      module Teams
        class MyTeam < Kennel::Models::Team
          defaults(
            slack: -> { "my-alerts" },
            email: -> { "my-team@exmaple.com" }
          )
        end
      end

      class MyProject < Kennel::Models::Project
        defaults(
          team: -> { Teams::MyTeam.new }, # use existing team or create new one in teams/
          parts: -> {
            [
              Kennel::Models::Monitor.new(
                self,
                type: -> { "query alert" },
                kennel_id: -> { "load-too-high" }, # make up a unique name
                name: -> { "My Kennel Test Monitor" }, # nice descriptive name that will show up in alerts and emails
                message: -> {
                  <<~TEXT
                    Foobar will be slow and that could cause Barfoo to go down.
                    Add capacity or debug why it is suddenly slow.
                    \#{super()}
                  TEXT
                },
                query: -> { "avg(last_5m):avg:system.load.5{hostgroup:api} by {pod} > \#{critical}" },
                critical: -> { 20 }
              ),
              Kennel::Models::Dash.new(
                self,
                title: -> { "My Kennel Test Dash" },
                description: -> { "Overview of foobar" },
                template_variables: -> { ["environment"] }, # see https://docs.datadoghq.com/api/?lang=ruby#timeboards
                kennel_id: -> { "overview-dashboard" }, # make up a unique name
                definitions: -> {
                  [ # An array or arrays, each one is a graph in the dashboard, alternatively a hash for finer control
                    [
                      # title, viz, type, query, edit an existing graph and see the json definition
                      "Graph name", "timeseries", "area", "sum:mystats.foobar{$environment}"
                    ],
                    [
                      # queries can be an Array as well, this will generate multiple requests
                      # for a single graph
                      "Graph name", "timeseries", "area", ["sum:mystats.foobar{$environment}", "sum:mystats.success{$environment}"],
                      # add events too ...
                      events: [{q: "tags:foobar,deploy", tags_execution: "and"}]
                    ]
                  ]
                }
              ),
              Kennel::Models::Screen.new(
                self,
                board_title: -> { "My Kennel Test Screen" },
                kennel_id: -> { "test-screen" },
                widgets: -> {
                  [
                    {text: "Hello World", height: 6, width: 24, x: 0, y: 0, type: "free_text"},
                    {title_text: "Test", height: 12, width: 36, timeframe: "1mo", x: 0, y: 6, type: "timeseries", tile_def: {viz: "timeseries", requests: [{q: "avg:test.metric{*}.as_count()", type: "line"}]}}
                  ]
                }
              )
            ]
          }
        )
      end
    RUBY
    yield
  ensure
    File.write("Gemfile", old)
    File.unlink(example) if File.exist?(example)
  end

  # we need something to build our test dashboards on
  # NOTE: due to a bug newly create metrics do not show up in the UI,
  # force it by modifying the url https://app.datadoghq.com/metric/explorer?exp_metric=test.metric
  def report_fake_metric
    api_key = TEST_KEYS[/DATADOG_API_KEY=(.*)/, 1] || raise
    payload = {
      series: [
        {
          metric: "test.metric",
          points: [["$currenttime", 20]],
          type: "rate",
          interval: 20,
          host: "test.example.com",
          tags: ["environment:test"]
        }
      ]
    }
    response = Faraday.post "https://api.datadoghq.com/api/v1/series?api_key=#{api_key}", payload.to_json
    raise "Error reporting fake metric #{response}" unless response.success?
  end
end
