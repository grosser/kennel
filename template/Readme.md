# Kennel

![](github/cage.jpg?raw=true)

Keep datadog monitors/dashboards/etc in version control, avoid chaotic management via UI.

 - Documented, reusable, automated, and searchable configuration
 - Changes are PR reviewed and auditable
 - Good defaults like no-data / re-notify are preselected
 - Reliable cleanup with automated deletion

![](github/screen.png?raw=true)

## Structure

 - `projects/` monitors/dashboards/etc scoped by project
 - `teams/` team definitions
 - `parts/` monitors/dashes/etc that are used by multiple projects
 - `generated/` projects as json, to show current state and proposed changes in PRs

## Workflows

### Setup
 - clone the repo
 - `gem install bundler && bundle install`
 - `cp .env.example .env`
 - open [Datadog API Settings](https://app.datadoghq.com/account/settings#api)
 - copy any `API Key` and add it to `.env` as `DATADOG_API_KEY`
 - find or create (check last page) your personal "Application Key" and add it to `.env` as `DATADOG_APP_KEY=`
 - change the `DATADOG_SUBDOMAIN=app` in `.env` to your companies subdomain if you have one

### Adding a team

 - `mention` is used for all team monitors via `super()`
 - `renotify_interval` is used for all team monitors (defaults to `0` / off)
 - `tags` is used for all team monitors/dashboards (defaults to `team:<team-name>`)

```Ruby
# teams/my_team.rb
module Teams
  class MyTeam < Kennel::Models::Team
    defaults(
      mention: -> { "@slack-my-team" }
    )
  end
end
```

### Adding a new monitor
 - use [datadog monitor UI](https://app.datadoghq.com/monitors#create/metric) to create a monitor
 - see below

### Updating an existing monitor
 - use [datadog monitor UI](https://app.datadoghq.com/monitors#create/metric) to find a monitor
 - get the `id` from the url
 - run `RESOURCE=monitor ID=12345 bundle exec rake kennel:import` and copy the output
 - find or create a project in `projects/`
 - add the monitor to `parts: [` list, for example:
  ```Ruby
  # projects/my_project.rb
  class MyProject < Kennel::Models::Project
    defaults(
      team: -> { Teams::MyTeam.new }, # use existing team or create new one in teams/
      parts: -> {
        [
          Kennel::Models::Monitor.new(
            self,
            id: -> { 123456 }, # id from datadog url, not necessary when creating a new monitor
            type: -> { "query alert" },
            kennel_id: -> { "load-too-high" }, # make up a unique name
            name: -> { "Foobar Load too high" }, # nice descriptive name that will show up in alerts and emails
            message: -> {
              # Explain what behavior to expect and how to fix the cause
              # Use #{super()} to add team notifications.
              <<~TEXT
                Foobar will be slow and that could cause Barfoo to go down.
                Add capacity or debug why it is suddenly slow.
                #{super()}
              TEXT
            },
            query: -> { "avg(last_5m):avg:system.load.5{hostgroup:api} by {pod} > #{critical}" }, # replace actual value with #{critical} to keep them in sync
            critical: -> { 20 }
          )
        ]
      }
    )
  end
  ```
 - run `PROJECT=my_project bundle exec rake plan`, an Update to the existing monitor should be shown (not Create / Delete)
 - alternatively: `bundle exec rake generate` to only locally update the generated `json` files
 - review changes then `git commit`
 - make a PR ... get reviewed ... merge
 - datadog is updated by travis

### Adding a new dashboard
 - go to [datadog dashboard UI](https://app.datadoghq.com/dashboard/lists) and click on _New Dashboard_ to create a dashboard
 - see below

### Updating an existing dashboard
 - go to [datadog dashboard UI](https://app.datadoghq.com/dashboard/lists) and click on _New Dashboard_ to find a dashboard
 - get the `id` from the url
 - run `RESOURCE=dashboard ID=abc-def-ghi bundle exec rake kennel:import` and copy the output
 - find or create a project in `projects/`
 - add a dashboard to `parts: [` list, for example:
  ```Ruby
  class MyProject < Kennel::Models::Project
    defaults(
      team: -> { Teams::MyTeam.new }, # use existing team or create new one in teams/
      parts: -> {
        [
          Kennel::Models::Dashboard.new(
            self,
            id: -> { "abc-def-ghi" }, # id from datadog url, not needed when creating a new dashboard
            title: -> { "My Dashboard" },
            description: -> { "Overview of foobar" },
            template_variables: -> { ["environment"] }, # see https://docs.datadoghq.com/api/?lang=ruby#timeboards
            kennel_id: -> { "overview-dashboard" }, # make up a unique name
            layout_type: -> { "ordered" },
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
          )
        ]
      }
    )
  end
 ```

### Skipping validations

Some validations might be too strict for your usecase or just wrong, please [open an issue](https://github.com/grosser/kennel/issues) and
to unblock use the `validate: -> { false }` option.

### Linking with kennel_ids

To link to existing monitors via their kennel_id

 - Screens `uptime` widgets can use `monitor: {id: "foo:bar"}`
 - Screens `alert_graph` widgets can use `alert_id: "foo:bar"`
 - Monitors `composite` can use `query: -> { "%{foo:bar} || %{foo:baz}" }`

### Debugging changes locally

 - rebase on updated `master` to not undo other changes
 - figure out project name by converting the class name to snake-case
 - run `PROJECT=foo bundle exec rake kennel:update_datadog` to test changes for a single project

### Listing un-muted alerts

Run `rake kennel:alerts TAG=service:my-service` to see all un-muted alerts for a given datadog monitor tag.

## Examples

### Reusable monitors/dashes/etc

Add to `parts/<folder>`.

```Ruby
module Monitors
  class LoadTooHigh < Kennel::Models::Monitor
    defaults(
      name: -> { "#{project.name} load too high" },
      message: -> { "Shut it down!" },
      type: -> { "query alert" },
      query: -> { "avg(last_5m):avg:system.load.5{hostgroup:#{project.kennel_id}} by {pod} > #{critical}" }
    )
  end
end
```

Reuse it in multiple projects.

```Ruby
class Database < Kennel::Models::Project
  defaults(
    team: -> { Kennel::Models::Team.new(mention: -> { '@slack-foo' }, kennel_id: -> { 'foo' }) },
    parts: -> { [Monitors::LoadTooHigh.new(self, critical: -> { 13 })] }
  )
end
```
