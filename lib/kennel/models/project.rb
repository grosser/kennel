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
          return if method_in_file.nil?

          instance_method(method_in_file).source_location.first.sub("#{Bundler.root}/", "")
        end
      end

      def validated_parts(base_dir)
        all = parts
        unless all.is_a?(Array) && all.all? { |part| part.is_a?(Record) }
          invalid! "#parts must return an array of Records"
        end

        all.each { |part| part.strip_caller(base_dir) }
        validate_parts(all)
        all
      end

      private

      # let users know which project/resource failed when something happens during diffing where the backtrace is hidden
      def invalid!(message)
        raise ValidationError, "#{kennel_id} #{message}"
      end

      # hook for users to add custom validations via `prepend`
      def validate_parts(parts)
      end
    end
  end
end
