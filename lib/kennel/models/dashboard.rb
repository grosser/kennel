# frozen_string_literal: true
module Kennel
  module Models
    class Dashboard < Base
      include TemplateVariables
      include OptionalValidations

      API_LIST_INCOMPLETE = true
      DASHBOARD_DEFAULTS = { template_variables: [] }.freeze
      READONLY_ATTRIBUTES = Base::READONLY_ATTRIBUTES + [
        :author_handle, :author_name, :modified_at, :url, :is_read_only, :notify_list
      ]
      REQUEST_DEFAULTS = {
        style: { line_width: "normal", palette: "dog_classic", line_type: "solid" }
      }.freeze

      settings :id, :title, :description, :widgets, :kennel_id, :layout_type

      defaults(
        description: -> { "" },
        widgets: -> { [] },
        id: -> { nil }
      )

      class << self
        def normalize(expected, actual)
          super

          ignore_default expected, actual, DASHBOARD_DEFAULTS

          base_pairs(expected, actual).each do |pair|
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

      def self.api_resource
        "dashboard"
      end

      def as_json
        return @json if @json
        @json = {
          layout_type: layout_type,
          title: "#{title}#{LOCK}",
          description: description,
          template_variables: render_template_variables,
          widgets: widgets
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
    end
  end
end
