# frozen_string_literal: true
module Kennel
  module TemplateVariables
    def self.included(base)
      base.settings :template_variables
      base.defaults(template_variables: -> { [] })
    end

    private

    def render_template_variables
      template_variables.map do |v|
        v.is_a?(String) ? { default: "*", prefix: v, name: v } : v
      end
    end
  end
end
