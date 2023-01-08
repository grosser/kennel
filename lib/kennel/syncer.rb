# frozen_string_literal: true

module Kennel
  class Syncer
    DELETE_ORDER = ["dashboard", "slo", "monitor", "synthetics/tests"].freeze # dashboards references monitors + slos, slos reference monitors
    LINE_UP = "\e[1A\033[K" # go up and clear

    Plan = Struct.new(:changes, keyword_init: true)
    Change = Struct.new(:type, :api_resource, :tracking_id, :id)

    def initialize(api, expected, actual, strict_imports: true, project_filter: nil, tracking_id_filter: nil)
      @api = api
      @expected = Set.new expected # need Set to speed up deletion
      @actual = actual
      @strict_imports = strict_imports
      @project_filter = project_filter
      @tracking_id_filter = tracking_id_filter

      @attribute_differ = AttributeDiffer.new

      calculate_changes
      validate_changes
      prevent_irreversible_partial_updates

      @warnings.each { |message| Kennel.out.puts Console.color(:yellow, "Warning: #{message}") }
    end

    def plan
      Plan.new(
        changes:
          @create.map { |_id, e, _a| Change.new(:create, e.class.api_resource, e.tracking_id, nil) } +
            @update.map { |id, e, _a| Change.new(:update, e.class.api_resource, e.tracking_id, id) } +
            @delete.map { |id, _e, a| Change.new(:delete, a.fetch(:klass).api_resource, a.fetch(:tracking_id), id) }
      )
    end

    def print_plan
      Kennel.out.puts "Plan:"
      if noop?
        Kennel.out.puts Console.color(:green, "Nothing to do")
      else
        print_changes "Create", @create, :green
        print_changes "Update", @update, :yellow
        print_changes "Delete", @delete, :red
      end
    end

    def confirm
      return false if noop?
      return true if ENV["CI"] || !STDIN.tty? || !Kennel.err.tty?
      Console.ask?("Execute Plan ?")
    end

    def update
      changes = []

      @delete.each do |id, _, a|
        klass = a.fetch(:klass)
        message = "#{klass.api_resource} #{a.fetch(:tracking_id)} #{id}"
        Kennel.out.puts "Deleting #{message}"
        @api.delete klass.api_resource, id
        changes << Change.new(:delete, klass.api_resource, a.fetch(:tracking_id), id)
        Kennel.out.puts "#{LINE_UP}Deleted #{message}"
      end

      @resolver.each_resolved @create do |_, e|
        message = "#{e.class.api_resource} #{e.tracking_id}"
        Kennel.out.puts "Creating #{message}"
        reply = @api.create e.class.api_resource, e.as_json
        id = reply.fetch(:id)
        changes << Change.new(:create, e.class.api_resource, e.tracking_id, id)
        @resolver.add_actual [reply] # allow resolving ids we could previously no resolve
        Kennel.out.puts "#{LINE_UP}Created #{message} #{e.class.url(id)}"
      end

      @resolver.each_resolved @update do |id, e|
        message = "#{e.class.api_resource} #{e.tracking_id} #{e.class.url(id)}"
        Kennel.out.puts "Updating #{message}"
        @api.update e.class.api_resource, id, e.as_json
        changes << Change.new(:update, e.class.api_resource, e.tracking_id, id)
        Kennel.out.puts "#{LINE_UP}Updated #{message}"
      end

      Plan.new(changes: changes)
    end

    private

    def noop?
      @create.empty? && @update.empty? && @delete.empty?
    end

    def calculate_changes
      @warnings = []
      @resolver = Resolver.new(expected: @expected, project_filter: @project_filter, tracking_id_filter: @tracking_id_filter)

      Progress.progress "Diffing" do
        @resolver.add_actual @actual
        filter_actual! @actual
        @resolver.resolve_linked_tracking_ids! @expected # resolve as many dependencies as possible to reduce the diff
        @expected.each(&:add_tracking_id) # avoid diff with actual, which has tracking_id

        # see which expected match the actual
        matching, unmatched_expected, unmatched_actual = MatchedExpected.partition(@expected, @actual)
        validate_expected_id_not_missing unmatched_expected
        fill_details! matching # need details to diff later

        # update matching if needed
        @update = matching.map do |e, a|
          id = a.fetch(:id)
          diff = e.diff(a)
          [id, e, a, diff] if diff.any?
        end.compact

        # delete previously managed
        @delete = unmatched_actual.map { |a| [a.fetch(:id), nil, a] if a.fetch(:tracking_id) }.compact

        # unmatched expected need to be created
        @create = unmatched_expected.map { |e| [nil, e] }

        # order to avoid deadlocks
        @delete.sort_by! { |_, _, a| DELETE_ORDER.index a.fetch(:klass).api_resource }
        @update.sort_by! { |_, e, _| DELETE_ORDER.index e.class.api_resource } # slo needs to come before slo alert
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

    def print_changes(step, list, color)
      return if list.empty?
      list.each do |_, e, a, diff|
        klass = (e ? e.class : a.fetch(:klass))
        Kennel.out.puts Console.color(color, "#{step} #{klass.api_resource} #{e&.tracking_id || a.fetch(:tracking_id)}")
        diff&.each { |args| Kennel.out.puts @attribute_differ.format(*args) } # only for update
      end
    end

    # We've already validated the desired objects ('generated') in isolation.
    # Now that we have made the plan, we can perform some more validation.
    def validate_changes
      @update.each do |_, expected, actuals, diffs|
        expected.validate_update!(actuals, diffs)
      end
    end

    # - do not add tracking-id when working with existing ids on a branch,
    #   so resource do not get deleted when running an update on master (for example merge->CI)
    # - ideally we'd never add tracking in the first place, but when adding tracking we do not know the diff yet
    def prevent_irreversible_partial_updates
      return unless @project_filter # full update, so we are not on a branch
      @update.select! do |_, e, _, diff| # ensure clean diff, by removing noop-update
        next true unless e.id # safe to add tracking when not having id

        diff.select! do |field_diff|
          (_, field, actual) = field_diff
          # TODO: refactor this so TRACKING_FIELD stays record-private
          next true if e.class::TRACKING_FIELD != field.to_sym # need to sym here because Hashdiff produces strings
          next true if e.class.parse_tracking_id(field.to_sym => actual) # already has tracking id

          field_diff[3] = e.remove_tracking_id # make `rake plan` output match what we are sending
          actual != field_diff[3] # discard diff if now nothing changes
        end

        diff.any?
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

      # loop over items until everything is resolved or crash when we get stuck
      # this solves cases like composite monitors depending on each other or monitor->monitor slo->slo monitor chains
      def each_resolved(list)
        list = list.dup
        loop do
          return if list.empty?
          list.reject! do |id, e|
            if resolved?(e)
              yield id, e
              true
            else
              false
            end
          end ||
            assert_resolved(list[0][1]) # resolve something or show a circular dependency error
        end
      end

      def resolve_linked_tracking_ids!(list, force: false)
        list.each { |e| e.resolve_linked_tracking_ids!(id_map, force: force) }
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
        resolve_linked_tracking_ids! [e], force: true
      end
    end

    module MatchedExpected
      class << self
        def partition(expected, actual)
          lookup_map = matching_expected_lookup_map(expected)
          unmatched_expected = expected.dup
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
          [matched, unmatched_expected, unmatched_actual]
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
  end
end
