# frozen_string_literal: true
module Kennel
  module Models
    class Monitor < Record
      include OptionalValidations

      RENOTIFY_INTERVALS = [0, 10, 20, 30, 40, 50, 60, 90, 120, 180, 240, 300, 360, 720, 1440].freeze # minutes
      OPTIONAL_SERVICE_CHECK_THRESHOLDS = [:ok, :warning].freeze
      READONLY_ATTRIBUTES = superclass::READONLY_ATTRIBUTES + [
        :multi, :matching_downtimes, :overall_state_modified, :overall_state, :restricted_roles
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
        groupby_simple_monitor: false
      }.freeze
      DEFAULT_ESCALATION_MESSAGE = ["", nil].freeze
      ALLOWED_PRIORITY_CLASSES = [NilClass, Integer].freeze

      settings(
        :query, :name, :message, :escalation_message, :critical, :type, :renotify_interval, :warning, :timeout_h, :evaluation_delay,
        :ok, :no_data_timeframe, :notify_no_data, :notify_audit, :tags, :critical_recovery, :warning_recovery, :require_full_window,
        :threshold_windows, :new_host_delay, :new_group_delay, :priority
      )

      defaults(
        message: -> { "\n\n#{project.mention}" },
        escalation_message: -> { DEFAULT_ESCALATION_MESSAGE.first },
        renotify_interval: -> { project.team.renotify_interval },
        warning: -> { nil },
        ok: -> { nil },
        id: -> { nil },
        notify_no_data: -> { true }, # datadog sets this to false by default, but true is the safer
        no_data_timeframe: -> { 60 },
        notify_audit: -> { MONITOR_OPTION_DEFAULTS.fetch(:notify_audit) },
        new_host_delay: -> { MONITOR_OPTION_DEFAULTS.fetch(:new_host_delay) },
        new_group_delay: -> { nil },
        tags: -> { @project.tags },
        timeout_h: -> { MONITOR_OPTION_DEFAULTS.fetch(:timeout_h) },
        evaluation_delay: -> { MONITOR_OPTION_DEFAULTS.fetch(:evaluation_delay) },
        critical_recovery: -> { nil },
        warning_recovery: -> { nil },
        threshold_windows: -> { nil },
        priority: -> { MONITOR_DEFAULTS.fetch(:priority) }
      )

      def as_json
        return @as_json if @as_json
        data = {
          name: "#{name}#{LOCK}",
          type: type,
          query: query.strip,
          message: message.strip,
          tags: tags.uniq,
          priority: priority,
          options: {
            timeout_h: timeout_h,
            notify_no_data: notify_no_data,
            no_data_timeframe: notify_no_data ? no_data_timeframe : nil,
            notify_audit: notify_audit,
            require_full_window: require_full_window,
            new_host_delay: new_host_delay,
            new_group_delay: new_group_delay,
            include_tags: true,
            escalation_message: Utils.presence(escalation_message.strip),
            evaluation_delay: evaluation_delay,
            locked: false, # setting this to true prevents any edit and breaks updates when using replace workflow
            renotify_interval: renotify_interval || 0
          }
        }

        data[:id] = id if id

        options = data[:options]
        if data.fetch(:type) != "composite"
          thresholds = (options[:thresholds] = { critical: critical })

          # warning, ok, critical_recovery, and warning_recovery are optional
          [:warning, :ok, :critical_recovery, :warning_recovery].each do |key|
            if value = send(key)
              thresholds[key] = value
            end
          end

          thresholds[:critical] = critical unless
          case data.fetch(:type)
          when "service check"
            # avoid diff for default values of 1
            OPTIONAL_SERVICE_CHECK_THRESHOLDS.each { |t| thresholds[t] ||= 1 }
          when "query alert"
            # metric and query values are stored as float by datadog
            thresholds.each { |k, v| thresholds[k] = Float(v) }
          end
        end

        if windows = threshold_windows
          options[:threshold_windows] = windows
        end

        # Datadog requires only either new_group_delay or new_host_delay, never both
        options.delete(options[:new_group_delay] ? :new_host_delay : :new_group_delay)

        validate_json(data) if validate

        @as_json = data
      end

      def resolve_linked_tracking_ids!(id_map, **args)
        case as_json[:type]
        when "composite", "slo alert"
          type = (as_json[:type] == "composite" ? :monitor : :slo)
          as_json[:query] = as_json[:query].gsub(/%{(.*?)}/) do
            resolve($1, type, id_map, **args) || $&
          end
        end
      end

      def validate_update!(_actual, diffs)
        if bad_diff = diffs.find { |diff| diff[1] == "type" }
          raise "Datadog does not allow update of #{bad_diff[1]} (in #{tracking_id}, #{bad_diff[2].inspect} -> #{bad_diff[3].inspect})"
        end
      end

      def self.api_resource
        "monitor"
      end

      def self.url(id)
        Utils.path_to_url "/monitors##{id}/edit"
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
        options.delete(:silenced) # we do not manage silenced, so ignore it when diffing

        # fields are not returned when set to true
        if ["service check", "event alert"].include?(actual[:type])
          options[:include_tags] = true unless options.key?(:include_tags)
          options[:require_full_window] = true unless options.key?(:require_full_window)
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
        end

        # nil / "" / 0 are not returned from the api when set via the UI
        options[:evaluation_delay] ||= nil

        expected_options = expected[:options] || {}
        ignore_default(expected_options, options, MONITOR_OPTION_DEFAULTS)
        if DEFAULT_ESCALATION_MESSAGE.include?(options[:escalation_message])
          options.delete(:escalation_message)
          expected_options.delete(:escalation_message)
        end
      end

      private

      def require_full_window
        # default 'on_average', 'at_all_times', 'in_total' aggregations to true, otherwise false
        # https://docs.datadoghq.com/ap/#create-a-monitor
        type != "query alert" || query.start_with?("avg", "min", "sum")
      end

      def validate_json(data)
        super

        type = data.fetch(:type)

        # do not allow deprecated type that will be coverted by datadog and then produce a diff
        if type == "metric alert"
          invalid! "type 'metric alert' is deprecated, please set to a different type (e.g. 'query alert')"
        end

        # verify query includes critical value
        if query_value = data.fetch(:query)[/\s*[<>]=?\s*(\d+(\.\d+)?)\s*$/, 1]
          if Float(query_value) != Float(data.dig(:options, :thresholds, :critical))
            invalid! "critical and value used in query must match"
          end
        end

        # verify renotify interval is valid
        unless RENOTIFY_INTERVALS.include? data.dig(:options, :renotify_interval)
          invalid! "renotify_interval must be one of #{RENOTIFY_INTERVALS.join(", ")}"
        end

        if ["query alert", "service check"].include?(type) # TODO: most likely more types need this
          validate_message_variables(data)
        end

        unless ALLOWED_PRIORITY_CLASSES.include?(priority.class)
          invalid! "priority needs to be an Integer"
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

        # TODO
        # - also match without by
        # - separate parsers for query and service
        # - service must always allow `host`, maybe others
        return unless match = data.fetch(:query).match(/(?:{([^}]*)}\s*)?by\s*[({]([^})]+)[})]/)

        allowed =
          match[1].to_s.split(/\s*,\s*/).map { |k| k.split(":", 2)[-2] } + # {a:b} -> a TODO: does not work for service check
          match[2].to_s.gsub(/["']/, "").split(/\s*,\s*/) # by {a} -> a

        allowed.compact!
        allowed.uniq!
        allowed.map! { |w| "#{w.tr('"', "")}.name" }

        forbidden = used - allowed
        return if forbidden.empty?

        invalid! <<~MSG.rstrip
          Used #{forbidden.join(", ")} in the message, but can only be used with #{allowed.join(", ")}.
          Group or filter the query by #{forbidden.map { |f| f.sub(".name", "") }.join(", ")} to use it.
        MSG
      end
    end
  end
end
