# frozen_string_literal: true
module Kennel
  module Models
    class Slo < Record
      READONLY_ATTRIBUTES = superclass::READONLY_ATTRIBUTES + [:type_id, :monitor_tags]
      DEFAULTS = {
        description: nil,
        query: nil,
        monitor_ids: []
      }.freeze

      settings :type, :description, :thresholds, :query, :tags, :monitor_ids, :monitor_tags, :name

      defaults(
        id: -> { nil },
        tags: -> { @project.tags },
        query: -> { DEFAULTS.fetch(:query) },
        description: -> { DEFAULTS.fetch(:description) },
        monitor_ids: -> { DEFAULTS.fetch(:monitor_ids) }
      )

      def as_json
        return @as_json if @as_json
        data = {
          name: "#{name}#{LOCK}",
          description: description,
          thresholds: thresholds,
          monitor_ids: monitor_ids,
          tags: tags,
          type: type
        }

        data[:query] = query if query
        data[:id] = id if id

        @as_json = data
      end

      def self.api_resource
        "slo"
      end

      def url(id)
        Utils.path_to_url "/slo?slo_id=#{id}"
      end

      def resolve_linked_tracking_ids(id_map)
        as_json[:monitor_ids] = as_json[:monitor_ids].map do |id|
          id.is_a?(String) ? resolve_link(id, id_map, force: false) || 1 : id
        end
      end

      def self.normalize(expected, actual)
        super

        # remove readonly values
        actual[:thresholds]&.each do |threshold|
          threshold.delete(:warning_display)
          threshold.delete(:target_display)
        end

        # tags come in a semi-random order and order is never updated
        expected[:tags]&.sort!
        actual[:tags].sort!

        ignore_default(expected, actual, DEFAULTS)
      end
    end
  end
end
