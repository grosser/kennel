# frozen_string_literal: true
#
module Kennel
  module Models
    class Dashboard < Base
      include TemplateVariables
      include OptionalValidations

      API_LIST_INCOMPLETE = true
      READONLY_ATTRIBUTES = (Base::READONLY_ATTRIBUTES + [:url, :notify_list, :modified_at, :is_read_only, :author_name, :author_handle]).freeze
      READONLY_WIDGET_ATTRIBUTES = [:id].freeze
      DEFINITION_DEFAULTS = { autoscale: true }.freeze
      DASH_DEFAULTS = { description: "", template_variables: [].freeze, layout_type: "ordered" }.freeze

      settings :id, :title, :description, :kennel_id, :widgets, :layout_type, :definitions

      defaults(
        id: -> { nil },
        description: -> { DASH_DEFAULTS.fetch(:description) },
        template_variables: -> { DASH_DEFAULTS.fetch(:template_variables) },
        widgets: -> { [] },
        layout_type: -> { DASH_DEFAULTS.fetch(:layout_type) },
        definitions: -> { [] }
      )

      attr_reader :project

      def initialize(project, *args)
        @project = project
        super(*args)
      end

      def self.api_resource
        "dashboard"
      end

      def as_json
        return @json if @json
        @json = {
          id: id,
          title: "#{title}#{LOCK}",
          description: description,
          template_variables: render_template_variables,
          widgets: render_widgets
        }

        validate_json(@json) if validate

        @json
      end

      def self.normalize(expected, actual)
        super

        actual[:template_variables] ||= [] # is nil when it never had template variables
        ignore_default expected, actual, DASH_DEFAULTS

        widgets = actual[:widgets] || []

        widgets.each { |g| g[:definition].delete(:status) }

        ignore_request_defaults expected, actual, :widgets, :definition

        widgets.each_with_index do |a_g, i|
          a_d = a_g[:definition]
          e_d = expected.dig(:widgets, i, :definition) || {}
          puts "IG #{e_d} -- #{a_d} -- #{DEFINITION_DEFAULTS}"
          ignore_default e_d, a_d, DEFINITION_DEFAULTS
        end
      end

      def url(id)
        Utils.path_to_url "/dashboard/#{id}"
      end

      private

      def validate_json(data)
        super

        # check for bad variables
        # TODO: do the same check for apm_query and their group_by
        variables = (data[:template_variables] || []).map { |v| "$#{v.fetch(:name)}" }
        queries = data[:widgets].flat_map { |g| (g[:definition][:requests] || []).map { |r| r[:q] }.compact }
        bad = queries.grep_v(/(#{variables.map { |v| Regexp.escape(v) }.join("|")})\b/)
        if bad.any?
          invalid! "queries #{bad.join(", ")} must use the template variables #{variables.join(", ")}"
        end

        # check for fields that are unsettable TODO: we might not need that anymore
        data[:widgets].each do |w|
          if w[:definition].key?(:status)
            invalid! "remove definition status, it is unsettable and will always produce a diff"
          end
        end
      end

      def render_template_variables
        (template_variables || []).map do |v|
          v.is_a?(String) ? { default: "*", prefix: v, name: v } : v
        end
      end

      def render_widgets
        definitions.map do |title, viz, type, queries, options = {}, ignored = nil|
          # validate inputs
          if ignored || (!title || !viz || !queries || !options.is_a?(Hash))
            raise ArgumentError, "Expected exactly 5 arguments for each definition (title, viz, type, queries, options)"
          end
          if options.each_key.any? { |k| !SUPPORTED_GRAPH_OPTIONS.include?(k) }
            raise ArgumentError, "Supported options are: #{SUPPORTED_GRAPH_OPTIONS.map(&:inspect).join(", ")}"
          end

          # build graph
          requests = Array(queries).map do |q|
            request = { q: q }
            request[:type] = type if type
            request
          end

          widget = { title: title, definition: { viz: viz, requests: requests } }

          # whitelist options that can be passed in, so we are flexible in the future
          SUPPORTED_GRAPH_OPTIONS.each do |key|
            widget[:definition][key] = options[key] if options[key]
          end

          # set default values so users do not have to pass them all the time
          if viz == "query_value"
            widget[:definition][:precision] ||= 2
          end

          widget
        end + widgets
      end
    end
  end
end
