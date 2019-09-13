# frozen_string_literal: true
module Kennel
  module Models
    class Team < Base
      settings :mention, :tags, :renotify_interval, :kennel_id
      defaults(
        tags: -> { ["team:#{kennel_id.sub(/^teams_/, "")}"] },
        renotify_interval: -> { 0 }
      )
    end
  end
end
