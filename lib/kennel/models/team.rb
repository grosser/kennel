# frozen_string_literal: true
module Kennel
  module Models
    class Team
      include SettingsAsMethods

      settings :mention, :tags, :renotify_interval
      defaults(
        tags: -> { ["team:#{StringUtils.snake_case(self.class.name).sub(/^teams_/, "").tr("_", "-")}"] },
        renotify_interval: -> { 0 }
      )
    end
  end
end
