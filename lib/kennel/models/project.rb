# frozen_string_literal: true
module Kennel
  module Models
    class Project < Base
      settings :team, :parts, :tags, :mention, :name, :kennel_id
      defaults(
        tags: -> { ["service:#{kennel_id}"] + team.tags },
        mention: -> { team.mention }
      )

      def self.file_location
        @file_location ||= begin
          method_in_file = instance_methods(false).first
          instance_method(method_in_file).source_location.first.sub("#{Bundler.root}/", "")
        end
      end

      def validated_parts
        all = parts
        validate_parts(all)
        all
      end

      private

      # hook for users to add custom validations via `prepend`
      def validate_parts(parts)
      end
    end
  end
end
