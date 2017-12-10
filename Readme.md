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
 - `git grep yourcompany` and change all of them
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
 - go to [Datadog API Settings](https://yourcompany.datadoghq.com/account/settings#api)
 - find or create your personal "Application Key" and add it to `.env` as `DATADOG_APP_KEY=` (will be on the last page if new)
 - copy the `yourcompany` `API Key` and add it to `.env` as `DATADOG_API_KEY`

### Adding a new monitor
 - use [datadog monitor UI](https://yourcompany.datadoghq.com/monitors#create/metric) to create a monitor
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
            type: -> { "metric alert" },
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
 - review changes then `git commit`
 - make a PR ... get reviewed ... merge
 - datadog is updated by travis

### Adding a new dashboard
 - structure is similar to monitors, so `lib/kennel/models/dash.rb`
 - add to `parts:` list
 ```Ruby
  Kennel::Models::Dash.new(
    kennel_id: -> { "kube-app" },
    template_variables: -> { ["environment"] },
    title: -> { project.name },
    definitions: -> {
      kube_project = project.kennel_id.tr("_", "-")
      [
        [
          "Instance count", "timeseries", "area",
          "sum:kube_stats.pods{phase:ready,kube_project:#{kube_project},$environment} by {pod}"
        ],
        [
          "Memory", "timeseries", "area",
          "sum:docker.mem.rss{kube_project:#{kube_project},$environment} by {pod}"
        ],
        [
          "Swap", "timeseries", "area",
          "sum:docker.mem.swap{kube_project:#{kube_project},$environment} by {pod}"
        ],
        [
          "CPU", "timeseries", "area",
          "sum:docker.cpu.user{kube_project:#{kube_project},$environment} by {pod}"
        ]
      ]
    }
  )
 ```

### Adding a new screenboard
 - needs to be implemented, is be similar to `dash.rb`
 - add to `parts:` list
 ```Ruby
 Kennel::Models::Screen.new(
   self,
   board_title: -> { "test-board" },
   widgets: -> { [{text: "Hello World", height: 6, width: 24, x: 0, y: 0, type: "free_text"}] }
 )
 ```

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
