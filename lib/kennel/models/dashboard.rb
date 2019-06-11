# frozen_string_literal: true
#
# TODO: resolve monitor-ids for uptime screen
module Kennel
  module Models
    class Dashboard < Base
      include TemplateVariables
      include OptionalValidations

      API_LIST_INCOMPLETE = true
      READONLY_ATTRIBUTES = (Base::READONLY_ATTRIBUTES + [:url, :notify_list, :modified_at, :is_read_only, :author_name, :author_handle]).freeze
      READONLY_WIDGET_ATTRIBUTES = [:id].freeze
      DEFINITION_DEFAULTS = { autoscale: true, title_align: "left", title_size: "16" }.freeze
      DASH_DEFAULTS = { description: "", template_variables: [].freeze }.freeze
      SUPPORTED_WIDGET_OPTIONS = [:events, :markers, :precision].freeze

      settings :id, :title, :description, :kennel_id, :widgets, :layout_type, :definitions

      defaults(
        id: -> { nil },
        description: -> { DASH_DEFAULTS.fetch(:description) },
        template_variables: -> { DASH_DEFAULTS.fetch(:template_variables) },
        widgets: -> { [] },
        definitions: -> { [] }
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
          id: id,
          title: "#{title}#{LOCK}",
          description: description,
          template_variables: render_template_variables,
          widgets: render_widgets,
          layout_type: layout_type
        }

        validate_json(@json) if validate

        @json
      end

      def self.normalize(expected, actual)
        super

        # path = [:widgets, 7]
        # # path = []
        # puts "ACTUAL #{expected[:description][/kennel (\S+)/, 1]} -- #{expected[:title]}"
        # pp(path.any? ? actual.dig(*path) : actual)
        # puts "Expected #{self < Models::Screen ? "Screen" : "Dash"}"
        # pp(path.any? ? expected.dig(*path) : expected)

        actual[:template_variables] ||= [] # is nil when it never had template variables
        ignore_default expected, actual, DASH_DEFAULTS

        widgets = actual[:widgets] || []

        widgets.each { |w| w.delete(:id) }

        widgets.each { |g| g[:definition].delete(:status) }

        ignore_request_defaults expected, actual, :widgets, :definition

        widgets.each_with_index do |a_g, i|
          a_d = a_g[:definition]
          e_d = expected.dig(:widgets, i, :definition) || {}
          ignore_default e_d, a_d, DEFINITION_DEFAULTS
        end
      end

      def url(id)
        Utils.path_to_url "/dashboard/#{id}"
      end

      def resolve_linked_tracking_ids(id_map)
        as_json[:widgets].each do |widget|
          case widget[:definition][:type]
          when "uptime"
            widget[:definition][:monitor_ids].map! { |id| resolve_link(id, id_map) }
          when "alert_graph"
            widget[:definition][:alert_id] = resolve_link(widget[:definition][:alert_id], id_map).to_s
            widget[:definition][:time] ||= {} # maybe ignore
          end
        end
      end

      private

      def validate_json(data)
        super

        validate_template_variables(data)
        validate_not_setting_unsettable(data)
      end

      # check for fields that are unsettable
      def validate_not_setting_unsettable(data)
        data[:widgets].each do |w|
          if w[:definition].key?(:status)
            invalid! "remove definition status, it is unsettable and will always produce a diff"
          end
        end
      end

      # check for bad variables
      # TODO: do the same check for apm_query and their group_by
      def validate_template_variables(data)
        variables = (data[:template_variables] || []).map { |v| "$#{v.fetch(:name)}" }
        queries = data[:widgets].flat_map { |g| (g[:definition][:requests] || []).map { |r| r[:q] }.compact }
        bad = queries.grep_v(/(#{variables.map { |v| Regexp.escape(v) }.join("|")})\b/)
        if bad.any?
          invalid! "queries #{bad.join(", ")} must use the template variables #{variables.join(", ")}"
        end
      end

      def render_template_variables
        (template_variables || []).map do |v|
          v.is_a?(String) ? { default: "*", prefix: v, name: v } : v
        end
      end

      def render_widgets
        definitions.map do |title, viz, type, queries, options = {}, ignored = nil|
          # validate inputs
          if ignored || (!title || !viz || !queries || !options.is_a?(Hash))
            raise ArgumentError, "Expected exactly 5 arguments for each definition (title, viz, type, queries, options)"
          end
          if options.each_key.any? { |k| !SUPPORTED_WIDGET_OPTIONS.include?(k) }
            raise ArgumentError, "Supported options are: #{SUPPORTED_WIDGET_OPTIONS.map(&:inspect).join(", ")}"
          end

          # build graph
          requests = Array(queries).map do |q|
            request = { q: q }
            request[:type] = type if type
            request
          end

          widget = { title: title, definition: { viz: viz, requests: requests } }

          # whitelist options that can be passed in, so we are flexible in the future
          SUPPORTED_WIDGET_OPTIONS.each do |key|
            widget[:definition][key] = options[key] if options[key]
          end

          # set default values so users do not have to pass them all the time
          if viz == "query_value"
            widget[:definition][:precision] ||= 2
          end

          widget
        end + widgets
      end

      def resolve_link(id, id_map)
        return id if id.is_a?(Integer)
        id_map[id] ||
          Kennel.err.puts("Unable to find #{id} in existing monitors (they need to be created first to link them)")
      end
    end
  end
end
