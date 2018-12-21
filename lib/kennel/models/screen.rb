# frozen_string_literal: true
module Kennel
  module Models
    class Screen < Base
      include TemplateVariables
      include OptionalValidations

      API_LIST_INCOMPLETE = true
      COPIED_WIDGET_VALUES = [:board_id, :isShared].freeze
      WIDGET_DEFAULTS = {
        time: {},
        timeframe: "1h"
      }.freeze
      READONLY_ATTRIBUTES = (Base::READONLY_ATTRIBUTES + [
        :disableCog,
        :disableEditing,
        :isIntegration,
        :isShared,
        :original_title,
        :read_only,
        :resource,
        :title,
        :title_edited,
        :created_by,
        :board_bgtype,
        :height,
        :width,
        :showGlobalTimeOnboarding,
        :originalHeight,
        :originalWidth
      ]).freeze
      SCREEN_DEFAULTS = { template_variables: [] }.freeze

      settings :id, :board_title, :description, :widgets, :kennel_id

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
        "screen"
      end

      def as_json
        return @json if @json
        @json = {
          id: id,
          board_title: "#{board_title}#{LOCK}",
          description: description,
          widgets: render_widgets,
          template_variables: render_template_variables
        }

        validate_json(@json) if validate

        @json
      end

      def self.normalize(expected, actual)
        super

        (actual[:widgets] || []).each do |w|
          # api randomly returns time.live_span or timeframe or empty time hash
          if w.dig(:time, :live_span)
            w[:timeframe] = w[:time].delete(:live_span)
          end

          COPIED_WIDGET_VALUES.each { |v| w.delete v }
        end

        ignore_default expected, actual, SCREEN_DEFAULTS
        ignore_defaults expected[:widgets], actual[:widgets], WIDGET_DEFAULTS
        ignore_request_defaults expected, actual, :widgets, :tile_def
      end

      def url(id)
        Utils.path_to_url "/screen/#{id}"
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

      def validate_json(data)
        super

        # check for fields that are unsettable
        data[:widgets].each do |w|
          COPIED_WIDGET_VALUES.each do |ignored|
            if w.key?(ignored)
              invalid! "remove definition #{ignored}, it is unsettable and will always produce a diff"
            end
          end
        end
      end

      def render_widgets
        widgets.map do |widget|
          widget = widget_defaults(widget[:type]).merge(widget)
          if tile = widget[:tile_def]
            tile[:autoscale] = true unless widget[:tile_def].key?(:autoscale) # TODO: use ignore_default
          end
          widget
        end
      end

      def widget_defaults(type)
        basics = {
          title_size: 16,
          title_align: "left",
          height: 20,
          width: 30
        }

        custom =
          case type
          when "free_text"
            {
              font_size: "auto",
              text_align: "left",
              title_text: "",
              title: true,
              color: "#4d4d4d"
            }
          when "timeseries"
            {
              title: true,
              legend: false,
              legend_size: "0"
            }
          else
            {}
          end

        basics.merge(custom)
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
