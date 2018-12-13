# frozen_string_literal: true
module Kennel
  module Models
    class Monitor < Base
      include OptionalValidations

      API_LIST_INCOMPLETE = false
      RENOTIFY_INTERVALS = [0, 10, 20, 30, 40, 50, 60, 90, 120, 180, 240, 300, 360, 720, 1440].freeze # minutes
      QUERY_INTERVALS = ["1m", "5m", "10m", "15m", "30m", "1h", "2h", "4h", "1d"].freeze
      OPTIONAL_SERVICE_CHECK_THRESHOLDS = [:ok, :warning].freeze
      NON_MULTI_TYPES = ["query alert", "log alert", "composite"].freeze # NOTE: event alerts don't seem to return their multi setting
      MONITOR_DEFAULTS = {
        escalation_message: nil,
        evaluation_delay: nil,
        no_data_timeframe: nil
      }.freeze

      settings(
        :query, :name, :message, :escalation_message, :critical, :kennel_id, :type, :renotify_interval, :warning, :timeout_h, :evaluation_delay,
        :ok, :id, :no_data_timeframe, :notify_no_data, :notify_audit, :tags, :multi, :critical_recovery, :warning_recovery, :require_full_window,
        :threshold_windows
      )
      defaults(
        message: -> { "\n\n@slack-#{project.slack}" },
        escalation_message: -> { "" },
        type: -> { "query alert" },
        renotify_interval: -> { 120 },
        warning: -> { nil },
        ok: ->  { nil },
        id: ->  { nil },
        notify_no_data: -> { true },
        no_data_timeframe: -> { notify_no_data ? 60 : nil },
        notify_audit: -> { true },
        tags: -> { @project.tags },
        timeout_h: -> { 0 },
        evaluation_delay: -> { nil },
        multi: -> { !NON_MULTI_TYPES.include?(type) || query.include?(" by ") },
        critical_recovery: -> { nil },
        warning_recovery: -> { nil },
        threshold_windows: -> { nil }
      )

      attr_reader :project

      def initialize(project, *args)
        @project = project
        super(*args)
      end

      def as_json
        return @as_json if @as_json
        data = {
          name: "#{name}#{LOCK}",
          type: type,
          query: query.strip,
          message: message.strip,
          tags: tags.uniq,
          multi: multi,
          options: {
            timeout_h: timeout_h,
            notify_no_data: notify_no_data,
            no_data_timeframe: no_data_timeframe,
            notify_audit: notify_audit,
            require_full_window: require_full_window,
            new_host_delay: 300,
            include_tags: true,
            escalation_message: Utils.presence(escalation_message.strip),
            evaluation_delay: evaluation_delay,
            locked: false, # setting this to true prevents any edit and breaks updates when using replace workflow
            renotify_interval: renotify_interval || 0,
            thresholds: {
              critical: critical
            }
          }
        }

        options = data[:options]
        thresholds = options[:thresholds]

        data[:id] = id if id

        # warning, ok, critical_recovery, and warning_recovery are optional
        [:warning, :ok, :critical_recovery, :warning_recovery].each do |key|
          if value = send(key)
            thresholds[key] = value
          end
        end

        case data.fetch(:type)
        when "service check"
          # avoid diff for default values of 1
          OPTIONAL_SERVICE_CHECK_THRESHOLDS.each { |t| thresholds[t] ||= 1 }
        when "query alert"
          # metric and query values are stored as float by datadog
          thresholds.each { |k, v| thresholds[k] = Float(v) }
        end

        if windows = threshold_windows
          options[:threshold_windows] = windows
        end

        validate_json(data) if validate

        @as_json = data
      end

      def self.api_resource
        "monitor"
      end

      def url(id)
        Utils.path_to_url "/monitors##{id}/edit"
      end

      def self.normalize(expected, actual)
        super
        options = actual.fetch(:options)
        options.delete(:silenced) # we do not manage silenced, so ignore it when diffing
        options[:escalation_message] ||= nil # unset field is not returned and would break the diff

        # fields are not returned when set to true
        if ["service check", "event alert"].include?(actual[:type])
          options[:include_tags] = true unless options.key?(:include_tags)
          options[:require_full_window] = true unless options.key?(:require_full_window)
        end

        case actual[:type]
        when "event alert"
          # setting 0 results in thresholds not getting returned from the api
          options[:thresholds] ||= { critical: 0 }

        when "service check"
          # fields are not returned when created with default values via UI
          OPTIONAL_SERVICE_CHECK_THRESHOLDS.each do |t|
            options[:thresholds][t] ||= 1
          end
        end

        # nil / "" / 0 are not returned from the api when set via the UI
        options[:evaluation_delay] ||= nil

        ignore_default(expected[:options] || {}, options, MONITOR_DEFAULTS)
      end

      private

      def require_full_window
        # default 'on_average', 'at_all_times', 'in_total' aggregations to true, otherwise false
        # https://docs.datadoghq.com/ap/#create-a-monitor
        type != "query alert" || query.start_with?("avg", "min", "sum")
      end

      def validate_json(data)
        type = data.fetch(:type)

        # do not allow deprecated type that will be coverted by datadog and then produce a diff
        if type == "metric alert"
          invalid! "type 'metric alert' is deprecated, do not set type to use the default 'query alert'"
        end

        # verify service checks use interger thresholds to avoid diff
        if type == "service check" && [ok, warning, critical].compact.map(&:class).uniq != [Integer]
          invalid! ":ok, :warning and :critical must be integers for service check type"
        end

        # verify query includes critical value
        if query_value = data.fetch(:query)[/\s*[<>]\s*(\d+(\.\d+)?)\s*$/, 1]
          if Float(query_value) != Float(data.dig(:options, :thresholds, :critical))
            invalid! "critical and value used in query must match"
          end
        end

        # verify renotify interval is valid
        unless RENOTIFY_INTERVALS.include? data.dig(:options, :renotify_interval)
          invalid! "renotify_interval must be one of #{RENOTIFY_INTERVALS.join(", ")}"
        end

        if type == "query alert"
          # verify interval is valud
          interval = data.fetch(:query)[/\(last_(\S+?)\)/, 1]
          unless QUERY_INTERVALS.include?(interval)
            invalid! "query interval was #{interval}, but must be one of #{QUERY_INTERVALS.join(", ")}"
          end
        end

        if ["query alert", "service check"].include?(type) # TODO: most likely more types need this
          # verify is_match uses available variables
          message = data.fetch(:message)
          used = message.scan(/{{\s*#is_match\s*"([a-zA-Z\d_.-]+).name"/).flatten.uniq
          allowed = data.fetch(:query)[/by\s*{([^\}]+)}/, 1].to_s.split(/\s*,\s*/)
          unsupported = used - allowed
          if unsupported.any?
            invalid! "is_match used with unsupported dimensions #{unsupported}, allowed dimensions are #{allowed}"
          end
        end
      end
    end
  end
end
