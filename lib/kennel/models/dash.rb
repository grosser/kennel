# frozen_string_literal: true
#
# TODO: delete
module Kennel
  module Models
    class Dash < Dashboard
      READONLY_ATTRIBUTES = (Base::READONLY_ATTRIBUTES + [:resource, :created_by, :read_only, :new_id]).freeze
      settings :graphs

      defaults(
        graphs: -> { [] }
      )
    end
  end
end
