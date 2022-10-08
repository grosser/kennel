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

## About the models

Kennel provides several classes which act as models for different purposes:

* `Kennel::Models::Dashboard`, `Kennel::Models::Monitor`, `Kennel::Models::Slo`, `Kennel::Models::SyntheticTest`;
  these models represent the various Datadog objects
* `Kennel::Models::Project`; a container for a collection of Datadog objects
* `Kennel::Models::Team`; provides defaults and values (e.g. tags, mentions) for the other models.

After loading all the `*.rb` files under `projects/`, Kennel's starting point
is to find all the subclasses of `Kennel::Models::Project`, and for each one,
create an instance of that subclass (via `.new`) and then call `#parts` on that
instance. `parts` should return a collection of the Datadog-objects (Dashboard / Monitor / etc).

### Model Settings

Each of the models defines various settings; for example, a Monitor has `name`, `message`,
`type`, `query`, `tags`, and many more.

When defining a subclass of a model, one can use `defaults` to provide default values for
those settings:

```Ruby
class MyMonitor < Kennel::Models::Monitor
  defaults(
    name: "Error rate",
    type: "query alert",
    critical: 5.0,
    query: -> {
      "some datadog metric expression > #{critical}"
    },
    # ...
  )
end
```

This is equivalent to defining instance methods of those names, which return those values:

```Ruby
class MyMonitor < Kennel::Models::Monitor
  def name
    "Error rate"
  end

  def type
    "query alert"
  end

  def critical
    5.0
  end

  def query
    "some datadog metric expression > #{critical}"
  end
end
```

except that `defaults` will complain if you try to use a setting name which doesn't
exist. Note also that you can use either plain values (`critical: 5.0`), or procs
(`query: -> { ... }`). Using a plain value is equivalent to using a proc which returns
that same value; use whichever suits you best.

When you _instantiate_ a model class, you can pass settings in the constructor, after
the project:

```Ruby
project = Kennel::Models::Project.new
my_monitor = MyMonitor.new(
  project,
  critical: 10.0,
  message: -> {
    <<~MESSAGE
      Something bad is happening and you should be worried.

      #{super()}
    MESSAGE
  },
)
```

This works just like `defaults` (it checks the setting names, and it accepts
either plain values or procs), but it applies just to this instance of the class,
rather than to the class as a whole (i.e. it defines singleton methods, rather
than instance methods).

Most of the examples in this Readme use the proc syntax (`critical: -> { 5.0 }`) but
for simple constants you may prefer to use the plain syntax (`critical: 5.0`).

## Workflows
<!-- ONLY IN template/Readme.md

### Setup
 - clone the repo
 - `gem install bundler && bundle install`
 - `cp .env.example .env`
 - open [Datadog API Settings](https://app.datadoghq.com/account/settings#api)
 - create a `API Key` or get an existing one from an admin, then add it to `.env` as `DATADOG_API_KEY`
 - open [Datadog API Settings](https://app.datadoghq.com/access/application-keys) and create a new key, then add it to `.env` as `DATADOG_APP_KEY=`
 - if you have a custom subdomain, change the `DATADOG_SUBDOMAIN=app` in `.env`
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
 - import task also works with SLO alerts, e.g. `URL='https://app.datadoghq.com/slo/edit/123abc456def123/alerts/789' bundle exec rake kennel:import`
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

### Deleting

Remove the code that created the resource. The next update will delete it (see above for PR workflow).

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

### Organizing projects with many resources
When project files get too long, this structure can keep things bite-sized.

```Ruby
# projects/project_a/base.rb
module ProjectA
  class Base < Kennel::Models::Project
    defaults(
      kennel_id: -> { "project_a" },
      parts: -> {
        [
          Monitors::FooAlert.new(self),
          ...
        ]
      }
      ...

# projects/project_a/monitors/foo_alert.rb
module ProjectA
  module Monitors
    class FooAlert < Kennel::Models::Monitor
      ...
```

### Updating a single project or resource

- Use `PROJECT=<kennel_id>` for single project:

  Use the projects `kennel_id` (and if none is set then snake_case of the class name including modules)
  to refer to the project. For example for `class ProjectA` use `PROJECT=project_a` but for `Foo::ProjectA` use `foo_project_a`.

- Use `TRACKING_ID=<project-kennel_id>:<resource-kennel_id>` for single resource:

  Use the project kennel_id and the resources kennel_id, for example `class ProjectA` and `FooAlert` would give `project_a:foo_alert`.

### Skipping validations
Some validations might be too strict for your usecase or just wrong, please [open an issue](https://github.com/grosser/kennel/issues) and
to unblock use the `validate: -> { false }` option.

### Linking resources with kennel_id
Link resources with their kennel_id in the format `project kennel_id` + `:` + `resource kennel_id`,
this should be used to create dependent resources like monitor + slos,
so they can be created in a single update and can be re-created if any of them is deleted.

|Resource|Type|Syntax|
|---|---|---|
|Dashboard|uptime|`monitor: {id: "foo:bar"}`|
|Dashboard|alert_graph|`alert_id: "foo:bar"`|
|Dashboard|slo|`slo_id: "foo:bar"`|
|Monitor|composite|`query: -> { "%{foo:bar} && %{foo:baz}" }`|
|Monitor|slo alert|`query: -> { "error_budget(\"%{foo:bar}\").over(\"7d\") > 123.0" }`|
|Slo|monitor|`monitor_ids: -> ["foo:bar"]`|

### Debugging changes locally
 - rebase on updated `master` to not undo other changes
 - figure out project name by converting the class name to snake_case
 - run `PROJECT=foo bundle exec rake kennel:update_datadog` to test changes for a single project (monitors: remove mentions while debugging to avoid alert spam)
   - use `PROJECT=foo,bar,...` for multiple projects

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
```Bash
rake kennel:dump > tmp/dump
cat tmp/dump | grep foo
```
focus on a single type: `TYPE=monitors`

Show full resources or just their urls by pattern:
```Bash
rake kennel:dump_grep DUMP=tmp/dump PATTERN=foo URLS=true
https://foo.datadog.com/dasboard/123
https://foo.datadog.com/monitor/123
```

### Find all monitors with No-Data
`rake kennel:nodata TAG=team:foo`

### Finding the tracking id of a resource

When trying to link resources together, this avoids having to go through datadog UI.

```Bash
rake kennel:tracking_id ID=123 RESOURCE=monitor
```

<!-- NOT IN template/Readme.md -->

## Development

### Benchmarking
- Setting `FORCE_GET_CACHE=true` will cache all get requests, which makes benchmarking improvements more reliable.
- Setting `STORE=false` will make `rake plan` not update the files on disk and save a bit of time

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
![CI](https://github.com/grosser/kennel/workflows/CI/badge.svg)
<!-- NOT IN -->
