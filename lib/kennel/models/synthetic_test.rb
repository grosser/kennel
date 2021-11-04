# frozen_string_literal: true
module Kennel
  module Models
    class SyntheticTest < Record
      TRACKING_FIELD = :message
      DEFAULTS = {
      }.freeze
      READONLY_ATTRIBUTES = superclass::READONLY_ATTRIBUTES + [:status, :monitor_id]
      LOCATIONS = ["aws:ca-central-1", "aws:eu-north-1", "aws:eu-west-1", "aws:eu-west-3", "aws:eu-west-2", "aws:ap-south-1", "aws:us-west-2", "aws:us-west-1", "aws:sa-east-1", "aws:us-east-2", "aws:ap-northeast-1", "aws:ap-northeast-2", "aws:eu-central-1", "aws:ap-southeast-2", "aws:ap-southeast-1"].freeze

      settings :tags, :config, :message, :subtype, :type, :name, :locations, :options

      defaults(
        id: -> { nil },
        tags: -> { @project.tags },
        message: -> { "\n\n#{project.mention}" }
      )

      def as_json
        return @as_json if @as_json
        locations = locations()
        data = {
          message: message,
          tags: tags,
          config: config,
          type: type,
          subtype: subtype,
          options: options,
          name: "#{name}#{LOCK}",
          locations: locations == :all ? LOCATIONS : locations
        }

        if v = id
          data[:id] = v
        end

        @as_json = data
      end

      def self.api_resource
        "synthetics/tests"
      end

      def self.url(id)
        Utils.path_to_url "/synthetics/details/#{id}"
      end

      def self.parse_url(url)
        url[/\/synthetics\/details\/([a-z\d-]{11,})/, 1] # id format is 1ab-2ab-3ab
      end

      def self.normalize(expected, actual)
        super

        # tags come in a semi-random order and order is never updated
        expected[:tags]&.sort!
        actual[:tags].sort!

        ignore_default(expected, actual, DEFAULTS)
      end
    end
  end
end
