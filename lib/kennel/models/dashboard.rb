# frozen_string_literal: true
module Kennel
  module Models
    class Dashboard < Record
      include TemplateVariables
      include OptionalValidations

      API_LIST_INCOMPLETE = true
      DASHBOARD_DEFAULTS = { template_variables: [] }.freeze
      READONLY_ATTRIBUTES = superclass::READONLY_ATTRIBUTES + [
        :author_handle, :author_name, :modified_at, :url, :is_read_only, :notify_list
      ]
      REQUEST_DEFAULTS = {
        style: { line_width: "normal", palette: "dog_classic", line_type: "solid" }
      }.freeze
      TIMESERIES_DEFAULTS = { show_legend: false, legend_size: "0" }.freeze
      SUPPORTED_DEFINITION_OPTIONS = [:events, :markers, :precision].freeze

      settings :title, :description, :definitions, :widgets, :layout_type

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

          widgets_pairs(expected, actual).each do |pair|
            # datadog always adds 2 to slo widget height
            # need to check fir layout since some monitors have height/width in their definition
            pair[1].each do |widget|
              if widget.dig(:definition, :type) == "slo" && widget.dig(:layout, :height)
                widget[:layout][:height] -= 2
              end
            end

            # conditional_formats ordering is randomly changed by datadog, compare a stable ordering
            pair.each do |widgets|
              widgets.each do |widget|
                if formats = widget.dig(:definition, :conditional_formats)
                  widget[:definition][:conditional_formats] = formats.sort_by(&:hash)
                end
              end
            end

            ignore_definition_defaults_for_type pair, "timeseries", TIMESERIES_DEFAULTS

            ignore_request_defaults(*pair)

            # ids are kinda random so we always discard them
            pair.each { |widgets| widgets.each { |w| w.delete(:id) } }
          end
        end

        private

        def ignore_definition_defaults_for_type(pair, type, defaults)
          pair.map(&:size).max.times do |i|
            if pair.all? { |w| w.dig(i, :definition, :type) == type }
              ignore_defaults(pair[0], pair[1], defaults, nesting: :definition)
            end
          end
        end

        # discard styles/conditional_formats/aggregator if nothing would change when we applied (both are default or nil)
        def ignore_request_defaults(expected, actual)
          [expected.size, actual.size].max.times do |i|
            a_r = actual.dig(i, :definition, :requests) || []
            e_r = expected.dig(i, :definition, :requests) || []
            ignore_defaults e_r, a_r, REQUEST_DEFAULTS
          end
        end

        def ignore_defaults(expected, actual, defaults, nesting: nil)
          [expected.size, actual.size].max.times do |i|
            e = expected.dig(i, *nesting) || {}
            a = actual.dig(i, *nesting) || {}
            ignore_default(e, a, defaults)
          end
        end

        # expand nested widgets into expected/actual pairs for default resolution
        # [a, e] -> [[a-w, e-w], [a-w1-w1, e-w1-w1], ...]
        def widgets_pairs(*pair)
          result = [pair.map { |d| d[:widgets] || [] }]
          slots = result[0].map(&:size).max
          slots.times do |i|
            nested = pair.map { |d| d.dig(:widgets, i, :definition, :widgets) || [] }
            result << nested if nested.any?(&:any?)
          end
          result
        end
      end

      def as_json
        return @json if @json
        all_widgets = render_definitions + widgets
        expand_q all_widgets

        @json = {
          layout_type: layout_type,
          title: "#{title}#{LOCK}",
          description: description,
          template_variables: render_template_variables,
          widgets: all_widgets
        }

        @json[:id] = id if id

        validate_json(@json) if validate

        @json
      end

      def url(id)
        Utils.path_to_url "/dashboard/#{id}"
      end

      def resolve_linked_tracking_ids(id_map)
        as_json[:widgets].each do |widget|
          next unless definition = widget[:definition]
          case definition[:type]
          when "uptime"
            if ids = definition[:monitor_ids]
              definition[:monitor_ids] = ids.map do |id|
                tracking_id?(id) ? resolve_link(id, id_map) : id
              end
            end
          when "alert_graph"
            if (id = definition[:alert_id]) && tracking_id?(id)
              definition[:alert_id] = resolve_link(id, id_map).to_s
            end
          when "slo"
            if (id = definition[:slo_id]) && tracking_id?(id)
              definition[:slo_id] = resolve_link(id, id_map).to_s
            end
          end
        end
      end

      private

      def tracking_id?(id)
        id.is_a?(String) && !id.match?(/\A\d+\z/)
      end

      # creates queries from metadata to avoid having to keep q and expression in sync
      #
      # {q: :metadata, metadata: [{expression: "sum:bar", alias_name: "foo"}, ...], }
      # -> {q: "sum:bar, ...", metadata: ..., }
      def expand_q(widgets)
        widgets = widgets.flat_map { |w| w.dig(:definition, :widgets) || w } # expand groups
        widgets.each do |w|
          w.dig(:definition, :requests)&.each do |request|
            next unless request.is_a?(Hash) && request[:q] == :metadata
            request[:q] = request.fetch(:metadata).map { |m| m.fetch(:expression) }.join(", ")
          end
        end
      end

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
