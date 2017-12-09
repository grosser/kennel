# frozen_string_literal: true
module Kennel
  module Models
    class Team < Base
      # TODO: validate slack has no leading #
      settings :slack, :email
    end
  end
end
