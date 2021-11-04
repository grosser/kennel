# frozen_string_literal: true
module Kennel
  module Models
    class Dashboard < Record
      include TemplateVariables
      include OptionalValidations

      READONLY_ATTRIBUTES = superclass::READONLY_ATTRIBUTES + [
        :author_handle, :author_name, :modified_at, :url, :is_read_only, :notify_list, :restricted_roles
      ]
      TRACKING_FIELD = :description
      REQUEST_DEFAULTS = {
        style: { line_width: "normal", palette: "dog_classic", line_type: "solid" }
      }.freeze
      WIDGET_DEFAULTS = {
        "timeseries" => {
          legend_size: "0",
          markers: [],
          legend_columns: [
            "avg",
            "min",
            "max",
            "value",
            "sum"
          ],
          legend_layout: "auto",
          yaxis: {
            include_zero: true,
            label: "",
            scale: "linear",
            min: "auto",
            max: "auto"
          },
          show_legend: true,
          time: {},
          title_align: "left",
          title_size: "16"
        },
        "note" => {
          show_tick: false,
          tick_edge: "left",
          tick_pos: "50%",
          text_align: "left",
          has_padding: true,
          background_color: "white",
          font_size: "14"
        },
        "query_value" => {
          time: {},
          title_align: "left",
          title_size: "16"
        },
        "free_text" => {
          font_size: "auto"
        },
        "check_status" => {
          title_align: "left",
          title_size: "16"
        },
        "slo" => {
          global_time_target: "0",
          title_align: "left",
          title_size: "16"
        }
      }.freeze
      SUPPORTED_DEFINITION_OPTIONS = [:events, :markers, :precision].freeze

      DEFAULTS = {
        template_variable_presets: nil
      }.freeze

      settings(
        :title, :description, :definitions, :widgets, :layout_type, :template_variable_presets, :reflow_type,
        :tags
      )

      defaults(
        description: -> { "" },
        definitions: -> { [] },
        widgets: -> { [] },
        template_variable_presets: -> { DEFAULTS.fetch(:template_variable_presets) },
        reflow_type: -> { layout_type == "ordered" ? "auto" : nil },
        tags: -> do # not inherited by default to make onboarding to using dashboard tags simple
          team = project.team
          team.tag_dashboards ? team.tags : []
        end,
        id: -> { nil }
      )

      class << self
        def api_resource
          "dashboard"
        end

        def normalize(expected, actual)
          super

          ignore_default expected, actual, DEFAULTS
          ignore_default expected, actual, reflow_type: "auto" if expected[:layout_type] == "ordered"

          widgets_pairs(expected, actual).each do |pair|
            pair.each { |w| sort_conditional_formats w }
            ignore_widget_defaults(*pair)
            ignore_request_defaults(*pair)
            pair.each { |widget| widget&.delete(:id) } # ids are kinda random so we always discard them
          end
        end

        private

        # conditional_formats ordering is randomly changed by datadog, compare a stable ordering
        def sort_conditional_formats(widget)
          if formats = widget&.dig(:definition, :conditional_formats)
            widget[:definition][:conditional_formats] = formats.sort_by(&:hash)
          end
        end

        def ignore_widget_defaults(expected, actual)
          types = [expected&.dig(:definition, :type), actual&.dig(:definition, :type)].uniq.compact
          return unless types.size == 1
          return unless defaults = WIDGET_DEFAULTS[types.first]
          ignore_default expected&.[](:definition) || {}, actual&.[](:definition) || {}, defaults
        end

        # discard styles/conditional_formats/aggregator if nothing would change when we applied (both are default or nil)
        def ignore_request_defaults(expected, actual)
          a_r = actual&.dig(:definition, :requests) || []
          e_r = expected&.dig(:definition, :requests) || []
          ignore_defaults e_r, a_r, REQUEST_DEFAULTS
        end

        def ignore_defaults(expected, actual, defaults)
          [expected.size, actual.size].max.times do |i|
            ignore_default expected[i] || {}, actual[i] || {}, defaults
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
          result.flat_map { |a, e| [a.size, e.size].max.times.map { |i| [a[i], e[i]] } }
        end
      end

      def as_json
        return @json if @json
        all_widgets = render_definitions(definitions) + widgets
        expand_q all_widgets
        tags = tags()
        tags_as_string = (tags.empty? ? "" : " (#{tags.join(" ")})")

        @json = {
          layout_type: layout_type,
          title: "#{title}#{tags_as_string}#{LOCK}",
          description: description,
          template_variables: render_template_variables,
          template_variable_presets: template_variable_presets,
          widgets: all_widgets
        }

        @json[:reflow_type] = reflow_type if reflow_type # setting nil breaks create with "ordered"

        @json[:id] = id if id

        validate_json(@json) if validate

        @json
      end

      def self.url(id)
        Utils.path_to_url "/dashboard/#{id}"
      end

      def self.parse_url(url)
        url[/\/dashboard\/([a-z\d-]+)/, 1]
      end

      def resolve_linked_tracking_ids!(id_map, **args)
        widgets = as_json[:widgets].flat_map { |w| [w, *w.dig(:definition, :widgets) || []] }
        widgets.each do |widget|
          next unless definition = widget[:definition]
          case definition[:type]
          when "uptime"
            if ids = definition[:monitor_ids]
              definition[:monitor_ids] = ids.map do |id|
                resolve(id, :monitor, id_map, **args) || id
              end
            end
          when "alert_graph"
            if id = definition[:alert_id]
              resolved = resolve(id, :monitor, id_map, **args) || id
              definition[:alert_id] = resolved.to_s # even though it's a monitor id
            end
          when "slo"
            if id = definition[:slo_id]
              definition[:slo_id] = resolve(id, :slo, id_map, **args) || id
            end
          end
        end
      end

      private

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

        validate_template_variables data

        # Avoid diff from datadog presets sorting.
        presets = data[:template_variable_presets]
        invalid! "template_variable_presets must be sorted by name" if presets && presets != presets.sort_by { |p| p[:name] }
      end

      def render_definitions(definitions)
        definitions.map do |title, type, display_type, queries, options = {}, too_many_args = nil|
          if title.is_a?(Hash) && !type
            title # user gave a full widget, just use it
          else
            # validate inputs
            if too_many_args || (!title || !type || !queries || !options.is_a?(Hash))
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
end
