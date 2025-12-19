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
        if (location = instance_methods(false).first)
          @file_location = force_relative_path(instance_method(location).source_location.first)
        else
          @file_location = nil
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

      private_class_method def self.force_relative_path(path)
        return path unless File.absolute_path?(path)
        path.dup.sub!("#{Bundler.root}/", "") ||
        path.dup.sub!("#{Dir.pwd}/", "") ||
        raise("Unable to make path #{path} relative with bundler root #{Bundler.root} or pwd #{Dir.pwd}")
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
