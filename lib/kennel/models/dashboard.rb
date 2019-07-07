# frozen_string_literal: true
module Kennel
  module Models
    class Dashboard < Base
      include TemplateVariables
      include OptionalValidations

      API_LIST_INCOMPLETE = true
      DASHBOARD_DEFAULTS = { template_variables: [] }.freeze
      DEFINITION_DEFAULTS = {
        # general
        title_align: "left",
        title_size: "16",

        # free text
        color: "#4d4d4d",
        text_align: "left",

        # note
        show_tick: false,
        tick_pos: "50%",
        tick_edge: "left",
        background_color: "white"
      }.freeze
      READONLY_ATTRIBUTES = Base::READONLY_ATTRIBUTES + [
        :author_handle, :author_name, :modified_at, :url, :is_read_only, :notify_list
      ]
      REQUEST_DEFAULTS = {
        style: { line_width: "normal", palette: "dog_classic", line_type: "solid" }
      }.freeze
      SUPPORTED_DEFINITION_OPTIONS = [:events, :markers, :precision].freeze

      settings :id, :title, :description, :definitions, :widgets, :kennel_id, :layout_type

      defaults(
        description: -> { "" },
        definitions: -> { [] },
        widgets: -> { [] },
        id: -> { nil }
      )

      class << self
        def api_resource
          "dashboard"
        end

        def normalize(expected, actual)
          super

          ignore_default expected, actual, DASHBOARD_DEFAULTS

          base_pairs(expected, actual).each do |pair|
            if pair.all? { |d| d[:widgets] }
              max = pair.map { |d| d[:widgets].size }.max
              max.times do |i|
                ignore_default *pair.map { |d| d.dig(:widgets, i, :definition) || {} }, DEFINITION_DEFAULTS
              end
            end

            ignore_request_defaults(*pair, :widgets, :definition)
            pair.each { |dash| dash[:widgets]&.each { |w| w.delete(:id) } }
          end
        end

        private

        # expand nested widgets into expected/actual pairs for default resolution
        # [a, e] -> [[a, e], [aw1, ew1], ...]
        def base_pairs(*pair)
          result = [pair]
          slots = pair.map { |d| d[:widgets]&.size }.compact.max.to_i
          slots.times do |i|
            nested = pair.map { |d| d.dig(:widgets, i, :definition) || {} }
            result << nested if nested.any? { |d| d.key?(:widgets) }
          end
          result
        end
      end

      attr_reader :project

      def initialize(project, *args)
        @project = project
        super(*args)
      end

      def as_json
        return @json if @json
        @json = {
          layout_type: layout_type,
          title: "#{title}#{LOCK}",
          description: description,
          template_variables: render_template_variables,
          widgets: render_definitions + widgets
        }

        @json[:id] = id if id

        validate_json(@json) if validate

        @json
      end

      def url(id)
        Utils.path_to_url "/dashboard/#{id}"
      end

      private

      def validate_json(data)
        super

        validate_template_variables data, :widgets
      end

      def render_definitions
        definitions.map do |title, type, display_type, queries, options = {}, ignored = nil|
          # validate inputs
          if ignored || (!title || !type || !queries || !options.is_a?(Hash))
            raise ArgumentError, "Expected exactly 5 arguments for each definition (title, type, display_type, queries, options)"
          end
          if (SUPPORTED_DEFINITION_OPTIONS | options.keys) != SUPPORTED_DEFINITION_OPTIONS
            raise ArgumentError, "Supported options are: #{SUPPORTED_DEFINITION_OPTIONS.map(&:inspect).join(", ")}"
          end

          # build definition
          requests = Array(queries).map do |q|
            request = { q: q }
            request[:display_type] = display_type if display_type
            request
          end
          { definition: { title: title, type: type, requests: requests, **options } }
        end
      end
    end
  end
end
