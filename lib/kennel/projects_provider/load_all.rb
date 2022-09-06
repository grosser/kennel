# frozen_string_literal: true

module Kennel
  module ProjectsProvider
    class LoadAll
      def projects
        load_all
        Models::Project.recursive_subclasses.map(&:new)
      end

      private

      def load_all
        loader = Zeitwerk::Loader.new
        Dir.exist?("teams") && loader.push_dir("teams", namespace: Teams)
        Dir.exist?("parts") && loader.push_dir("parts")
        loader.setup
        loader.eager_load # TODO: this should not be needed but we see hanging CI processes when it's not added

        # TODO: also auto-load projects and update expected path too
        ["projects"].each do |folder|
          Dir["#{folder}/**/*.rb"].sort.each { |f| require "./#{f}" }
        end
      rescue NameError => e
        message = e.message
        raise unless klass = message[/uninitialized constant (.*)/, 1]

        # inverse of zeitwerk lib/zeitwerk/inflector.rb
        path = klass.gsub("::", "/").gsub(/([a-z])([A-Z])/, "\\1_\\2").downcase + ".rb"
        expected_path = (path.start_with?("teams/") ? path : "parts/#{path}")

        # TODO: prefer to raise a new exception with the old backtrace attacked
        e.define_singleton_method(:message) do
          "\n" + <<~MSG.gsub(/^/, "  ")
            #{message}
            Unable to load #{klass} from #{expected_path}
            - Option 1: rename the constant or the file it lives in, to make them match
            - Option 2: Use `require` or `require_relative` to load the constant
          MSG
        end

        raise
      end
    end
  end
end
