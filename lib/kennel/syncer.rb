# frozen_string_literal: true

require_relative "syncer/matched_expected"
require_relative "syncer/plan"
require_relative "syncer/plan_printer"
require_relative "syncer/resolver"
require_relative "syncer/types"

module Kennel
  class Syncer
    DELETE_ORDER = ["dashboard", "slo", "monitor", "synthetics/tests"].freeze # dashboards references monitors + slos, slos reference monitors
    LINE_UP = "\e[1A\033[K" # go up and clear

    attr_reader :plan

    def initialize(api, expected, actual, filter:, strict_imports: true)
      @api = api
      @strict_imports = strict_imports
      @filter = filter

      @resolver = Resolver.new(expected: expected, filter: filter)
      @plan = Plan.new(*calculate_changes(expected: expected, actual: actual))
      validate_changes
    end

    def print_plan
      PlanPrinter.new.print(plan)
    end

    def confirm
      return false if plan.empty?
      return true unless Console.tty?
      Console.ask?("Execute Plan ?")
    end

    def update
      changes = []

      plan.deletes.each do |item|
        message = "#{item.api_resource} #{item.tracking_id} #{item.id}"
        Kennel.out.puts "Deleting #{message}"
        @api.delete item.api_resource, item.id
        changes << item.change
        Kennel.out.puts "#{LINE_UP}Deleted #{message}"
      end

      planned_actions = plan.creates + plan.updates

      # slos need to be updated first in case their timeframes changed
      # because datadog validates that update+create of slo alerts match an existing timeframe
      planned_actions.sort_by! { |item| item.expected.is_a?(Models::Slo) ? 0 : 1 }

      resolver.each_resolved(planned_actions) do |item|
        if item.is_a?(Types::PlannedCreate)
          message = "#{item.api_resource} #{item.tracking_id}"
          Kennel.out.puts "Creating #{message}"
          reply = @api.create item.api_resource, item.expected.as_json
          id = reply.fetch(:id)
          changes << item.change(id)
          resolver.add_actual [reply] # allow resolving ids we could previously not resolve
          Kennel.out.puts "#{LINE_UP}Created #{message} #{item.url(id)}"
        else
          message = "#{item.api_resource} #{item.tracking_id} #{item.url}"
          Kennel.out.puts "Updating #{message}"
          @api.update item.api_resource, item.id, item.expected.as_json
          changes << item.change
          Kennel.out.puts "#{LINE_UP}Updated #{message}"
        end
      rescue StandardError
        raise unless Console.tty?
        Kennel.err.puts $!.message
        Kennel.err.puts $!.backtrace
        raise unless Console.ask?("Continue with error ?")
      end

      plan.changes = changes
      plan
    end

    private

    attr_reader :filter, :resolver

    def calculate_changes(expected:, actual:)
      Progress.progress "Diffing" do
        resolver.add_actual actual
        filter_actual! actual
        resolver.resolve_as_much_as_possible(expected) # resolve as many dependencies as possible to reduce the diff

        # see which expected match the actual
        matching, unmatched_expected, unmatched_actual = MatchedExpected.partition(expected, actual)
        unmatched_actual.select! { |a| a.fetch(:tracking_id) } # ignore items that were never managed by kennel

        convert_replace_into_update!(matching, unmatched_actual, unmatched_expected)

        validate_expected_id_not_missing unmatched_expected
        fill_details! matching # need details to diff later

        # update matching if needed
        updates = matching.map do |e, a|
          # Refuse to "adopt" existing items into kennel while running with a filter (i.e. on a branch).
          # Without this, we'd adopt an item, then the next CI run would delete it
          # (instead of "unadopting" it).
          e.add_tracking_id unless filter.filtering? && a.fetch(:tracking_id).nil?
          id = a.fetch(:id)
          diff = e.diff(a)
          a[:id] = id
          Types::PlannedUpdate.new(e, a, diff) if diff.any?
        end.compact

        # delete previously managed
        deletes = unmatched_actual.map { |a| Types::PlannedDelete.new(a) }

        # unmatched expected need to be created
        unmatched_expected.each(&:add_tracking_id)
        creates = unmatched_expected.map { |e| Types::PlannedCreate.new(e) }

        # order to avoid deadlocks
        deletes.sort_by! { |item| DELETE_ORDER.index item.api_resource }
        updates.sort_by! { |item| DELETE_ORDER.index item.api_resource } # slo needs to come before slo alert

        [creates, updates, deletes]
      end
    end

    # if there is a new item that has the same name or title as an "to be deleted" item,
    # update it instead to avoid old urls from becoming invalid
    # - careful with unmatched_actual being huge since it has all api resources
    # - don't do it when a monitor type is changing since that would block the update
    def convert_replace_into_update!(matching, unmatched_actual, unmatched_expected)
      unmatched_expected.reject! do |e|
        e_field, e_value = Kennel::Models::Record::TITLE_FIELDS.detect do |field|
          next unless (value = e.as_json[field])
          break [field, value]
        end
        raise unless e_field #  uncovered: should never happen ...
        e_monitor_type = e.as_json[:type]

        actual = unmatched_actual.detect do |a|
          a[:klass] == e.class && a[e_field] == e_value && a[:type] == e_monitor_type
        end
        next false unless actual # keep in unmatched

        # add as update and remove from unmatched
        unmatched_actual.delete(actual)
        actual[:tracking_id] = e.tracking_id
        matching << [e, actual]
        true
      end
    end

    # fill details of things we need to compare
    def fill_details!(details_needed)
      details_needed = details_needed.map { |e, a| a if e && e.class.api_resource == "dashboard" }.compact
      @api.fill_details! "dashboard", details_needed
    end

    def validate_expected_id_not_missing(expected)
      expected.each do |e|
        next unless (id = e.id)
        resource = e.class.api_resource
        if @strict_imports
          raise "Unable to find existing #{resource} with id #{id}\nIf the #{resource} was deleted, remove the `id: -> { #{id} }` line."
        else
          message = "Warning: #{resource} #{e.tracking_id} specifies id #{id}, but no such #{resource} exists. 'id' will be ignored. Remove the `id: -> { #{id} }` line."
          Kennel.err.puts Console.color(:yellow, message)
        end
      end
    end

    # We've already validated the desired objects ('generated') in isolation.
    # Now that we have made the plan, we can perform some more validation.
    def validate_changes
      @plan.updates.each do |item|
        item.expected.validate_update!(item.diff)
      end
    end

    def filter_actual!(actual)
      return unless filter.filtering? # minor optimization

      actual.select! do |a|
        tracking_id = a.fetch(:tracking_id)
        tracking_id.nil? || filter.matches_tracking_id?(tracking_id)
      end
    end
  end
end
