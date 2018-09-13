# frozen_string_literal: true
module Kennel
  module Models
    class Team < Base
      settings :slack, :email, :tags, :kennel_id
      defaults(
        tags: -> { ["team:#{kennel_id.sub(/^teams_/, "")}"] }
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
