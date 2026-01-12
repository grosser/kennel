# frozen_string_literal: true
module Kennel
  module Models
    class Monitor < Record
      include TagsValidation

      OPTIONAL_SERVICE_CHECK_THRESHOLDS = [:ok, :warning].freeze
      READONLY_ATTRIBUTES = superclass::READONLY_ATTRIBUTES + [
        :multi, :matching_downtimes, :overall_state_modified, :overall_state, :restricted_roles, :draft_status, :assets,
        :enable_logs_sample
      ]
      TRACKING_FIELD = :message

      MONITOR_DEFAULTS = {
        priority: nil
      }.freeze

      # defaults that datadog uses when options are not sent, so safe to leave out if our values match their defaults
      MONITOR_OPTION_DEFAULTS = {
        evaluation_delay: nil,
        new_host_delay: 300,
        timeout_h: 0,
        renotify_interval: 0,
        notify_audit: false,
        no_data_timeframe: nil, # this works out ok since if notify_no_data is on, it would never be nil
        group_retention_duration: nil,
        groupby_simple_monitor: false,
        variables: nil,
        on_missing_data: nil,
        notification_preset_name: nil,
        notify_by: nil
      }.freeze
      DEFAULT_ESCALATION_MESSAGE = ["", nil].freeze
      ALLOWED_PRIORITY_CLASSES = [NilClass, Integer].freeze
      SKIP_NOTIFY_NO_DATA_TYPES = ["event alert", "event-v2 alert", "log alert"].freeze
      MINUTES_PER_UNIT = {
        "m" => 1,
        "h" => 60,
        "d" => 60 * 24,
        "w" => 60 * 24 * 7
      }.freeze

      settings(
        :query, :name, :message, :escalation_message, :critical, :type, :renotify_interval, :warning, :timeout_h, :evaluation_delay,
        :ok, :no_data_timeframe, :notify_no_data, :notify_audit, :tags, :critical_recovery, :warning_recovery, :require_full_window,
        :threshold_windows, :scheduling_options, :new_host_delay, :new_group_delay, :group_retention_duration, :priority,
        :variables, :on_missing_data, :notification_preset_name, :notify_by
      )

      defaults(
        message: -> { "\n\n#{project.mention}" },
        escalation_message: -> { DEFAULT_ESCALATION_MESSAGE.first },
        renotify_interval: -> { project.team.renotify_interval },
        warning: -> { nil },
        ok: -> { nil },
        # datadog UI sets this to false by default, but true is safer
        # except for log alerts which will always have "no error" gaps and should default to false
        notify_no_data: -> { !SKIP_NOTIFY_NO_DATA_TYPES.include?(type) },
        no_data_timeframe: -> { MONITOR_OPTION_DEFAULTS.fetch(:no_data_timeframe) },
        notify_audit: -> { MONITOR_OPTION_DEFAULTS.fetch(:notify_audit) },
        new_host_delay: -> { MONITOR_OPTION_DEFAULTS.fetch(:new_host_delay) },
        new_group_delay: -> { nil },
        group_retention_duration: -> { MONITOR_OPTION_DEFAULTS.fetch(:group_retention_duration) },
        tags: -> { @project.tags },
        evaluation_delay: -> { MONITOR_OPTION_DEFAULTS.fetch(:evaluation_delay) },
        critical_recovery: -> { nil },
        warning_recovery: -> { nil },
        threshold_windows: -> { nil },
        scheduling_options: -> { nil },
        priority: -> { MONITOR_DEFAULTS.fetch(:priority) },
        variables: -> { MONITOR_OPTION_DEFAULTS.fetch(:variables) },
        on_missing_data: -> { MONITOR_OPTION_DEFAULTS.fetch(:on_missing_data) },
        notification_preset_name: -> { MONITOR_OPTION_DEFAULTS.fetch(:notification_preset_name) },
        notify_by: -> { MONITOR_OPTION_DEFAULTS.fetch(:notify_by) },
        require_full_window: -> { false }
      )

      def build_json
        no_data_options = configure_no_data

        data = super.merge(
          name: "#{name}#{LOCK}",
          type: type,
          query: query.strip,
          message: message.strip,
          tags: tags,
          priority: priority,
          options: {
            timeout_h: timeout_h,
            **no_data_options.except(:on_missing_data),
            notify_audit: notify_audit,
            require_full_window: require_full_window,
            new_host_delay: new_host_delay,
            new_group_delay: new_group_delay,
            include_tags: true,
            escalation_message: Utils.presence(escalation_message.strip),
            evaluation_delay: evaluation_delay,
            renotify_interval: renotify_interval || 0,
            variables: variables,
            **configure_thresholds,
            **no_data_options.slice(:on_missing_data) # moved here to avoid generated diff
          }
        )

        options = data[:options]

        # set without causing lots of nulls to be stored
        if (notify_by_value = notify_by)
          options[:notify_by] = notify_by_value
        end

        # setting this via the api breaks the UI with
        # "The no_data_timeframe option is not allowed for log alert monitors"
        if data.fetch(:type) == "log alert"
          options.delete :no_data_timeframe
        end

        if (windows = threshold_windows)
          options[:threshold_windows] = windows
        end

        if (schedule = scheduling_options)
          options[:scheduling_options] = schedule
        end

        # Datadog requires only either new_group_delay or new_host_delay, never both
        options.delete(options[:new_group_delay] ? :new_host_delay : :new_group_delay)

        if (duration = group_retention_duration)
          options[:group_retention_duration] = duration
        end

        # Add in statuses where we would re notify on. Possible values: alert, no data, warn
        if options[:renotify_interval] != 0
          statuses = ["alert"]
          statuses << "no data" if options[:notify_no_data] || options[:on_missing_data] == "show_and_notify_no_data"
          statuses << "warn" if options.dig(:thresholds, :warning)
          options[:renotify_statuses] = statuses
        end

        # only set when needed to avoid big diff
        if (notification_preset_name = notification_preset_name())
          options[:notification_preset_name] = notification_preset_name
        end

        data
      end

      # TODO: migrate everything to only use on_missing_data by only sending notify_no_data when it was set by a user
      # and enforce that it is not set at the same time as on_missing_data
      def configure_no_data
        notify = notify_no_data
        timeframe = no_data_timeframe
        action = on_missing_data
        action ||= "default" if type == "event-v2 alert"

        # TODO: mark setting action && !notify.nil? at all as invalid
        if action && timeframe
          invalid! :invalid_no_data_config, "set either no_data_timeframe or on_missing_data"
        end
        if type == "composite" && action
          invalid! :invalid_no_data_config, "cannot use on_missing_data with composite monitor"
        end
        if action == "resolve" && timeout_h.to_i != 0
          invalid! :invalid_no_data_config, "timeout_h cannot be set and non-zero when on_missing_data is `resolve`"
        end

        # on_missing_data cannot be used with notify_no_data + no_data_timeframe
        if action
          { on_missing_data: action || "default" }
        else
          {
            notify_no_data: notify,
            no_data_timeframe: notify ? no_data_timeframe || default_no_data_timeframe : nil
          }
        end
      end

      def resolve_linked_tracking_ids!(id_map, **args)
        case as_json[:type]
        when "composite", "slo alert"
          type = (as_json[:type] == "composite" ? :monitor : :slo)
          as_json[:query] = as_json[:query].gsub(/%{(.*?)}/) do
            resolve($1, type, id_map, **args) || $&
          end
        else # do nothing
        end
      end

      # ensure type does not change, but not if it's metric->query which is supported and used by importer.rb
      def allowed_update_error(actual)
        actual_type = actual[:type]
        return if actual_type == type || (actual_type == "metric alert" && type == "query alert")
        "cannot update type from #{actual_type} to #{type}"
      end

      # deprecated this setting is no longer returned by dd for new monitors
      # datadog UI warns when setting no data timeframe to less than 2x the query window
      # limited to 24h because `no_data_timeframe must not exceed group retention` and max group retention is 24h
      def default_no_data_timeframe
        default = 60
        if type == "query alert" && (minutes = query_window_minutes)
          (minutes * 2).clamp(default, 24 * 60)
        else
          default
        end
      end

      # validate that monitors that alert on no data resolve in external services by using timeout_h, so it sends a
      # notification when the no data group is removed from the monitor, which datadog does automatically after 24h
      def timeout_h
        sending_no_data_notifications = (on_missing_data ? on_missing_data == "show_and_notify_no_data" : notify_no_data)
        sending_no_data_notifications ? 24 : MONITOR_OPTION_DEFAULTS.fetch(:timeout_h)
      end

      def self.api_resource
        "monitor"
      end

      def self.url(id)
        Utils.path_to_url "/monitors/#{id}/edit"
      end

      def self.parse_url(url)
        # datadog uses / for show and # for edit as separator in it's links
        id = url[/\/monitors[\/#](\d+)/, 1]

        # slo alert url
        id ||= url[/\/slo\/edit\/[a-z\d]{10,}\/alerts\/(\d+)/, 1]

        return unless id

        Integer(id)
      end

      def self.normalize(expected, actual)
        super

        ignore_default(expected, actual, MONITOR_DEFAULTS)

        options = actual.fetch(:options)

        # we do not manage silenced: ignore it when diffing
        options.delete(:silenced)

        # fields are not returned when set to true
        if ["service check", "event alert"].include?(actual[:type])
          options[:include_tags] = true unless options.key?(:include_tags)
          options[:require_full_window] = false unless options.key?(:require_full_window)
        end

        case actual[:type]
        when "event alert"
          # setting nothing results in thresholds not getting returned from the api
          options[:thresholds] ||= { critical: 0 }

        when "service check"
          # fields are not returned when created with default values via UI
          OPTIONAL_SERVICE_CHECK_THRESHOLDS.each do |t|
            options[:thresholds][t] ||= 1
          end
        else # do nothing
        end

        # nil / "" / 0 are not returned from the api when set via the UI
        options[:evaluation_delay] ||= nil

        expected_options = expected[:options] || {}
        ignore_default(expected_options, options, MONITOR_OPTION_DEFAULTS)
        if DEFAULT_ESCALATION_MESSAGE.include?(options[:escalation_message])
          options.delete(:escalation_message)
          expected_options.delete(:escalation_message)
        end

        # locked is deprecated: ignored when diffing
        options.delete(:locked)
      end

      private

      def configure_thresholds
        return {} if type == "composite"

        thresholds = { critical: critical }

        # set optional variables
        [:warning, :ok, :critical_recovery, :warning_recovery].each do |key|
          if (value = send(key))
            thresholds[key] = value
          end
        end

        # custom logic for some types
        case type
        when "service check"
          # avoid diff for default values of 1
          OPTIONAL_SERVICE_CHECK_THRESHOLDS.each { |t| thresholds[t] ||= 1 }
        when "query alert"
          # metric and query values are stored as float by datadog
          thresholds.each { |k, v| thresholds[k] = Float(v) }
        end

        { thresholds: thresholds }
      end

      def validate_json(data)
        super

        if data[:name]&.start_with?(" ")
          invalid! :name_must_not_start_with_space, "name cannot start with a space"
        end

        type = data.fetch(:type)

        # do not allow deprecated type that will be coverted by datadog and then produce a diff
        if type == "metric alert"
          invalid! :metric_alert_is_deprecated, "type 'metric alert' is deprecated, please set to a different type (e.g. 'query alert')"
        end

        # verify query includes critical value
        if (critical = data.dig(:options, :thresholds, :critical))
          if (query_value = data.fetch(:query)[/\s*[<>]=?\s*(\d+(\.\d+)?)\s*$/, 1])
            if Float(query_value) != Float(critical)
              invalid! :critical_does_not_match_query, "critical and value used in query must match"
            end
          end
        end

        if ["query alert", "service check"].include?(type) # TODO: most likely more types need this
          validate_message_variables(data)
        end

        validate_using_links(data)
        validate_thresholds(data)

        if type == "service check" && !data[:query].to_s.include?(".by(")
          invalid! :query_must_include_by, "query must include a .by() at least .by(\"*\")"
        end

        unless ALLOWED_PRIORITY_CLASSES.include?(priority.class)
          invalid! :invalid_priority, "priority needs to be an Integer"
        end

        if data.dig(:options, :timeout_h)&.> 24
          invalid! :invalid_timeout_h, "timeout_h must be <= 24"
        end
      end

      # verify is_match/is_exact_match and {{foo.name}} uses available variables
      def validate_message_variables(data)
        message = data.fetch(:message)

        used =
          message.scan(/{{\s*(?:[#^]is(?:_exact)?_match)\s*"([^\s}]+)"/) + # {{#is_match "environment.name" "production"}}
          message.scan(/{{\s*([^}]+\.name)\s*}}/) # Pod {{pod.name}} failed
        return if used.empty?
        used.flatten!(1)
        used.uniq!
        used.map! { |w| w.tr("[]", "") }

        # TODO
        # - also match without by
        # - separate parsers for query and service
        # - service must always allow `host`, maybe others
        return unless (match = data.fetch(:query).match(/(?:{([^}]*)}\s*)?by\s*[({]([^})]+)[})]/))

        allowed =
          match[1].to_s.split(/\s*,\s*/).map { |k| k.split(":", 2)[-2] } + # {a:b} -> a TODO: does not work for service check
          match[2].to_s.gsub(/["']/, "").split(/\s*,\s*/) # by {a} -> a

        return if allowed.include?("*")

        allowed.compact!
        allowed.uniq!
        allowed.map! { |w| "#{w.tr('"', "")}.name" }

        forbidden = used - allowed
        return if forbidden.empty?

        invalid! :invalid_variable_used_in_message, <<~MSG.rstrip
          Used #{forbidden.join(", ")} in the message, but can only be used with #{allowed.join(", ")}.
          Group or filter the query by #{forbidden.map { |f| f.sub(".name", "") }.join(", ")} to use it.
        MSG
      end

      def validate_using_links(data)
        case data[:type]
        when "composite" # TODO: add slo to mirror resolve_linked_tracking_ids! logic
          ids = data[:query].tr("-", "_").scan(/\b\d+\b/)
          if ids.any?
            invalid! :links_must_be_via_tracking_id, <<~MSG.rstrip
              Use kennel ids in the query for linking monitors instead of #{ids}, for example `%{#{project.kennel_id}:<monitor id>}`
              If the target monitors are not managed via kennel, add `ignored_errors: [:links_must_be_via_tracking_id] # linked monitors are not in kennel`
            MSG
          end
        when "slo alert"
          if (id = data[:query][/error_budget\("([a-f\d]+)"\)/, 1])
            invalid! :links_must_be_via_tracking_id, <<~MSG
              Use kennel ids in the query for linking alerts to slos instead of "#{id}", for example `error_budget("%{#{project.kennel_id}:slo_id_goes_here}")
              If the target slo is not managed by kennel, then add `ignored_errors: [:links_must_be_via_tracking_id] # linked slo is not in kennel`
            MSG
          end
        else # do nothing
        end
      end

      # Prevent "Warning threshold (50.0) must be less than the alert threshold (20.0) with > comparison."
      def validate_thresholds(data)
        return unless (warning = data.dig(:options, :thresholds, :warning))
        critical = data.dig(:options, :thresholds, :critical)

        case data[:query]
        when /<=?\s*\S+\s*$/
          if warning <= critical
            invalid!(
              :alert_less_than_warning,
              "Warning threshold (#{warning}) must be greater than the alert threshold (#{critical}) with < comparison"
            )
          end
        when />=?\s*\S+\s*$/
          if warning >= critical
            invalid!(
              :alert_less_than_warning,
              "Warning threshold (#{warning}) must be less than the alert threshold (#{critical}) with > comparison"
            )
          end
        else # do nothing
        end
      end

      def query_window_minutes
        return unless (match = query.match(/^\s*\w+\(last_(?<count>\d+)(?<unit>[mhdw])\):/))
        Integer(match["count"]) * MINUTES_PER_UNIT.fetch(match["unit"])
      end
    end
  end
end
