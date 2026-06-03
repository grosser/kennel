# frozen_string_literal: true
module Kennel
  module Models
    class Project < Base
      settings :team, :parts, :tags, :mention, :name, :kennel_id
      defaults(
        tags: -> { team.tags },
        mention: -> { team.mention }
      )

      def self.file_location
        return @file_location if defined?(@file_location)
        methods = instance_methods(false)
        if methods.any?
          @file_location = methods.detect do |method|
            location = instance_method(method).source_location.first
            if (path = find_relative_path(location))
              break path
            end
          end || raise("Unable to find file_location for #{name}")
        else
          @file_location = nil # not sure if this is actually needed
        end
      end

      def validated_parts
        all = filter_parts(parts)
        unless all.is_a?(Array) && all.all? { |part| part.is_a?(Record) }
          raise "Project #{kennel_id} #parts must return an array of Records"
        end

        validate_parts(all)
        all
      end

      private

      private_class_method def self.find_relative_path(path)
        return path unless File.absolute_path?(path)
        path.dup.sub!("#{Bundler.root}/", "") || path.dup.sub!("#{Dir.pwd}/", "")
      end

      # hook for users to add custom filtering via `prepend`
      def filter_parts(parts)
        parts
      end

      # hook for users to add custom validations via `prepend`
      def validate_parts(parts)
      end
    end
  end
end
