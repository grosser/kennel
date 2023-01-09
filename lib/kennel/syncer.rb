# frozen_string_literal: true

module Kennel
  class Syncer
    DELETE_ORDER = ["dashboard", "slo", "monitor", "synthetics/tests"].freeze # dashboards references monitors + slos, slos reference monitors
    LINE_UP = "\e[1A\033[K" # go up and clear

    Plan = Struct.new(:changes, keyword_init: true)
    Change = Struct.new(:type, :api_resource, :tracking_id, :id)

    def initialize(api, expected, actual, strict_imports: true, project_filter: nil, tracking_id_filter: nil)
      @api = api
      @strict_imports = strict_imports
      @project_filter = project_filter
      @tracking_id_filter = tracking_id_filter

      @resolver = Resolver.new(expected: expected, project_filter: @project_filter, tracking_id_filter: @tracking_id_filter)

      calculate_changes(expected: expected, actual: actual)
      validate_changes

      @warnings.each { |message| Kennel.out.puts Console.color(:yellow, "Warning: #{message}") }
    end

    def plan
      Plan.new(
        changes: (@create + @update + @delete).map(&:change)
      )
    end

    def print_plan
      PlanDisplayer.new.display(@create, @update, @delete)
    end

    def confirm
      return false if noop?
      return true if ENV["CI"] || !STDIN.tty? || !Kennel.err.tty?
      Console.ask?("Execute Plan ?")
    end

    def update
      changes = []

      @delete.each do |item|
        message = "#{item.api_resource} #{item.tracking_id} #{item.id}"
        Kennel.out.puts "Deleting #{message}"
        @api.delete item.api_resource, item.id
        changes << item.change
        Kennel.out.puts "#{LINE_UP}Deleted #{message}"
      end

      resolver.each_resolved @create do |item|
        message = "#{item.api_resource} #{item.tracking_id}"
        Kennel.out.puts "Creating #{message}"
        reply = @api.create item.api_resource, item.expected.as_json
        id = reply.fetch(:id)
        changes << item.change(id)
        resolver.add_actual [reply] # allow resolving ids we could previously not resolve
        Kennel.out.puts "#{LINE_UP}Created #{message} #{item.url(id)}"
      end

      resolver.each_resolved @update do |item|
        message = "#{item.api_resource} #{item.tracking_id} #{item.url}"
        Kennel.out.puts "Updating #{message}"
        @api.update item.api_resource, item.id, item.expected.as_json
        changes << item.change
        Kennel.out.puts "#{LINE_UP}Updated #{message}"
      end

      Plan.new(changes: changes)
    end

    private

    attr_reader :resolver

    def noop?
      @create.empty? && @update.empty? && @delete.empty?
    end

    def calculate_changes(expected:, actual:)
      @warnings = []

      Progress.progress "Diffing" do
        resolver.add_actual actual
        filter_actual! actual
        resolver.resolve_as_much_as_possible(expected) # resolve as many dependencies as possible to reduce the diff

        # see which expected match the actual
        matching, unmatched_expected, unmatched_actual = MatchedExpected.partition(expected, actual)
        validate_expected_id_not_missing unmatched_expected
        fill_details! matching # need details to diff later

        # update matching if needed
        @update = matching.map do |e, a|
          # Refuse to "adopt" existing items into kennel while running with a filter (i.e. on a branch).
          # Without this, we'd adopt an item, then the next CI run would delete it
          # (instead of "unadopting" it).
          e.add_tracking_id unless @project_filter && a.fetch(:tracking_id).nil?
          id = a.fetch(:id)
          diff = e.diff(a)
          a[:id] = id
          Types::PlannedUpdate.new(e, a, diff) if diff.any?
        end.compact

        # delete previously managed
        @delete = unmatched_actual.map { |a| Types::PlannedDelete.new(a) if a.fetch(:tracking_id) }.compact

        # unmatched expected need to be created
        unmatched_expected.each(&:add_tracking_id)
        @create = unmatched_expected.map { |e| Types::PlannedCreate.new(e) }

        # order to avoid deadlocks
        @delete.sort_by! { |item| DELETE_ORDER.index item.api_resource }
        @update.sort_by! { |item| DELETE_ORDER.index item.api_resource } # slo needs to come before slo alert
      end
    end

    # fill details of things we need to compare
    def fill_details!(details_needed)
      details_needed = details_needed.map { |e, a| a if e && e.class.api_resource == "dashboard" }.compact
      @api.fill_details! "dashboard", details_needed
    end

    def validate_expected_id_not_missing(expected)
      expected.each do |e|
        next unless id = e.id
        resource = e.class.api_resource
        if @strict_imports
          raise "Unable to find existing #{resource} with id #{id}\nIf the #{resource} was deleted, remove the `id: -> { #{id} }` line."
        else
          @warnings << "#{resource} #{e.tracking_id} specifies id #{id}, but no such #{resource} exists. 'id' will be ignored. Remove the `id: -> { #{id} }` line."
        end
      end
    end

    # We've already validated the desired objects ('generated') in isolation.
    # Now that we have made the plan, we can perform some more validation.
    def validate_changes
      @update.each do |item|
        item.expected.validate_update!(item.diff)
      end
    end

    def filter_actual!(actual)
      if @tracking_id_filter
        actual.select! do |a|
          tracking_id = a.fetch(:tracking_id)
          !tracking_id || @tracking_id_filter.include?(tracking_id)
        end
      elsif @project_filter
        project_prefixes = @project_filter.map { |p| "#{p}:" }
        actual.select! do |a|
          tracking_id = a.fetch(:tracking_id)
          !tracking_id || tracking_id.start_with?(*project_prefixes)
        end
      end
    end

    class PlanDisplayer
      def initialize
        @attribute_differ = AttributeDiffer.new
      end

      def display(create, update, delete)
        Kennel.out.puts "Plan:"
        if create.empty? && update.empty? && delete.empty?
          Kennel.out.puts Console.color(:green, "Nothing to do")
        else
          print_changes "Create", create, :green
          print_changes "Update", update, :yellow
          print_changes "Delete", delete, :red
        end
      end

      private

      def print_changes(step, list, color)
        return if list.empty?
        list.each do |item|
          Kennel.out.puts Console.color(color, "#{step} #{item.api_resource} #{item.tracking_id}")
          if item.class::TYPE == :update
            item.diff.each { |args| Kennel.out.puts @attribute_differ.format(*args) } # only for update
          end
        end
      end
    end

    class Resolver
      def initialize(expected:, project_filter:, tracking_id_filter:)
        @id_map = IdMap.new
        @project_filter = project_filter
        @tracking_id_filter = tracking_id_filter

        # mark everything as new
        expected.each do |e|
          id_map.set(e.class.api_resource, e.tracking_id, IdMap::NEW)
          if e.class.api_resource == "synthetics/tests"
            id_map.set(Kennel::Models::Monitor.api_resource, e.tracking_id, IdMap::NEW)
          end
        end
      end

      def add_actual(actual)
        # override resources that exist with their id
        project_prefixes = project_filter&.map { |p| "#{p}:" }

        actual.each do |a|
          # ignore when not managed by kennel
          next unless tracking_id = a.fetch(:tracking_id)

          # ignore when deleted from the codebase
          # (when running with filters we cannot see the other resources in the codebase)
          api_resource = a.fetch(:klass).api_resource
          next if
            !id_map.get(api_resource, tracking_id) &&
            (!project_prefixes || tracking_id.start_with?(*project_prefixes)) &&
            (!tracking_id_filter || tracking_id_filter.include?(tracking_id))

          id_map.set(api_resource, tracking_id, a.fetch(:id))
          if a.fetch(:klass).api_resource == "synthetics/tests"
            id_map.set(Kennel::Models::Monitor.api_resource, tracking_id, a.fetch(:monitor_id))
          end
        end
      end

      def resolve_as_much_as_possible(expected)
        expected.each do |e|
          e.resolve_linked_tracking_ids!(id_map, force: false)
        end
      end

      # loop over items until everything is resolved or crash when we get stuck
      # this solves cases like composite monitors depending on each other or monitor->monitor slo->slo monitor chains
      def each_resolved(list)
        list = list.dup
        loop do
          return if list.empty?
          list.reject! do |item|
            if resolved?(item.expected)
              yield item
              true
            else
              false
            end
          end ||
            assert_resolved(list[0].expected) # resolve something or show a circular dependency error
        end
      end

      private

      attr_reader :id_map, :project_filter, :tracking_id_filter

      # TODO: optimize by storing an instance variable if already resolved
      def resolved?(e)
        assert_resolved e
        true
      rescue UnresolvableIdError
        false
      end

      # raises UnresolvableIdError when not resolved
      def assert_resolved(e)
        e.resolve_linked_tracking_ids!(id_map, force: true)
      end
    end

    module MatchedExpected
      class << self
        def partition(expected, actual)
          lookup_map = matching_expected_lookup_map(expected)
          unmatched_expected = Set.new(expected) # for efficient deletion
          unmatched_actual = []
          matched = []
          actual.each do |a|
            e = matching_expected(a, lookup_map)
            if e && unmatched_expected.delete?(e)
              matched << [e, a]
            else
              unmatched_actual << a
            end
          end.compact
          [matched, unmatched_expected.to_a, unmatched_actual]
        end

        private

        # index list by all the thing we look up by: tracking id and actual id
        def matching_expected_lookup_map(expected)
          expected.each_with_object({}) do |e, all|
            keys = [e.tracking_id]
            keys << "#{e.class.api_resource}:#{e.id}" if e.id
            keys.compact.each do |key|
              raise "Lookup #{key} is duplicated" if all[key]
              all[key] = e
            end
          end
        end

        def matching_expected(a, map)
          klass = a.fetch(:klass)
          map["#{klass.api_resource}:#{a.fetch(:id)}"] || map[a.fetch(:tracking_id)]
        end
      end
    end

    module Types
      class PlannedChange
        def initialize(klass, tracking_id)
          @klass = klass
          @tracking_id = tracking_id
        end

        def api_resource
          klass.api_resource
        end

        def url(id = nil)
          klass.url(id || self.id)
        end

        def change(id = nil)
          Change.new(self.class::TYPE, api_resource, tracking_id, id)
        end

        attr_reader :klass, :tracking_id
      end

      class PlannedCreate < PlannedChange
        TYPE = :create

        def initialize(expected)
          super(expected.class, expected.tracking_id)
          @expected = expected
        end

        attr_reader :expected
      end

      class PlannedUpdate < PlannedChange
        TYPE = :update

        def initialize(expected, actual, diff)
          super(expected.class, expected.tracking_id)
          @expected = expected
          @actual = actual
          @diff = diff
          @id = actual.fetch(:id)
        end

        def change
          super(id)
        end

        attr_reader :expected, :actual, :diff, :id
      end

      class PlannedDelete < PlannedChange
        TYPE = :delete

        def initialize(actual)
          super(actual.fetch(:klass), actual.fetch(:tracking_id))
          @actual = actual
          @id = actual.fetch(:id)
        end

        def change
          super(id)
        end

        attr_reader :actual, :id
      end
    end
  end
end
