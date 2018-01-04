# frozen_string_literal: true
module Kennel
  module OptionalValidations
    def self.included(base)
      base.settings :validate
      base.defaults(validate: -> { true })
    end
  end
end
