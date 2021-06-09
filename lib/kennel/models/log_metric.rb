# frozen_string_literal: true

module Kennel
  module Models
    class LogMetric < Record
      VIRTUAL_ID = true

      settings(:metric, :query, :group_by, :aggregation_type, :aggregation_path)

      defaults(
        group_by: -> { [] },
        aggregation_type: -> { "count" },
        aggregation_path: -> { nil }
      )

      # log metrics don't have any free-text description/message, so we stuff the tracking id into the query
      TRACKING_FIELD = [:attributes, :filter, :query].freeze
      TRACKING_REGEX = /-managed_by_kennel:"(\S+)"/

      class << self
        def api_resource
          "logs/config/metrics"
        end

        def parse_tracking_id(a)
          a.dig(*TRACKING_FIELD).to_s[TRACKING_REGEX, 1]
        end

        def remove_tracking_id(a)
          value = a.dig(*TRACKING_FIELD)
          value.sub!(TRACKING_REGEX, "") ||
            raise("did not find tracking id in #{value}")
        end

        def url(id)
          Utils.path_to_url "/logs/pipelines/generate-metrics/#{id}"
        end
      end

      def id
        metric
      end

      def as_json
        return @as_json if @as_json
        data = {
          id: metric,
          type: 'logs_metrics',
          attributes: {
            filter: {
              query: query.dup # unfreeze
            },
            group_by: group_by,
            compute: {
              aggregation_type: aggregation_type
            }
          }
        }

        if aggregation_type == "distribution"
          data[:attributes][:compute][:path] = aggregation_path
        end

        @as_json = data
      end

      def add_tracking_id
        json = as_json
        if self.class.parse_tracking_id(json)
          invalid! "remove \"-managed_by_kennel\" portion from query to copy a resource"
        end
        json.dig(*TRACKING_FIELD).replace(json.dig(*TRACKING_FIELD) + " -managed_by_kennel:\"#{tracking_id}\"")
      end
    end
  end
end
