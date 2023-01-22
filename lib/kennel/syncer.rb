# frozen_string_literal: true

require_relative "./syncer/matched_expected"
require_relative "./syncer/plan_displayer"
require_relative "./syncer/resolver"
require_relative "./syncer/types"

module Kennel
  class Syncer
    DELETE_ORDER = ["dashboard", "slo", "monitor", "synthetics/tests"].freeze # dashboards references monitors + slos, slos reference monitors
    LINE_UP = "\e[1A\033[K" # go up and clear

    Plan = Struct.new(:changes, keyword_init: true)

    InternalPlan = Struct.new(:creates, :updates, :deletes) do
      def empty?
        creates.empty? && updates.empty? && deletes.empty?
      end
    end

    Change = Struct.new(:type, :api_resource, :tracking_id, :id)

    def initialize(api, expected, actual, filter:, strict_imports: true)
      @api = api
      @strict_imports = strict_imports
      @filter = filter

      @resolver = Resolver.new(expected: expected, filter: filter)

      internal_plan = calculate_changes(expected: expected, actual: actual)
      validate_changes(internal_plan)
      @internal_plan = internal_plan

      @warnings.each { |message| Kennel.out.puts Console.color(:yellow, "Warning: #{message}") }
    end

    def plan
      ip = @internal_plan
      Plan.new(
        changes: (ip.creates + ip.updates + ip.deletes).map(&:change)
      )
    end

    def print_plan
      PlanDisplayer.new.display(internal_plan)
    end

    def confirm
      return false if internal_plan.empty?
      return true if ENV["CI"] || !STDIN.tty? || !Kennel.err.tty?
      Console.ask?("Execute Plan ?")
    end

    def update
      changes = []

      internal_plan.deletes.each do |item|
        message = "#{item.api_resource} #{item.tracking_id} #{item.id}"
        Kennel.out.puts "Deleting #{message}"
        @api.delete item.api_resource, item.id
        changes << item.change
        Kennel.out.puts "#{LINE_UP}Deleted #{message}"
      end

      resolver.each_resolved internal_plan.creates do |item|
        message = "#{item.api_resource} #{item.tracking_id}"
        Kennel.out.puts "Creating #{message}"
        reply = @api.create item.api_resource, item.expected.as_json
        id = reply.fetch(:id)
        changes << item.change(id)
        resolver.add_actual [reply] # allow resolving ids we could previously not resolve
        Kennel.out.puts "#{LINE_UP}Created #{message} #{item.url(id)}"
      end

      resolver.each_resolved internal_plan.updates do |item|
        message = "#{item.api_resource} #{item.tracking_id} #{item.url}"
        Kennel.out.puts "Updating #{message}"
        @api.update item.api_resource, item.id, item.expected.as_json
        changes << item.change
        Kennel.out.puts "#{LINE_UP}Updated #{message}"
      end

      Plan.new(changes: changes)
    end

    private

    attr_reader :filter, :resolver, :internal_plan

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
        updates = matching.map do |e, a|
          # Refuse to "adopt" existing items into kennel while running with a filter (i.e. on a branch).
          # Without this, we'd adopt an item, then the next CI run would delete it
          # (instead of "unadopting" it).
          e.add_tracking_id unless filter.project_filter && a.fetch(:tracking_id).nil?
          id = a.fetch(:id)
          diff = e.diff(a)
          a[:id] = id
          Types::PlannedUpdate.new(e, a, diff) if diff.any?
        end.compact

        # delete previously managed
        deletes = unmatched_actual.map { |a| Types::PlannedDelete.new(a) if a.fetch(:tracking_id) }.compact

        # unmatched expected need to be created
        unmatched_expected.each(&:add_tracking_id)
        creates = unmatched_expected.map { |e| Types::PlannedCreate.new(e) }

        # order to avoid deadlocks
        deletes.sort_by! { |item| DELETE_ORDER.index item.api_resource }
        updates.sort_by! { |item| DELETE_ORDER.index item.api_resource } # slo needs to come before slo alert

        InternalPlan.new(creates, updates, deletes)
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
    def validate_changes(internal_plan)
      internal_plan.updates.each do |item|
        item.expected.validate_update!(item.diff)
      end
    end

    def filter_actual!(actual)
      return if filter.project_filter.nil? # minor optimization

      actual.select! do |a|
        tracking_id = a.fetch(:tracking_id)
        tracking_id.nil? || filter.matches_tracking_id?(tracking_id)
      end
    end
  end
end
