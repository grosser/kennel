# frozen_string_literal: true
module Kennel
  class ProjectsProvider
    class AutoloadFailed < StandardError
    end

    def initialize(filter:)
      @filter = filter
    end

    # @return [Array<Models::Project>]
    #   All requested projects. This is a slow operation when loading all projects.
    def projects
      load_requested
      loaded_projects.map(&:new)
    end

    private

    def loaded_projects
      Models::Project.recursive_subclasses.reject(&:abstract_class?)
    end

    # "require" requested .rb files under './projects',
    # while allowing them to resolve reference to ./teams and ./parts via autoload
    def load_requested
      return if ensure_load_once!
      loader = setup_zeitwerk_loader
      if (projects = @filter.project_filter)
        known_paths = zeitwerk_known_paths(loader)
        projects.each do |project|
          search = project_search project
          found = sort_paths(known_paths.grep(search))
          if found.any?
            require found.first
            assert_project_loaded search, found
          else
            raise AutoloadFailed, "Unable to load #{project} since there are no projects/ files matching #{search}"
          end
        end
      else # load everything
        loader.eager_load force: true
      end
    rescue NameError => e # improve error message when file does not match constant
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

    def setup_zeitwerk_loader
      loader = Zeitwerk::Loader.new
      Dir.exist?("teams") && loader.push_dir("teams", namespace: Teams)
      Dir.exist?("parts") && loader.push_dir("parts")
      loader.push_dir("projects")
      loader.setup
      loader
    end

    # Zeitwerk rejects subsequent calls.
    # Even if we skip over the Zeitwerk part, the nature of 'require' is
    # one-way: ruby does not provide a mechanism to *un*require things.
    def ensure_load_once!
      return true if defined?(@@loaded) && @@loaded
      @@loaded = true
      false
    end

    def zeitwerk_known_paths(loader)
      projects_path = "#{File.expand_path("projects")}/"
      loader.all_expected_cpaths.keys.select! { |path| path.start_with?(projects_path) }
    end

    # - support PROJECT being used for nested folders, to allow teams to easily group their projects
    # - support PROJECT.rb but also PROJECT/base.rb or PROJECT/project.rb
    def project_search(project)
      suffixes = ["base.rb", "project.rb"]
      project_match = Regexp.escape(project.tr("-", "_")).gsub("_", "[-_/]")
      /\/#{project_match}(\.rb|#{suffixes.map { |s| Regexp.escape "/#{s}" }.join("|")})$/
    end

    # keep message in sync with logic in sort_paths
    def assert_project_loaded(search, paths)
      return if loaded_projects.any?
      paths = paths.map { |path| path.sub("#{Dir.pwd}/", "") }
      raise(
        AutoloadFailed,
        <<~MSG
          No project found in loaded files! (no class inheriting from Kennel::Models::Project)
          Ensure the project file you want to load is first in the list,
          list is sorted alphabetically and by nesting level.

          Loaded:
          #{paths.first}
          After finding:
          #{paths.join("\n")}
          With regex:
          #{search}
        MSG
      )
    end

    # sort by name and nesting level to pick the best candidate
    # keep logic in sync with message in assert_project_loaded
    def sort_paths(paths)
      paths.sort.sort_by { |path| path.count("/") }
    end
  end
end
