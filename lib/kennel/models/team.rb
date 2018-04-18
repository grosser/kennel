# frozen_string_literal: true
module Kennel
  module Models
    class Team < Base
      # TODO: validate slack has no leading #
      settings :slack, :email, :tags
      defaults(
        tags: -> { ["team:#{kennel_id}"] }
      )
    end
  end
end
