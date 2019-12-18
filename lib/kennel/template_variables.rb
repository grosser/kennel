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
      queries = data[key].flat_map do |widget|
        ([widget] + (widget.dig(:definition, :widgets) || [])).flat_map { |w| widget_queries(w) }
      end.compact
      bad = queries.grep_v(/(#{variables.map { |v| Regexp.escape(v) }.join("|")})\b/)
      if bad.any?
        invalid!(
          "queries #{bad.join(", ")} must use the template variables #{variables.join(", ")}\n" \
          "If that is not possible, add `validate_template_variables: -> { false } # query foo in bar does not have baz tag`"
        )
      end
    end

    def widget_queries(widget)
      requests = widget.dig(:definition, :requests) || []
      (requests.is_a?(Hash) ? requests.values : requests).map { |r| r[:q] } # hostmap widgets have hash requests
    end
  end
end
