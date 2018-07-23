# frozen_string_literal: true
module Kennel
  module Models
    class Screen < Base
      include TemplateVariables
      include OptionalValidations

      API_LIST_INCOMPLETE = true
      SUPPORTED_DEFINITION_OPTIONS = [:title_text, :height, :width, :timeframe, :x, :y].freeze

      settings :id, :board_title, :description, :widgets, :definitions, :kennel_id

      defaults(
        description: -> { "" },
        widgets: -> { [] },
        definitions: -> { [] },
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

      def diff(actual)
        actual.delete(:disableCog)
        actual.delete(:disableEditing)
        actual.delete(:isIntegration)
        actual.delete(:isShared)
        actual.delete(:original_title)
        actual.delete(:read_only)
        actual.delete(:resource)
        actual.delete(:title)
        actual.delete(:title_edited)
        actual.delete(:created_by)
        actual.delete(:board_bgtype)
        actual.delete(:height)
        actual.delete(:width)
        actual.delete(:showGlobalTimeOnboarding)
        actual[:template_variables] ||= []
        (actual[:widgets] || []).each do |w|
          # api randomly returns time.live_span or timeframe
          w[:timeframe] = w.delete(:time)[:live_span] if w[:time]

          w.delete :board_id # copied value, can ignore
          w.delete :isShared # copied value, can ignore
        end

        ignore_request_defaults as_json, actual, :widgets, :tile_def

        super
      end

      def url(id)
        Utils.path_to_url "/screen/#{id}"
      end

      private

      def validate_json(data)
        # check for fields that are unsettable
        data[:widgets].each do |w|
          [:isShared, :board_id].each do |ignored|
            if w.key?(ignored)
              invalid! "remove definition #{ignored}, it is unsettable and will always produce a diff"
            end
          end
        end
      end

      def render_widgets
        index = -1
        rows = 5

        all = definitions.map do |title, viz, type, queries, options = {}, ignored = nil|
          if ignored || (!title || !viz || !type || !queries || !options.is_a?(Hash))
            raise ArgumentError, "Expected exactly 4 arguments for each definition (title, viz | nil, type, queries | text, options)"
          end

          if options.each_key.any? { |k| !SUPPORTED_DEFINITION_OPTIONS.include?(k) }
            raise ArgumentError, "Supported options are: #{SUPPORTED_DEFINITION_OPTIONS.map(&:inspect).join(", ")}"
          end

          index += 1
          column = index % rows

          {
            width: 8,
            height: 4,
            timeframe: "1h",
            x: column * 8,
            y: rows * 4,
            type: type,
            tile_def: {
              viz: viz,
              requests: queries.map { |q| { q: q, type: type } }
            }
          }.merge(options)
        end + widgets

        all.map do |widget|
          widget = widget_defaults(widget[:type]).merge(widget)
          if tile = widget[:tile_def]
            tile[:autoscale] = true unless widget[:tile_def].key?(:autoscale)
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
              legend_size: "0",
              timeframe: "1h"
            }
          else
            {}
          end

        basics.merge(custom)
      end
    end
  end
end
