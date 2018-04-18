# frozen_string_literal: true
module Kennel
  module Models
    class Project < Base
      settings :team, :parts, :tags
      defaults(
        tags: -> { ["service:#{kennel_id}"] + team.tags }
      )

      def self.file_location
        @file_location ||= begin
          method_in_file = instance_methods(false).first
          instance_method(method_in_file).source_location.first.sub("#{Bundler.root}/", "")
        end
      end
    end
  end
end
