# frozen_string_literal: true
module Kennel
  module Models
    class Team < Base
      settings :slack, :email, :tags, :renotify_interval, :kennel_id
      defaults(
        tags: -> { ["team:#{kennel_id.sub(/^teams_/, "")}"] },
        renotify_interval: -> { 0 }
      )

      def initialize(*)
        super
        invalid! "remove leading # from slack" if slack.to_s.start_with?("#")
      end

      def tracking_id
        kennel_id
      end
    end
  end
end
