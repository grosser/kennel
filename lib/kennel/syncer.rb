# frozen_string_literal: true
module Kennel
  class Syncer
    DELETE_ORDER = ["dashboard", "slo", "monitor", "synthetics/tests"].freeze # dashboards references monitors + slos, slos reference monitors
    LINE_UP = "\e[1A\033[K" # go up and clear

    def initialize(api, expected, project: nil)
      @api = api
      @project_filter = project
      @expected = expected
      calculate_diff
      validate_plan
      prevent_irreversible_partial_updates
    end

    def plan
      Kennel.out.puts "Plan:"
      if noop?
        Kennel.out.puts Utils.color(:green, "Nothing to do")
      else
        @warnings.each { |message| Kennel.out.puts Utils.color(:yellow, "Warning: #{message}") }
        print_plan "Create", @create, :green
        print_plan "Update", @update, :yellow
        print_plan "Delete", @delete, :red
      end
    end

    def confirm
      return false if noop?
      return true if ENV["CI"] || !STDIN.tty?
      Utils.ask("Execute Plan ?")
    end

    def update
      each_resolved @create do |_, e|
        message = "#{e.class.api_resource} #{e.tracking_id}"
        Kennel.out.puts "Creating #{message}"
        reply = @api.create e.class.api_resource, e.as_json
        cache_metadata reply, e.class
        id = reply.fetch(:id)
        populate_id_map [], [reply] # allow resolving ids we could previously no resolve
        Kennel.out.puts "#{LINE_UP}Created #{message} #{e.class.url(id)}"
      end

      each_resolved @update do |id, e|
        message = "#{e.class.api_resource} #{e.tracking_id} #{e.class.url(id)}"
        Kennel.out.puts "Updating #{message}"
        @api.update e.class.api_resource, id, e.as_json
        Kennel.out.puts "#{LINE_UP}Updated #{message}"
      end

      @delete.each do |id, _, a|
        klass = a.fetch(:klass)
        message = "#{klass.api_resource} #{a.fetch(:tracking_id)} #{id}"
        Kennel.out.puts "Deleting #{message}"
        @api.delete klass.api_resource, id
        Kennel.out.puts "#{LINE_UP}Deleted #{message}"
      end
    end

    private

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

    # TODO: optimize by storing an instance variable if already resolved
    def resolved?(e)
      assert_resolved e
      true
    rescue ValidationError
      false
    end

    # raises ValidationError when not resolved
    def assert_resolved(e)
      resolve_linked_tracking_ids! [e], force: true
    end

    def noop?
      @create.empty? && @update.empty? && @delete.empty?
    end

    def calculate_diff
      @warnings = []
      @update = []
      @delete = []
      @id_map = IdMap.new

      actual = Progress.progress("Downloading definitions") { download_definitions }

      Progress.progress "Diffing" do
        populate_id_map @expected, actual
        filter_actual_by_project! actual
        resolve_linked_tracking_ids! @expected # resolve dependencies to avoid diff

        @expected.each(&:add_tracking_id) # avoid diff with actual

        items = actual.map do |a|
          e = matching_expected(a)
          if e && @expected.delete(e)
            [e, a]
          else
            [nil, a]
          end
        end

        # fill details of things we need to compare
        details = items.map { |e, a| a if e && e.class.api_resource == "dashboard" }.compact
        @api.fill_details! "dashboard", details

        # pick out things to update or delete
        items.each do |e, a|
          id = a.fetch(:id)
          if e
            diff = e.diff(a)
            @update << [id, e, a, diff] if diff.any?
          elsif a.fetch(:tracking_id) # was previously managed
            @delete << [id, nil, a]
          end
        end

        ensure_all_ids_found
        @create = @expected.map { |e| [nil, e] }
        @delete.sort_by! { |_, _, a| DELETE_ORDER.index a.fetch(:klass).api_resource }
        @update.sort_by! { |_, e, _| DELETE_ORDER.index e.class.api_resource } # slo needs to come before slo alert
      end
    end

    def download_definitions
      Utils.parallel(Models::Record.subclasses) do |klass|
        results = @api.list(klass.api_resource, with_downtimes: false) # lookup monitors without adding unnecessary downtime information
        results = results[results.keys.first] if results.is_a?(Hash) # dashboards are nested in {dashboards: []}
        results.each { |a| cache_metadata(a, klass) }
      end.flatten(1)
    end

    def cache_metadata(a, klass)
      a[:klass] = klass
      a[:tracking_id] = a.fetch(:klass).parse_tracking_id(a)
    end

    def ensure_all_ids_found
      @expected.each do |e|
        next unless id = e.id
        resource = e.class.api_resource
        if Kennel.strict_imports
          raise "Unable to find existing #{resource} with id #{id}\nIf the #{resource} was deleted, remove the `id: -> { #{id} }` line."
        else
          @warnings << "#{resource} #{e.tracking_id} specifies id #{id}, but no such #{resource} exists. 'id' will be ignored. Remove the `id: -> { #{id} }` line."
        end
      end
    end

    def matching_expected(a)
      # index list by all the thing we look up by: tracking id and actual id
      @lookup_map ||= @expected.each_with_object({}) do |e, all|
        keys = [e.tracking_id]
        keys << "#{e.class.api_resource}:#{e.id}" if e.id
        keys.compact.each do |key|
          raise "Lookup #{key} is duplicated" if all[key]
          all[key] = e
        end
      end

      klass = a.fetch(:klass)
      @lookup_map["#{klass.api_resource}:#{a.fetch(:id)}"] || @lookup_map[a.fetch(:tracking_id)]
    end

    def print_plan(step, list, color)
      return if list.empty?
      list.each do |_, e, a, diff|
        klass = (e ? e.class : a.fetch(:klass))
        Kennel.out.puts Utils.color(color, "#{step} #{klass.api_resource} #{e&.tracking_id || a.fetch(:tracking_id)}")
        print_diff(diff) if diff # only for update
      end
    end

    def print_diff(diff)
      diff.each do |type, field, old, new|
        if type == "+"
          temp = Utils.pretty_inspect(new)
          new = Utils.pretty_inspect(old)
          old = temp
        else # ~ and -
          old = Utils.pretty_inspect(old)
          new = Utils.pretty_inspect(new)
        end

        if (old + new).size > 100
          Kennel.out.puts "  #{type}#{field}"
          Kennel.out.puts "    #{old} ->"
          Kennel.out.puts "    #{new}"
        else
          Kennel.out.puts "  #{type}#{field} #{old} -> #{new}"
        end
      end
    end

    # We've already validated the desired objects ('generated') in isolation.
    # Now that we have made the plan, we can perform some more validation.
    def validate_plan
      @update.each do |_, expected, actual, diffs|
        expected.validate_update!(actual, diffs)
      end
    end

    # - do not add tracking-id when working with existing ids on a branch,
    #   so resource do not get deleted when running an update on master (for example merge->CI)
    # - make sure the diff is clean, by kicking out the now noop-update
    # - ideally we'd never add tracking in the first place, but when adding tracking we do not know the diff yet
    def prevent_irreversible_partial_updates
      return unless @project_filter
      @update.select! do |_, e, _, diff|
        next true unless e.id # safe to add tracking when not having id

        diff.select! do |field_diff|
          (_, field, actual) = field_diff
          # TODO: refactor this so TRACKING_FIELD stays record-private
          next true if e.class::TRACKING_FIELD != field.to_sym # need to sym here because Hashdiff produces strings
          next true if e.class.parse_tracking_id(field.to_sym => actual) # already has tracking id

          field_diff[3] = e.remove_tracking_id # make `rake plan` output match what we are sending
          actual != field_diff[3] # discard diff if now nothing changes
        end

        !diff.empty?
      end
    end

    def populate_id_map(expected, actual)
      # mark everything as new
      expected.each do |e|
        @id_map.set(e.class.api_resource, e.tracking_id, IdMap::NEW)
        if e.class.api_resource == "synthetics/tests"
          @id_map.set(Kennel::Models::Monitor.api_resource, e.tracking_id, IdMap::NEW)
        end
      end

      # override resources that exist with their id
      project_prefix = @project_filter && "#{@project_filter}:"
      actual.each do |a|
        # ignore when not managed by kennel
        next unless tracking_id = a.fetch(:tracking_id)

        # ignore when deleted from the codebase
        # (when running with project filter we cannot see the other resources in the codebase)
        api_resource = a.fetch(:klass).api_resource
        next if
          !@id_map.get(api_resource, tracking_id) &&
          (!project_prefix || tracking_id.start_with?(project_prefix))

        @id_map.set(api_resource, tracking_id, a.fetch(:id))
        if a[:klass].api_resource == "synthetics/tests"
          @id_map.set(Kennel::Models::Monitor.api_resource, tracking_id, a.fetch(:monitor_id))
        end
      end
    end

    def resolve_linked_tracking_ids!(list, force: false)
      list.each { |e| e.resolve_linked_tracking_ids!(@id_map, force: force) }
    end

    def filter_actual_by_project!(actual)
      return unless @project_filter
      actual.select! do |a|
        tracking_id = a.fetch(:tracking_id)
        !tracking_id || tracking_id.start_with?("#{@project_filter}:")
      end
    end
  end
end
