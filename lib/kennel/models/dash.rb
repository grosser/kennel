# frozen_string_literal: true
module Kennel
  module Models
    class Dash < Base
      include TemplateVariables
      include OptionalValidations

      API_LIST_INCOMPLETE = true
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
          g[:definition][:requests].each { |r| r.delete(:aggregator) }
        end
        super
      end

      def url(id)
        Utils.path_to_url "/dash/#{id}"
      end

      private

      def validate_json(data)
        variables = data.fetch(:template_variables).map { |v| "$#{v.fetch(:name)}" }
        queries = data[:graphs].flat_map { |g| g[:definition][:requests].map { |r| r.fetch(:q) } }
        bad = queries.grep_v(/(#{variables.map { |v| Regexp.escape(v) }.join("|")})\b/)
        if bad.any?
          raise "#{tracking_id} queries #{bad.join(", ")} must use the template variables #{variables.join(", ")}"
        end
      end

      def render_template_variables
        template_variables.map do |v|
          v.is_a?(String) ? { default: "*", prefix: v, name: v } : v
        end
      end

      def render_graphs
        all = definitions.map do |title, viz, type, queries, ignored|
          if ignored || (!title || !viz || !type || !queries)
            raise ArgumentError, "Expected exactly 4 arguments for each definition (title, viz, type, queries)"
          end

          requests = Array(queries).map { |q| { q: q, type: type } }
          { title: title, definition: { viz: viz, requests: requests } }
        end + graphs

        all.each do |g|
          g[:definition][:requests].each { |r| r[:conditional_formats] ||= [] }
          g[:definition][:autoscale] = true unless g[:definition].key?(:autoscale)
        end
      end
    end
  end
end
