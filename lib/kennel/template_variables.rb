# frozen_string_literal: true
module Kennel
  module TemplateVariables
    def self.included(base)
      base.settings :template_variables
      base.defaults(template_variables: -> { [] })
    end

    private

    def render_template_variables
      (template_variables || []).map do |v|
        v.is_a?(String) ? { default: "*", prefix: v, name: v } : v
      end
    end

    # check for queries that do not use the variables and would be misleading
    # TODO: do the same check for apm_query and their group_by
    def validate_template_variables(data, key)
      variables = (data[:template_variables] || []).map { |v| "$#{v.fetch(:name)}" }
      queries = data[key].flat_map do |g|
        requests =
          (g.dig(:definition, :requests) || []) +
          (g.dig(:definition, :widgets) || []).flat_map { |w| w.dig(:definition, :requests) || [] }
        requests.map { |r| r[:q] }
      end.compact
      bad = queries.grep_v(/(#{variables.map { |v| Regexp.escape(v) }.join("|")})\b/)
      if bad.any?
        invalid! "queries #{bad.join(", ")} must use the template variables #{variables.join(", ")}"
      end
    end
  end
end
