# frozen_string_literal: true
module Kennel
  module Models
    class Dash < Base
      include TemplateVariables
      include OptionalValidations

      API_LIST_INCOMPLETE = true
      SUPPORTED_GRAPH_OPTIONS = [:events, :markers, :precision].freeze
      READONLY_ATTRIBUTES = (Base::READONLY_ATTRIBUTES + [:resource, :created_by, :read_only, :new_id]).freeze
      DEFINITION_DEFAULTS = { autoscale: true }.freeze
      DASH_DEFAULTS = { template_variables: [] }.freeze

      settings :id, :title, :description, :graphs, :kennel_id, :definitions

      defaults(
        id: -> { nil },
        description: -> { "" },
        definitions: -> { [] },
        graphs: -> { [] },
        template_variables: -> { [] }
      )

      attr_reader :project

      def initialize(project, *args)
        @project = project
        super(*args)
      end

      def self.api_resource
        "dash"
      end

      def as_json
        return @json if @json
        @json = {
          id: id,
          title: "#{title}#{LOCK}",
          description: description,
          template_variables: render_template_variables,
          graphs: render_graphs
        }

        validate_json(@json) if validate

        @json
      end

      def self.normalize(expected, actual)
        super

        actual[:template_variables] ||= [] # is nil when it never had template variables
        ignore_default expected, actual, DASH_DEFAULTS

        graphs = actual[:graphs] || []

        graphs.each { |g| g[:definition].delete(:status) }

        ignore_request_defaults expected, actual, :graphs, :definition

        graphs.each_with_index do |a_g, i|
          a_d = a_g[:definition]
          e_d = expected.dig(:graphs, i, :definition) || {}
          ignore_default e_d, a_d, DEFINITION_DEFAULTS
        end
      end

      def url(id)
        Utils.path_to_url "/dash/#{id}"
      end

      private

      def validate_json(data)
        super

        # check for bad variables
        # TODO: do the same check for apm_query and their group_by
        variables = (data[:template_variables] || []).map { |v| "$#{v.fetch(:name)}" }
        queries = data[:graphs].flat_map { |g| (g[:definition][:requests] || []).map { |r| r[:q] }.compact }
        bad = queries.grep_v(/(#{variables.map { |v| Regexp.escape(v) }.join("|")})\b/)
        if bad.any?
          invalid! "queries #{bad.join(", ")} must use the template variables #{variables.join(", ")}"
        end

        # check for fields that are unsettable
        data[:graphs].each do |g|
          if g[:definition].key?(:status)
            invalid! "remove definition status, it is unsettable and will always produce a diff"
          end
        end
      end

      def render_template_variables
        (template_variables || []).map do |v|
          v.is_a?(String) ? { default: "*", prefix: v, name: v } : v
        end
      end

      def render_graphs
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

          graph = { title: title, definition: { viz: viz, requests: requests } }

          # whitelist options that can be passed in, so we are flexible in the future
          SUPPORTED_GRAPH_OPTIONS.each do |key|
            graph[:definition][key] = options[key] if options[key]
          end

          # set default values so users do not have to pass them all the time
          if viz == "query_value"
            graph[:definition][:precision] ||= 2
          end

          graph
        end + graphs
      end
    end
  end
end
