# frozen_string_literal: true

module DD
  module Native
    class Model
      class Monitor < Model
        ID_NAMESPACE = "monitor"

        REQUIRED_KEYS = [
          "created", "created_at", "creator", "deleted", "id", "matching_downtimes", "message", "modified", "multi", "name", "options", "org_id", "overall_state", "overall_state_modified", "priority", "query", "restricted_roles", "tags", "type"
        ].freeze

        OPTIONAL_KEYS = [].freeze

        attr_reader *REQUIRED_KEYS, *OPTIONAL_KEYS

        require_relative "monitor/audit_alert"
        require_relative "monitor/ci_tests_alert"
        require_relative "monitor/composite"
        require_relative "monitor/error_tracking_alert"
        require_relative "monitor/event_v2_alert"
        require_relative "monitor/log_alert"
        require_relative "monitor/metric_alert"
        require_relative "monitor/process_alert"
        require_relative "monitor/query_alert"
        require_relative "monitor/rum_alert"
        require_relative "monitor/service_check"
        require_relative "monitor/slo_alert"
        require_relative "monitor/trace_analytics_alert"

        TYPE_MAP = {
          "audit alert": Monitor::AuditAlert,
          "ci-tests alert": Monitor::CITestsAlert,
          "composite": Monitor::Composite,
          "error-tracking alert": Monitor::ErrorTrackingAlert,
          "event-v2 alert": Monitor::EventV2Alert,
          "log alert": Monitor::LogAlert,
          "metric alert": Monitor::MetricAlert,
          "process alert": Monitor::ProcessAlert,
          "query alert": Monitor::QueryAlert,
          "rum alert": Monitor::RUMAlert,
          "service check": Monitor::ServiceCheck,
          "slo alert": Monitor::SLOAlert,
          "trace-analytics alert": Monitor::TraceAnalyticsAlert,
        }

        TYPE_FIELD = :type

        #  [DD::Native::Model::Monitor, "creator", Hash]=>19053,
        #  [DD::Native::Model::Monitor, "matching_downtimes", Array]=>19053,
        #  [DD::Native::Model::Monitor, "options", Hash]=>19053,
        #  [DD::Native::Model::Monitor, "tags", Array]=>19053,
        #  [DD::Native::Model::Monitor, "restricted_roles", Array]=>12,
      end
    end
  end
end
