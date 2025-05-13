# frozen_string_literal: true
module Kennel
  class ProjectsProvider
    class AutoloadFailed < StandardError
    end

    # @return [Array<Models::Project>]
    #   All projects in the system. This is a slow operation.
    #   Use `projects` to get all projects in the system.
    def all_projects
      load_all
      Models::Project.recursive_subclasses.map(&:new)
    end

    # @return [Array<Models::Project>]
    #   All projects in the system. This is a slow operation.

    def projects
      load_all
      Models::Project.recursive_subclasses.map(&:new)
    end

    private

    # load_all's purpose is to "require" all the .rb files under './projects',
    # while allowing them to resolve reference to ./teams and ./parts via autoload
    def load_all
      # Zeitwerk rejects second and subsequent calls.
      # Even if we skip over the Zeitwerk part, the nature of 'require' is
      # one-way: ruby does not provide a mechanism to *un*require things.
      return if defined?(@@load_all) && @@load_all
      @@load_all = true

      loader = Zeitwerk::Loader.new
      Dir.exist?("teams") && loader.push_dir("teams", namespace: Teams)
      Dir.exist?("parts") && loader.push_dir("parts")

      if (autoload = ENV["AUTOLOAD_PROJECTS"]) && autoload != "false"
        loader.push_dir("projects")
        loader.setup

        if (project = ENV["PROJECT"]) # TODO: use project filter instead and also support TRACKING_ID
          # we support PROJECT being used for nested folders, to allow teams to easily group their projects
          # so when loading a project we need to find anything that could be a project source
          # sorting by name and nesting level to avoid confusion
          segments = project.tr("-", "_").split("_")
          search = /#{segments[0...-1].map { |p| "#{p}[_/]" }.join}#{segments[-1]}(\.rb|\/project\.rb|\/base\.rb)/

          projects_path = "#{File.expand_path("projects")}/"
          known_paths = loader.all_expected_cpaths.keys
          project_path = known_paths.select do |path|
            path.start_with?(projects_path) && path.match?(search)
          end.sort.min_by { |p| p.count("/") }
          if project_path
            require project_path
          elsif autoload != "abort"
            Kennel.err.puts(
              "No projects/ file matching #{search} found" \
              ", falling back to slow loading of all projects instead"
            )
            loader.eager_load
          else
            raise AutoloadFailed, "No projects/ file matching #{search} found"
          end
        else # all projects needed
          loader.eager_load
        end
      else # old style without autoload
        loader.setup
        loader.eager_load # TODO: this should not be needed but we see hanging CI processes when it's not added
        # TODO: also auto-load projects and update expected path too
        # but to do that we need to stop the pattern of having a class at the bottom of the project structure
        # and change to Module::Project + Module::Support
        # we need the extra sort so foo/bar.rb is loaded before foo/bar/baz.rb
        Dir["projects/**/*.rb"].sort.each { |f| require "./#{f}" } # rubocop:disable Lint/RedundantDirGlobSort
      end
    rescue NameError => e
      message = e.message
      raise unless (klass = message[/uninitialized constant (.*)/, 1])

      # inverse of zeitwerk lib/zeitwerk/inflector.rb
      project_path = klass.gsub("::", "/").gsub(/([a-z])([A-Z])/, "\\1_\\2").downcase + ".rb"
      expected_path = (project_path.start_with?("teams/") ? project_path : "parts/#{project_path}")

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
