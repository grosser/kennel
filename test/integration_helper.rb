# frozen_string_literal: true
require "base64"
require "faraday"

module IntegrationHelper
  # obfuscated keys so it is harder to find them
  TEST_KEYS = Base64.decode64("REFUQURPR19BUElfS0VZPThkMDU5MmY4YmE5MDhiNWE2MmRmN2MwMGM3MGUy\nNmYwCkRBVEFET0dfQVBQX0tFWT05YjNkYWQxMzQyMmY5ZGJjMWU1NDY3YTk0\nMTdmNWYxNzk4ZjJmZTcw\n")

  def with_test_keys_in_dotenv
    File.write(".env", TEST_KEYS)
    Bundler.with_unbundled_env do
      # we need to make sure we use the test credentials
      # so delete real credentials in the users env
      ENV.delete "DATADOG_API_KEY"
      ENV.delete "DATADOG_APP_KEY"
      yield
    end
  ensure
    FileUtils.rm_f(".env")
  end

  def with_local_kennel
    old = File.read("Gemfile")
    local = old.sub!('"kennel"', "'kennel', path: '#{File.dirname(__dir__)}'") || raise(".sub! failed")
    example = "projects/example.rb"
    File.write("Gemfile", local)
    File.write(example, <<~RUBY)
      module Teams
        class MyTeam < Kennel::Models::Team
          defaults(
            mention: -> { "@slack-my-alerts" }
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
                name: -> { "My Kennel Test Monitor" }, # nice descriptive name that will show up in alerts
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
              Kennel::Models::Dashboard.new(
                self,
                title: -> { "My Kennel Test Dashboard" },
                kennel_id: -> { "another-dashboard" }, # make up a unique name
                description: -> { "Overview of bar" },
                template_variables: -> { ["environment"] },
                layout_type: -> { "ordered" },
                widgets: -> {
                  [
                    {
                      definition: {
                        title: "Graph name",
                        type: "timeseries",
                        requests: [
                          {
                            q: "sum:mystats.foobar{$environment}",
                            display_type: "area"
                          }
                        ]
                      }
                    }
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
    FileUtils.rm_f(example)
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
