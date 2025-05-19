# frozen_string_literal: true
module Kennel
  class ProjectsProvider
    class AutoloadFailed < StandardError
    end

    def initialize(filter:)
      @filter = filter
    end

    # @return [Array<Models::Project>]
    #   All projects in the system. This is a slow operation.
    #   Use `projects` to get all projects in the system.
    def all_projects
      load_all
      loaded_projects.map(&:new)
    end

    # @return [Array<Models::Project>]
    #   All projects in the system. This is a slow operation.

    def projects
      load_all
      loaded_projects.map(&:new)
    end

    private

    def loaded_projects
      Models::Project.recursive_subclasses
    end

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

        if (projects = @filter.project_filter)
          projects_path = "#{File.expand_path("projects")}/"
          known_paths = loader.all_expected_cpaths.keys.select! { |path| path.start_with?(projects_path) }

          projects.each do |project|
            search = project_search project

            # sort by name and nesting level to pick the best candidate
            found = known_paths.grep(search).sort.sort_by { |path| path.count("/") }

            if found.any?
              require found.first
              assert_project_loaded search, found
            elsif autoload != "abort"
              Kennel.err.puts(
                "No projects/ file matching #{search} found, falling back to slow loading of all projects instead"
              )
              loader.eager_load
              break
            else
              raise AutoloadFailed, "No projects/ file matching #{search} found"
            end
          end
        else
          # all projects needed
          loader.eager_load
        end
      else
        # old style without autoload to be removed eventually
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

    # - support PROJECT being used for nested folders, to allow teams to easily group their projects
    # - support PROJECT.rb but also PROJECT/base.rb or PROJECT/project.rb
    def project_search(project)
      suffixes = ["base.rb", "project.rb"]
      project_match = Regexp.escape(project.tr("-", "_")).gsub("_", "[-_/]")
      /\/#{project_match}(\.rb|#{suffixes.map { |s| Regexp.escape "/#{s}" }.join("|")})$/
    end

    def assert_project_loaded(search, paths)
      return if loaded_projects.any?
      paths = paths.map { |path| path.sub("#{Dir.pwd}/", "") }
      raise(
        AutoloadFailed,
        <<~MSG
          No project found in loaded files!
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
  end
end
