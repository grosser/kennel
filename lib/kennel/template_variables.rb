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
    def validate_json(data)
      super

      variables = (data[:template_variables] || []).map { |v| "$#{v.fetch(:name)}" }
      return if variables.empty?

      queries = data[:widgets].flat_map do |widget|
        ([widget] + (widget.dig(:definition, :widgets) || [])).flat_map { |w| widget_queries(w) }
      end.compact

      matches = variables.map { |v| Regexp.new "#{Regexp.escape(v)}\\b" }
      queries.reject! { |q| matches.all? { |m| q.match? m } }
      return if queries.empty?

      invalid!(
        :queries_must_use_template_variables,
        "queries #{queries.join(", ")} must use the template variables #{variables.join(", ")}"
      )
    end

    def widget_queries(widget)
      requests = widget.dig(:definition, :requests) || []
      return hostmap_queries(requests) if requests.is_a?(Hash) # hostmap widgets have hash requests
      requests.flat_map { |r| r[:q] || r[:queries]&.map { |q| q[:query] } } # old format with q: or queries: [{query:}]
    end

    # hostmap requests nest queries at varying depth, for example
    # { fill: { q: "..." } } or { fill: { queries: [{ search: { query: "..." } }] }, request_type: "hosts" }
    def hostmap_queries(node)
      case node
      when Hash
        query = node[:q] || node[:query]
        [*query, *hostmap_queries(node.except(:q, :query).values)]
      when Array
        node.flat_map { |v| hostmap_queries(v) }
      else
        [] # scalar leaves like request_type: "hosts"
      end
    end
  end
end
