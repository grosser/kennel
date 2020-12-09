![](template/github/cage.jpg?raw=true)

Manage Datadog Monitors / Dashboards / Slos as code

 - DRY, searchable, audited, documented
 - Changes are PR reviewed and applied on merge
 - Updating shows diff before applying
 - Automated import of existing resources
 - Resources are grouped into projects that belong to teams and inherit tags
 - No copy-pasting of ids to create new resources
 - Automated cleanup when removing code
 - [Helpers](#helpers) for automating common tasks
 
### Applying changes

![](template/github/screen.png?raw=true)

### Example code

```Ruby
# teams/foo.rb
module Teams
  class Foo < Kennel::Models::Team
    defaults(mention: -> { "@slack-my-team" })
  end
end

# projects/bar.rb
class Bar < Kennel::Models::Project
  defaults(
    team: -> { Teams::Foo.new }, # use mention and tags from the team
    parts: -> {
      [
        Kennel::Models::Monitor.new(
          self, # the current project
          type: -> { "query alert" },
          kennel_id: -> { "load-too-high" }, # pick a unique name
          name: -> { "Foobar Load too high" }, # nice descriptive name that will show up in alerts and emails
          message: -> {
            <<~TEXT
              This is bad!
              #{super()} # inserts mention from team
            TEXT
          },
          query: -> { "avg(last_5m):avg:system.load.5{hostgroup:api} by {pod} > #{critical}" },
          critical: -> { 20 }
        )
      ]
    }
  )
end
```

<!-- NOT IN template/Readme.md  -->
## Installation

 - create a new private `kennel` repo for your organization (do not fork this repo)
 - use the template folder as starting point:
    ```Bash
    git clone git@github.com:your-org/kennel.git
    git clone git@github.com:grosser/kennel.git seed
    mv seed/template/* kennel/
    cd kennel && git add . && git commit -m 'initial'
    ```
 - add a basic projects and teams so others can copy-paste to get started
 - setup CI build for your repo (travis and Github Actions supported)
 - uncomment `.travis.yml` section for datadog updates on merge (TODO: example setup for Github Actions)
 - follow `Setup` in your repos Readme.md
<!-- NOT IN -->

## Structure

 - `projects/` monitors/dashboards/etc scoped by project
 - `teams/` team definitions
 - `parts/` monitors/dashboards/etc that are used by multiple projects
 - `generated/` projects as json, to show current state and proposed changes in PRs

## Workflows

<!-- ONLY IN template/Readme.md
### Setup
 - clone the repo
 - `gem install bundler && bundle install`
 - `cp .env.example .env`
 - open [Datadog API Settings](https://app.datadoghq.com/account/settings#api)
 - create a `API Key` or get an existing one from an admin, then add it to `.env` as `DATADOG_API_KEY`
 - find or create (check last page) your personal "Application Key" and add it to `.env` as `DATADOG_APP_KEY=`
 - change the `DATADOG_SUBDOMAIN=app` in `.env` to your companies subdomain if you have one
 - verify it works by running `rake plan`, it might show some diff, but should not crash
-->

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
 - use [datadog monitor UI](https://app.datadoghq.com/monitors#create) to create a monitor
 - see below

### Updating an existing monitor
 - use [datadog monitor UI](https://app.datadoghq.com/monitors/manage) to find a monitor
 - get the `id` from the url
 - run `URL='https://app.datadoghq.com/monitors/123' bundle exec rake kennel:import` and copy the output
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
 - datadog is updated by CI

### Adding a new dashboard
 - go to [datadog dashboard UI](https://app.datadoghq.com/dashboard/lists) and click on _New Dashboard_ to create a dashboard
 - see below

### Updating an existing dashboard
 - go to [datadog dashboard UI](https://app.datadoghq.com/dashboard/lists) and click on _New Dashboard_ to find a dashboard
 - get the `id` from the url
 - run `URL='https://app.datadoghq.com/dashboard/bet-foo-bar' bundle exec rake kennel:import` and copy the output
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

### Updating existing resources with id

Setting `id` makes kennel take over a manually created datadog resource.
When manually creating to import, it is best to remove the `id` and delete the manually created resource.

When an `id` is set and the original resource is deleted, kennel will fail to update,
removing the `id` will cause kennel to create a new resource in datadog.


### Skipping validations

Some validations might be too strict for your usecase or just wrong, please [open an issue](https://github.com/grosser/kennel/issues) and
to unblock use the `validate: -> { false }` option.

### Linking with kennel_ids

To link to existing monitors via their kennel_id `projects kennel_id` + `:` + `monitors kennel id`

 - Screens `uptime` widgets can use `monitor: {id: "foo:bar"}`
 - Screens `alert_graph` widgets can use `alert_id: "foo:bar"`
 - Monitors `composite` can use `query: -> { "%{foo:bar} || %{foo:baz}" }`
 - Slos can use `monitor_ids: -> ["foo:bar"]` 

### Debugging changes locally

 - rebase on updated `master` to not undo other changes
 - figure out project name by converting the class name to snake-case
 - run `PROJECT=foo bundle exec rake kennel:update_datadog` to test changes for a single project (monitors: remove mentions while debugging to avoid alert spam)

### Reuse

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

## Helpers

### Listing un-muted alerts

Run `rake kennel:alerts TAG=service:my-service` to see all un-muted alerts for a given datadog monitor tag.

### Validating mentions work

`rake kennel:validate_mentions` should run as part of CI

### Grepping through all of datadog

`rake kennel:dump`
focus on a single type: `TYPE=monitors`

### Find all monitors with No-Data

`rake kennel:nodata TAG=team:foo`

<!-- NOT IN template/Readme.md -->


## Development

### Integration testing

```Bash
rake play
cd template
rake plan
```

Then make changes to play around, do not commit changes and make sure to revert with a `rake kennel:update_datadog` after deleting everything.

To make changes via the UI, make a new free datadog account and use it's credentaisl instead.

Author
======
[Michael Grosser](http://grosser.it)<br/>
michael@grosser.it<br/>
License: MIT<br/>
[![Build Status](https://travis-ci.org/grosser/kennel.png)](https://travis-ci.org/grosser/kennel)
<!-- NOT IN -->
