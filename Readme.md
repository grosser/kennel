# Kennel

![](template/github/cage.jpg?raw=true)

Keep datadog monitors/dashboards/etc in version control, avoid chaotic management via UI.

 - Documented, reusable, automated, and searchable configuration
 - Changes are PR reviewed and auditable
 - Good defaults like no-data / re-notify are preselected
 - Reliable cleanup with automated deletion

![](template/github/screen.png?raw=true)

<!-- CUT only make changes to template/Readme.md -->
## Install

 - create a new private `kennel` repo for your organization, clone this repo, push the contents of the `template` folder into the private repo
 - uncomment `.travis.yml` section for automated github PR feedback and datadog updates on merge
 - setup travis build for the repo
 - add a basic projects and teams so others can copy-paste to get started
<!-- CUT -->

## Structure

 - `projects/` monitors/dashboards/etc scoped by project
 - `teams/` team definitions
 - `parts/` monitors/dashes/etc that are used by multiple projects
 - `generated/` projects as json, to show current state and proposed changes in PRs

## Workflows

### Setup
 - clone the repo
 - `gem install bundler && bundle install`
 - go to [Datadog API Settings](https://app.datadoghq.com/account/settings#api)
 - find or create your personal "Application Key" and add it to `.env` as `DATADOG_APP_KEY=` (will be on the last page if new)
 - copy any `API Key` and add it to `.env` as `DATADOG_API_KEY`

### Adding a new monitor
 - use [datadog monitor UI](https://app.datadoghq.com/monitors#create/metric) to create a monitor
 - get the `id` from the url, click "Export Monitor" on the monitors edit tab to get the `query` and `type`
 - see below

### Updating an existing monitor
 - find or create a project in `projects/`
 - add a monitor to `parts: [` list
  ```Ruby
  class MyProject < Kennel::Models::Project
    defaults(
      team: -> { Teams::MyTeam.new }, # use existing team or create new one in teams/
      parts: -> {
        [
          Kennel::Models::Monitor.new(
            self,
            id: -> { 123456 }, # id from datadog url
            type: -> { "query alert" },
            kennel_id: -> { "load-too-high" }, # make up a unique name
            name: -> { "Foobar Load too high" }, # nice descriptive name that will show up in alerts and emails
            message: -> {
              # Explain what behavior to expect and how to fix the cause. Use #{super()} to add team notifications.
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
 - `bundle exec rake plan` update to existing should be shown (not Create / Delete)
 - alternatively: `bundle exec rake generate` to only update the generated `json` files
 - review changes then `git commit`
 - make a PR ... get reviewed ... merge
 - datadog is updated by travis

### Adding a new dashboard
 - go to [datadog dashboard UI](https://app.datadoghq.com/dash/list) and click on _New Dashboard_ to create a dashboard
 - get the `id` from the url
 - see below

### Updating an existing dashboard
 - find or create a project in `projects/`
 - add a dashboard to `parts: [` list
  ```Ruby
  class MyProject < Kennel::Models::Project
    defaults(
      team: -> { Teams::MyTeam.new }, # use existing team or create new one in teams/
      parts: -> {
        [
          Kennel::Models::Dash.new(
            self,
            id: -> { 123457 }, # id from datadog url
            title: -> { "My Dashboard" },
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
                  "Graph name", "timeseries", "area", ["sum:mystats.foobar{$environment}", "sum:mystats.success{$environment}"]
                ]
              ]
            }
          )
        ]
      }
    )
  end
 ```

### Adding a new screenboard
 - similar to `dash.rb`
 - add to `parts:` list
 ```Ruby
 Kennel::Models::Screen.new(
   self,
   board_title: -> { "test-board" },
   widgets: -> { [{text: "Hello World", height: 6, width: 24, x: 0, y: 0, type: "free_text"}] }
 )
 ```

### Skipping validations

Some validations might be too strict for your usecase or just wrong, please open an issue and
to unblock use the `validate: -> { false }` option.

### Debugging locally

 - make sure to be on update `master` to not undo other changes
 - run `bundle exec rake kennel:update_datadog`

## Examples

### Reusable monitors/dashes/etc

Add to `parts/<folder>`.

```Ruby
module Monitors
  class LoadTooHigh < Kennel::Models::Monitor
    defaults(
      name: -> { "#{project.name} load too high" },
      message: -> { "Shut it down!" },
      query: -> { "avg(last_5m):avg:system.load.5{hostgroup:#{project.kennel_id}} by {pod} > #{critical}" }
    )
  end
end
```

Reuse it in multiple projects.

```Ruby
class Database < Kennel::Models::Project
  defaults(
    team: -> { Kennel::Models::Team.new(slack: -> { 'foo' }) },
    parts: -> { [Monitors::LoadTooHigh.new(self, critical: -> { 13 })] }
  )
end
```
<!-- CUT only make changes to template/Readme.md -->

Author
======
[Michael Grosser](http://grosser.it)<br/>
michael@grosser.it<br/>
License: MIT<br/>
[![Build Status](https://travis-ci.org/grosser/kennel.png)](https://travis-ci.org/grosser/kennel)
<!-- CUT -->
