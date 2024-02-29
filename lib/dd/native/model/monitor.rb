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

        # Options:
        # audit alert
        #        1   10%  notify_no_data
        #       10  100%  all
        #        1   10%  require_full_window
        #        1   10%  include_tags
        #        1   10%  locked
        #        1   10%  thresholds
        #        1   10%  notify_by
        #        1   10%  notify_audit
        #        1   10%  new_host_delay
        #        1   10%  groupby_simple_monitor
        #        1   10%  silenced
        #
        # ci-tests alert
        #        1    7%  thresholds
        #       13  100%  all
        #        1    7%  enable_logs_sample
        #        1    7%  notify_audit
        #        1    7%  on_missing_data
        #        1    7%  include_tags
        #        1    7%  variables
        #        1    7%  renotify_interval
        #        1    7%  renotify_statuses
        #        1    7%  escalation_message
        #        1    7%  new_host_delay
        #        1    7%  renotify_occurrences
        #        1    7%  groupby_simple_monitor
        #        1    7%  silenced
        #
        # composite
        #      318   13%  notify_audit
        #     2408  100%  all
        #      245   10%  locked
        #      318   13%  include_tags
        #      318   13%  new_host_delay
        #      318   13%  notify_no_data
        #      124    5%  renotify_interval
        #       89    3%  escalation_message
        #      318   13%  silenced
        #       55    2%  thresholds
        #      219    9%  require_full_window
        #        7    0%  threshold_windows
        #        3    0%  renotify_statuses
        #       58    2%  timeout_h
        #       12    0%  no_data_timeframe
        #        3    0%  evaluation_delay
        #        3    0%  variables
        #
        # error-tracking alert
        #       13   10%  notify_audit
        #      119  100%  all
        #        5    4%  enable_logs_sample
        #       13   10%  thresholds
        #       13   10%  new_host_delay
        #       10    8%  notify_no_data
        #       13   10%  include_tags
        #       13   10%  groupby_simple_monitor
        #        5    4%  restriction_query
        #       13   10%  silenced
        #        8    6%  require_full_window
        #        8    6%  locked
        #        3    2%  on_missing_data
        #        2    1%  notify_by
        #
        # event-v2 alert
        #      348    9%  notify_no_data
        #     3838  100%  all
        #      264    6%  require_full_window
        #      389   10%  include_tags
        #      286    7%  locked
        #      347    9%  thresholds
        #      389   10%  notify_audit
        #      352    9%  new_host_delay
        #      389   10%  groupby_simple_monitor
        #      389   10%  silenced
        #      128    3%  enable_logs_sample
        #       45    1%  new_group_delay
        #      125    3%  restriction_query
        #       62    1%  on_missing_data
        #      124    3%  renotify_interval
        #        9    0%  renotify_statuses
        #       39    1%  escalation_message
        #      104    2%  timeout_h
        #       26    0%  evaluation_delay
        #       20    0%  variables
        #        1    0%  renotify_occurrences
        #        2    0%  notify_by
        #
        # log alert
        #      855    9%  notify_audit
        #     8708  100%  all
        #      483    5%  locked
        #      145    1%  timeout_h
        #      855    9%  include_tags
        #      849    9%  thresholds
        #      542    6%  require_full_window
        #      789    9%  new_host_delay
        #      668    7%  notify_no_data
        #      221    2%  renotify_interval
        #      530    6%  enable_logs_sample
        #      102    1%  queryConfig
        #       22    0%  no_data_timeframe
        #      102    1%  aggregation
        #      855    9%  silenced
        #      253    2%  restriction_query
        #      191    2%  on_missing_data
        #      818    9%  groupby_simple_monitor
        #      136    1%  escalation_message
        #       68    0%  new_group_delay
        #       68    0%  evaluation_delay
        #       45    0%  renotify_statuses
        #       61    0%  scheduling_options
        #        8    0%  notification_preset_name
        #       36    0%  variables
        #        1    0%  renotify_occurrences
        #        5    0%  group_retention_duration
        #
        # metric alert
        #      938   10%  notify_no_data
        #     9012  100%  all
        #      938   10%  notify_audit
        #      493    5%  timeout_h
        #      938   10%  silenced
        #      459    5%  no_data_timeframe
        #      624    6%  renotify_interval
        #      387    4%  escalation_message
        #        4    0%  is_data_sparse
        #      544    6%  locked
        #      857    9%  require_full_window
        #      791    8%  thresholds
        #        1    0%  period
        #      880    9%  new_host_delay
        #      892    9%  include_tags
        #        3    0%  synthetics_check_id
        #      171    1%  evaluation_delay
        #       64    0%  new_group_delay
        #       10    0%  renotify_occurrences
        #       10    0%  renotify_statuses
        #        8    0%  notification_preset_name
        #
        # process alert
        #        8   10%  include_tags
        #       75  100%  all
        #        4    5%  locked
        #        6    8%  new_host_delay
        #        4    5%  no_data_timeframe
        #        8   10%  notify_audit
        #        7    9%  notify_no_data
        #        6    8%  require_full_window
        #        8   10%  thresholds
        #        8   10%  silenced
        #        3    4%  timeout_h
        #        5    6%  renotify_interval
        #        4    5%  escalation_message
        #        2    2%  new_group_delay
        #        1    1%  renotify_statuses
        #        1    1%  on_missing_data
        #
        # query alert
        #    13878   10%  notify_no_data
        #   127915  100%  all
        #    13878   10%  notify_audit
        #     3490    2%  timeout_h
        #    13878   10%  silenced
        #    11526    9%  locked
        #    13831   10%  include_tags
        #    13856   10%  thresholds
        #    13735   10%  require_full_window
        #    11503    8%  new_host_delay
        #     4176    3%  renotify_interval
        #     2676    2%  escalation_message
        #     3884    3%  no_data_timeframe
        #     2297    1%  evaluation_delay
        #     2507    1%  new_group_delay
        #      123    0%  notify_by
        #     1161    0%  renotify_statuses
        #      124    0%  renotify_occurrences
        #      477    0%  threshold_windows
        #       13    0%  synthetics_check_id
        #       54    0%  notification_preset_name
        #      844    0%  variables
        #        4    0%  scheduling_options
        #
        # rum alert
        #       21   10%  notify_audit
        #      206  100%  all
        #        1    0%  locked
        #       17    8%  new_host_delay
        #       21   10%  enable_logs_sample
        #       21   10%  thresholds
        #        1    0%  queryConfig
        #        1    0%  aggregation
        #        4    1%  notify_no_data
        #       21   10%  include_tags
        #       21   10%  groupby_simple_monitor
        #       18    8%  restriction_query
        #       21   10%  silenced
        #       19    9%  on_missing_data
        #        5    2%  escalation_message
        #        6    2%  variables
        #        4    1%  new_group_delay
        #        1    0%  renotify_statuses
        #        1    0%  renotify_interval
        #        1    0%  renotify_occurrences
        #        1    0%  evaluation_delay
        #
        # service check
        #      995   11%  include_tags
        #     8724  100%  all
        #      905   10%  new_host_delay
        #      995   11%  notify_no_data
        #      194    2%  renotify_interval
        #      949   10%  require_full_window
        #      995   11%  thresholds
        #      995   11%  notify_audit
        #      995   11%  silenced
        #      916   10%  locked
        #      162    1%  timeout_h
        #      201    2%  no_data_timeframe
        #      132    1%  escalation_message
        #       96    1%  new_group_delay
        #       88    1%  evaluation_delay
        #       22    0%  renotify_statuses
        #        3    0%  notification_preset_name
        #        5    0%  threshold_windows
        #       76    0%  variables
        #
        # slo alert
        #     1397   11%  notify_audit
        #    11660  100%  all
        #      913    7%  locked
        #     1397   11%  include_tags
        #     1397   11%  thresholds
        #     1397   11%  new_host_delay
        #     1397   11%  notify_no_data
        #      234    2%  renotify_interval
        #     1397   11%  silenced
        #      204    1%  escalation_message
        #     1302   11%  require_full_window
        #       30    0%  renotify_statuses
        #      140    1%  timeout_h
        #      179    1%  no_data_timeframe
        #        4    0%  renotify_occurrences
        #      136    1%  evaluation_delay
        #      136    1%  variables
        #
        # trace-analytics alert
        #      239    8%  notify_audit
        #     2733  100%  all
        #      134    4%  timeout_h
        #      197    7%  enable_logs_sample
        #      239    8%  thresholds
        #      233    8%  new_host_delay
        #      186    6%  notify_no_data
        #      239    8%  include_tags
        #      183    6%  groupby_simple_monitor
        #      165    6%  renotify_interval
        #       66    2%  restriction_query
        #      239    8%  silenced
        #       44    1%  require_full_window
        #      171    6%  locked
        #      121    4%  queryConfig
        #      121    4%  aggregation
        #       27    0%  no_data_timeframe
        #       53    1%  on_missing_data
        #       27    0%  evaluation_delay
        #       31    1%  escalation_message
        #        6    0%  new_group_delay
        #        4    0%  notification_preset_name
        #        3    0%  renotify_statuses
        #        5    0%  variables

        # {:all=>{"notify_no_data"=>18750, :all=>175421, "notify_audit"=>19053, "timeout_h"=>4729, "silenced"=>19053, "no_data_timeframe"=>4788, "renotify_interval"=>5869, "escalation_message"=>3704, "locked"=>15098, "include_tags"=>18960, "thresholds"=>18573, "require_full_window"=>17927, "new_host_delay"=>16415, "is_data_sparse"=>4, "evaluation_delay"=>2817, "period"=>1, "new_group_delay"=>2792, "notify_by"=>128, "renotify_statuses"=>1286, "renotify_occurrences"=>142, "threshold_windows"=>489, "synthetics_check_id"=>16, "notification_preset_name"=>77, "enable_logs_sample"=>882, "queryConfig"=>224, "aggregation"=>224, "restriction_query"=>467, "on_missing_data"=>330, "groupby_simple_monitor"=>1426, "scheduling_options"=>65, "variables"=>1127, "group_retention_duration"=>5}, "query alert"=>{"notify_no_data"=>13878, :all=>127915, "notify_audit"=>13878, "timeout_h"=>3490, "silenced"=>13878, "locked"=>11526, "include_tags"=>13831, "thresholds"=>13856, "require_full_window"=>13735, "new_host_delay"=>11503, "renotify_interval"=>4176, "escalation_message"=>2676, "no_data_timeframe"=>3884, "evaluation_delay"=>2297, "new_group_delay"=>2507, "notify_by"=>123, "renotify_statuses"=>1161, "renotify_occurrences"=>124, "threshold_windows"=>477, "synthetics_check_id"=>13, "notification_preset_name"=>54, "variables"=>844, "scheduling_options"=>4}, "metric alert"=>{"notify_no_data"=>938, :all=>9012, "notify_audit"=>938, "timeout_h"=>493, "silenced"=>938, "no_data_timeframe"=>459, "renotify_interval"=>624, "escalation_message"=>387, "is_data_sparse"=>4, "locked"=>544, "require_full_window"=>857, "thresholds"=>791, "period"=>1, "new_host_delay"=>880, "include_tags"=>892, "synthetics_check_id"=>3, "evaluation_delay"=>171, "new_group_delay"=>64, "renotify_occurrences"=>10, "renotify_statuses"=>10, "notification_preset_name"=>8}, "service check"=>{"include_tags"=>995, :all=>8724, "new_host_delay"=>905, "notify_no_data"=>995, "renotify_interval"=>194, "require_full_window"=>949, "thresholds"=>995, "notify_audit"=>995, "silenced"=>995, "locked"=>916, "timeout_h"=>162, "no_data_timeframe"=>201, "escalation_message"=>132, "new_group_delay"=>96, "evaluation_delay"=>88, "renotify_statuses"=>22, "notification_preset_name"=>3, "threshold_windows"=>5, "variables"=>76}, "composite"=>{"notify_audit"=>318, :all=>2408, "locked"=>245, "include_tags"=>318, "new_host_delay"=>318, "notify_no_data"=>318, "renotify_interval"=>124, "escalation_message"=>89, "silenced"=>318, "thresholds"=>55, "require_full_window"=>219, "threshold_windows"=>7, "renotify_statuses"=>3, "timeout_h"=>58, "no_data_timeframe"=>12, "evaluation_delay"=>3, "variables"=>3}, "process alert"=>{"include_tags"=>8, :all=>75, "locked"=>4, "new_host_delay"=>6, "no_data_timeframe"=>4, "notify_audit"=>8, "notify_no_data"=>7, "require_full_window"=>6, "thresholds"=>8, "silenced"=>8, "timeout_h"=>3, "renotify_interval"=>5, "escalation_message"=>4, "new_group_delay"=>2, "renotify_statuses"=>1, "on_missing_data"=>1}, "log alert"=>{"notify_audit"=>855, :all=>8708, "locked"=>483, "timeout_h"=>145, "include_tags"=>855, "thresholds"=>849, "require_full_window"=>542, "new_host_delay"=>789, "notify_no_data"=>668, "renotify_interval"=>221, "enable_logs_sample"=>530, "queryConfig"=>102, "no_data_timeframe"=>22, "aggregation"=>102, "silenced"=>855, "restriction_query"=>253, "on_missing_data"=>191, "groupby_simple_monitor"=>818, "escalation_message"=>136, "new_group_delay"=>68, "evaluation_delay"=>68, "renotify_statuses"=>45, "scheduling_options"=>61, "notification_preset_name"=>8, "variables"=>36, "renotify_occurrences"=>1, "group_retention_duration"=>5}, "trace-analytics alert"=>{"notify_audit"=>239, :all=>2733, "timeout_h"=>134, "enable_logs_sample"=>197, "thresholds"=>239, "new_host_delay"=>233, "notify_no_data"=>186, "include_tags"=>239, "groupby_simple_monitor"=>183, "renotify_interval"=>165, "restriction_query"=>66, "silenced"=>239, "require_full_window"=>44, "locked"=>171, "queryConfig"=>121, "aggregation"=>121, "no_data_timeframe"=>27, "on_missing_data"=>53, "evaluation_delay"=>27, "escalation_message"=>31, "new_group_delay"=>6, "notification_preset_name"=>4, "renotify_statuses"=>3, "variables"=>5}, "slo alert"=>{"notify_audit"=>1397, :all=>11660, "locked"=>913, "include_tags"=>1397, "thresholds"=>1397, "new_host_delay"=>1397, "notify_no_data"=>1397, "renotify_interval"=>234, "silenced"=>1397, "escalation_message"=>204, "require_full_window"=>1302, "renotify_statuses"=>30, "timeout_h"=>140, "no_data_timeframe"=>179, "renotify_occurrences"=>4, "evaluation_delay"=>136, "variables"=>136}, "rum alert"=>{"notify_audit"=>21, :all=>206, "locked"=>1, "new_host_delay"=>17, "enable_logs_sample"=>21, "thresholds"=>21, "queryConfig"=>1, "aggregation"=>1, "notify_no_data"=>4, "include_tags"=>21, "groupby_simple_monitor"=>21, "restriction_query"=>18, "silenced"=>21, "on_missing_data"=>19, "escalation_message"=>5, "variables"=>6, "new_group_delay"=>4, "renotify_statuses"=>1, "renotify_interval"=>1, "renotify_occurrences"=>1, "evaluation_delay"=>1}, "event-v2 alert"=>{"notify_no_data"=>348, :all=>3838, "require_full_window"=>264, "include_tags"=>389, "locked"=>286, "thresholds"=>347, "notify_audit"=>389, "new_host_delay"=>352, "groupby_simple_monitor"=>389, "silenced"=>389, "enable_logs_sample"=>128, "new_group_delay"=>45, "restriction_query"=>125, "on_missing_data"=>62, "renotify_interval"=>124, "renotify_statuses"=>9, "escalation_message"=>39, "timeout_h"=>104, "evaluation_delay"=>26, "variables"=>20, "renotify_occurrences"=>1, "notify_by"=>2}, "error-tracking alert"=>{"notify_audit"=>13, :all=>119, "enable_logs_sample"=>5, "thresholds"=>13, "new_host_delay"=>13, "notify_no_data"=>10, "include_tags"=>13, "groupby_simple_monitor"=>13, "restriction_query"=>5, "silenced"=>13, "require_full_window"=>8, "locked"=>8, "on_missing_data"=>3, "notify_by"=>2}, "audit alert"=>{"notify_no_data"=>1, :all=>10, "require_full_window"=>1, "include_tags"=>1, "locked"=>1, "thresholds"=>1, "notify_by"=>1, "notify_audit"=>1, "new_host_delay"=>1, "groupby_simple_monitor"=>1, "silenced"=>1}, "ci-tests alert"=>{"thresholds"=>1, :all=>13, "enable_logs_sample"=>1, "notify_audit"=>1, "on_missing_data"=>1, "include_tags"=>1, "variables"=>1, "renotify_interval"=>1, "renotify_statuses"=>1, "escalation_message"=>1, "new_host_delay"=>1, "renotify_occurrences"=>1, "groupby_simple_monitor"=>1, "silenced"=>1}}
      end
    end
  end
end
