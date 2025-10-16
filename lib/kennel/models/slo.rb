# frozen_string_literal: true
module Kennel
  module Models
    class Slo < Record
      include TagsValidation

      READONLY_ATTRIBUTES = [
        *superclass::READONLY_ATTRIBUTES,
        :type_id, :monitor_tags
      ].freeze
      TRACKING_FIELD = :description
      DEFAULTS = {
        description: nil,
        query: nil,
        groups: nil,
        monitor_ids: [],
        thresholds: []
      }.freeze

      settings :type, :description, :thresholds, :query, :tags, :monitor_ids, :monitor_tags, :name, :groups, :sli_specification, :timeframe

      defaults(
        tags: -> { @project.tags },
        query: -> { DEFAULTS.fetch(:query) },
        description: -> { DEFAULTS.fetch(:description) },
        monitor_ids: -> { DEFAULTS.fetch(:monitor_ids) },
        thresholds: -> { DEFAULTS.fetch(:thresholds) },
        groups: -> { DEFAULTS.fetch(:groups) },
        timeframe: -> { (thresholds || raise("no thresholds set")).dig(0, :timeframe) }
      )

      def build_json
        data = super.merge(
          name: "#{name}#{LOCK}",
          description: description,
          thresholds: thresholds,
          timeframe: timeframe,
          monitor_ids: monitor_ids,
          tags: tags,
          type: type
        )

        # we do not store the copy-pasted fields for warning_threshold and target_threshold, so insert them
        threshold =
          thresholds.detect { |t| t[:timeframe] == data[:timeframe] } ||
          raise("unable to find threshold with timeframe #{data[:timeframe]}")
        data[:warning_threshold] = threshold[:warning]
        data[:target_threshold] = threshold[:target]

        if type == "time_slice"
          data[:sli_specification] = sli_specification
        elsif (v = query)
          data[:query] = v
        end

        if (v = groups)
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
        url[/[?&]slo_id=([a-z\d]{10,})/, 1] || url[/\/slo\/([a-z\d]{10,})\/edit(\?|$)/, 1]
      end

      def resolve_linked_tracking_ids!(id_map, **args)
        return unless (ids = as_json[:monitor_ids]) # ignore_default can remove it
        as_json[:monitor_ids] = ids.map do |id|
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

        # remove copy-pasted value diff, if threshold changes these will also change
        [:warning_threshold, :target_threshold].each { |a| actual[a] = expected[a] }

        # tags come in a semi-random order and order is never updated
        expected[:tags]&.sort!
        actual[:tags].sort!

        ignore_default(expected, actual, DEFAULTS)
      end

      private

      def validate_json(data)
        super

        # datadog does not allow uppercase tags for slos
        bad_tags = data[:tags].grep(/[A-Z]/)
        if bad_tags.any?
          invalid! :tags_are_upper_case, "Tags must not be upper case (bad tags: #{bad_tags.sort.inspect})"
        end

        # Check that thresholds are not empty
        if !data[:thresholds] || data[:thresholds].empty?
          invalid! :thresholds_empty, "SLO must have at least one threshold defined"
        end

        # prevent "Invalid payload: The target is incorrect: target must be a positive number between (0.0, 100.0)"
        data[:thresholds]&.each do |threshold|
          target = threshold.fetch(:target)
          if !target || target <= 0 || target >= 100
            invalid! :threshold_target_invalid, "SLO threshold target must be > 0 and < 100"
          end
        end

        # warning must be <= critical
        if data[:thresholds].any? { |t| t[:warning] && t[:warning].to_f <= t[:critical].to_f }
          invalid! :warning_must_be_gt_critical, "Threshold warning must be greater-than critical value"
        end
      end
    end
  end
end
