# frozen_string_literal: true
module Kennel
  module Models
    class Dashboard < Base
      include TemplateVariables
      include OptionalValidations

      API_LIST_INCOMPLETE = true
      WIDGET_DEFAULTS = {
        time: {},
        timeframe: "1h"
      }.freeze
      SCREEN_DEFAULTS = { template_variables: [] }.freeze
      WIDGET_READONLY = [:id].freeze
      READONLY_ATTRIBUTES = Base::READONLY_ATTRIBUTES + [:author_handle, :modified_at, :url]

      settings :id, :title, :description, :widgets, :kennel_id

      defaults(
        description: -> { "" },
        widgets: -> { [] },
        id: -> { nil }
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
          title: "#{title}#{LOCK}",
          description: description,
          layout_type: "ordered",
          is_read_only: false,
          notify_list: [],
          widgets: widgets,
          template_variables: render_template_variables
        }

        validate_json(@json) if validate

        @json
      end

      def diff(a)
        super(a)
      end

      def self.normalize(expected, actual)
        super

        ignore_default expected, actual, SCREEN_DEFAULTS
        ignore_widget_readonly expected, actual, WIDGET_READONLY
      end

      def url(id)
        Utils.path_to_url "/dashboard/#{id}"
      end

      def resolve_linked_tracking_ids(id_map)
        as_json[:widgets].each do |widget|
          case widget[:type]
          when "uptime"
            resolve_link(widget, [:monitor, :id], id_map)
          when "alert_graph"
            resolve_link(widget, [:alert_id], id_map)
          end
        end
      end

      private

      def self.ignore_widget_readonly(expected, actual, attributes)
        definitions = [
          *expected[:widgets],
          *actual[:widgets],
          *expected[:widgets].flat_map { |w| w.dig(:definition, :widgets) },
          *actual[:widgets].flat_map { |w| w.dig(:definition, :widgets) }
        ].compact
        definitions.each do |definition|
          definition.delete_if { |key| attributes.include?(key) }
        end
      end

      def resolve_link(widget, key, id_map)
        id = widget.dig(*key)
        return unless tracking_id?(id)

        *id_path, id_key = key
        monitor_path = (id_path.empty? ? widget : widget.dig(*id_path))
        monitor_path[id_key] =
          id_map[id] ||
            Kennel.err.puts("Unable to find #{id} in existing monitors (they need to be created first to link them)")
      end


      def tracking_id?(id)
        id.is_a?(String) && !id.match?(/\A\d+\z/)
      end
    end
  end
end
