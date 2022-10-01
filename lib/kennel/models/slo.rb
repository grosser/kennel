# frozen_string_literal: true
module Kennel
  module Models
    class Slo < Record
      READONLY_ATTRIBUTES = superclass::READONLY_ATTRIBUTES + [:type_id, :monitor_tags]
      TRACKING_FIELD = :description
      DEFAULTS = {
        description: nil,
        query: nil,
        groups: nil,
        monitor_ids: [],
        thresholds: []
      }.freeze

      settings :type, :description, :thresholds, :query, :tags, :monitor_ids, :monitor_tags, :name, :groups

      defaults(
        id: -> { nil },
        tags: -> { @project.tags },
        query: -> { DEFAULTS.fetch(:query) },
        description: -> { DEFAULTS.fetch(:description) },
        monitor_ids: -> { DEFAULTS.fetch(:monitor_ids) },
        thresholds: -> { DEFAULTS.fetch(:thresholds) },
        groups: -> { DEFAULTS.fetch(:groups) }
      )

      def initialize(*)
        super
        if thresholds.any? { |t| t[:warning] && t[:warning].to_f <= t[:critical].to_f }
          raise ValidationError, "Threshold warning must be greater-than critical value"
        end
      end

      def as_json
        data = {
          name: "#{name}#{LOCK}",
          description: description,
          thresholds: thresholds,
          monitor_ids: monitor_ids,
          tags: tags.uniq,
          type: type
        }

        if v = query
          data[:query] = v
        end
        if v = id
          data[:id] = v
        end
        if v = groups
          data[:groups] = v
        end

        data
      end

      def self.api_resource
        "slo"
      end

      def self.url(id)
        Utils.path_to_url "/slo?slo_id=#{id}"
      end

      def self.parse_url(url)
        url[/\/slo(\?.*slo_id=|\/edit\/)([a-z\d]{10,})(&|$)/, 2]
      end

      def resolve_linked_tracking_ids!(id_map, **args)
        return unless ids = working_json[:monitor_ids] # ignore_default can remove it
        working_json[:monitor_ids] = ids.map do |id|
          resolve(id, :monitor, id_map, **args) || id
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
