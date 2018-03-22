# frozen_string_literal: true
module Kennel
  module Models
    class Monitor < Base
      include OptionalValidations

      API_LIST_INCOMPLETE = false
      RENOTIFY_INTERVALS = [0, 10, 20, 30, 40, 50, 60, 90, 120, 180, 240, 300, 360, 720, 1440].freeze # minutes
      QUERY_INTERVALS = ["1m", "5m", "10m", "15m", "30m", "1h", "2h", "4h", "24h"].freeze

      settings(
        :query, :name, :message, :escalation_message, :critical, :kennel_id, :type, :renotify_interval, :warning,
        :ok, :id, :no_data_timeframe, :notify_no_data, :tags, :multi, :critical_recovery, :warning_recovery
      )
      defaults(
        message: -> { "" },
        escalation_message: -> { "" },
        type: -> { "query alert" },
        renotify_interval: -> { 120 },
        warning: -> { nil },
        ok: ->  { nil },
        id: ->  { nil },
        notify_no_data: -> { true },
        no_data_timeframe: -> { notify_no_data ? 60 : nil },
        tags: -> { [] },
        multi: ->  { type != "query alert" || query.include?(" by ") },
        critical_recovery: -> { nil },
        warning_recovery: -> { nil }
      )

      attr_reader :project

      def initialize(project, *args)
        @project = project
        super(*args)
      end

      def kennel_id
        if self.class == Kennel::Models::Monitor
          raise "Need to set :kennel_id when defining monitors from Kennel::Models::Monitor"
        end
        super
      end

      def as_json
        return @as_json if @as_json
        data = {
          name: "#{name}#{LOCK}",
          type: type,
          query: query,
          message: <<~TEXT.strip,
            #{message}

            @slack-#{project.team.slack}
          TEXT
          tags: @project.tags + tags,
          multi: multi,
          options: {
            timeout_h: 0,
            notify_no_data: notify_no_data,
            no_data_timeframe: no_data_timeframe,
            notify_audit: true,
            require_full_window: true,
            new_host_delay: 300,
            include_tags: true,
            escalation_message: Utils.presence(escalation_message.strip),
            evaluation_delay: nil,
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
        thresholds[:warning] = warning if warning
        thresholds[:ok] = ok if ok
        thresholds[:critical_recovery] = critical_recovery if critical_recovery
        thresholds[:warning_recovery] = warning_recovery if warning_recovery

        # metric and query values are stored as float by datadog
        if data.fetch(:type) == "query alert"
          thresholds.each { |k, v| thresholds[k] = Float(v) }
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

      def diff(actual)
        options = actual.fetch(:options)
        options.delete(:silenced) # we do not manage silenced, so ignore it when diffing
        options[:escalation_message] ||= nil # unset field is not returned and would break the diff

        # fields are not returned when set to true
        if ["service check", "event alert"].include?(actual[:type])
          options[:include_tags] = true unless options.key?(:include_tags)
          options[:require_full_window] = true unless options.key?(:require_full_window)
        end

        # setting 0 results in thresholds not getting returned from the api
        if actual[:type] == "event alert"
          options[:thresholds] ||= { critical: 0 }
        end

        # fields are not returned when set to true
        if actual[:type] == "service check"
          options[:thresholds][:critical] ||= 1
          options[:thresholds][:warning] ||= 1
          options[:thresholds][:ok] ||= 1
        end

        # nil or "" are not returned from the api
        options[:evaluation_delay] ||= nil

        super
      end

      private

      def validate_json(data)
        type = data.fetch(:type)

        if type == "metric alert"
          raise "#{tracking_id} type 'metric alert' is deprecated, do not set type to use the default 'query alert'"
        end

        if type == "service check" && [ok, warning, critical].compact.map(&:class).uniq != [Integer]
          raise "#{tracking_id} :ok, :warning and :critical must be integers for service check type"
        end

        if query_value = data.fetch(:query)[/\s*[<>]\s*(\d+(\.\d+)?)\s*$/, 1]
          if Float(query_value) != Float(data.dig(:options, :thresholds, :critical))
            raise "#{tracking_id} critical and value used in query must match"
          end
        end

        unless RENOTIFY_INTERVALS.include? data.dig(:options, :renotify_interval)
          raise "#{tracking_id} renotify_interval must be one of #{RENOTIFY_INTERVALS.join(", ")}"
        end

        if ["metric alert", "query alert"].include?(type)
          interval = data.fetch(:query)[/\(last_(\S+?)\)/, 1]
          unless QUERY_INTERVALS.include?(interval)
            raise "#{tracking_id} query interval was #{interval}, but must be one of #{QUERY_INTERVALS.join(", ")}"
          end
        end
      end
    end
  end
end
