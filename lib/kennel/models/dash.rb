# frozen_string_literal: true
module Kennel
  module Models
    class Dash < Base
      include TemplateVariables
      include OptionalValidations

      API_LIST_INCOMPLETE = true
      SUPPORTED_GRAPH_OPTIONS = [:events, :markers].freeze
      settings :id, :title, :description, :graphs, :kennel_id, :graphs, :definitions

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
          read_only: false,
          template_variables: render_template_variables,
          graphs: render_graphs
        }

        validate_json(@json) if validate

        @json
      end

      def diff(actual)
        actual.delete :resource
        actual.delete :created_by
        actual[:template_variables] ||= []
        actual[:graphs].each do |g|
          g[:definition].delete(:status)
        end
        ignore_request_defaults as_json, actual, :graphs, :definition
        super
      end

      def url(id)
        Utils.path_to_url "/dash/#{id}"
      end

      private

      def validate_json(data)
        # check for bad variables
        # TODO: do the same check for apm_query and their group_by
        variables = data.fetch(:template_variables).map { |v| "$#{v.fetch(:name)}" }
        queries = data[:graphs].flat_map { |g| g[:definition][:requests].map { |r| r[:q] }.compact }
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
        template_variables.map do |v|
          v.is_a?(String) ? { default: "*", prefix: v, name: v } : v
        end
      end

      def render_graphs
        all = definitions.map do |title, viz, type, queries, options = {}, ignored = nil|
          if ignored || (!title || !viz || !type || !queries || !options.is_a?(Hash))
            raise ArgumentError, "Expected exactly 5 arguments for each definition (title, viz, type, queries, options)"
          end
          if options.each_key.any? { |k| !SUPPORTED_GRAPH_OPTIONS.include?(k) }
            raise ArgumentError, "Supported options are: #{SUPPORTED_GRAPH_OPTIONS.map(&:inspect).join(", ")}"
          end

          requests = Array(queries).map { |q| { q: q, type: type } }
          graph = { title: title, definition: { viz: viz, requests: requests } }
          SUPPORTED_GRAPH_OPTIONS.each do |key|
            graph[:definition][key] = options[key] if options[key]
          end
          graph
        end + graphs

        all.each do |g|
          g[:definition][:autoscale] = true unless g[:definition].key?(:autoscale)
        end
      end
    end
  end
end
