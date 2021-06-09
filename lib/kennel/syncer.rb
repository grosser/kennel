# frozen_string_literal: true
module Kennel
  class Syncer
    DELETE_ORDER = ["dashboard", "slo", "monitor"].freeze # dashboards references monitors + slos, slos reference monitors

    def initialize(api, expected, project: nil)
      @api = api
      @project_filter = project
      @expected = expected
      if @project_filter
        original = @expected
        @expected = @expected.select { |e| e.project.kennel_id == @project_filter }
        if @expected.empty?
          possible = original.map { |e| e.project.kennel_id }.uniq.sort
          raise "#{@project_filter} does not match any projects, try any of these:\n#{possible.join("\n")}"
        end
      end
      @expected.each(&:add_tracking_id)
      calculate_diff
      prevent_irreversible_partial_updates
    end

    def plan
      Kennel.out.puts "Plan:"
      if noop?
        Kennel.out.puts Utils.color(:green, "Nothing to do")
      else
        print_plan "Create", @create, :green
        print_plan "Update", @update, :yellow
        print_plan "Delete", @delete, :red
      end
    end

    def confirm
      ENV["CI"] || !STDIN.tty? || Utils.ask("Execute Plan ?") unless noop?
    end

    def update
      each_resolved @create do |_, e|
        reply = @api.create e.class.api_resource, e.as_json
        reply[:klass] = e.class # store api resource class for later use
        id = reply.fetch(:id)
        populate_id_map [reply] # allow resolving ids we could previously no resolve
        Kennel.out.puts "Created #{e.class.api_resource} #{e.tracking_id} #{e.class.url(id)}"
      end

      each_resolved @update do |id, e|
        @api.update e.class.api_resource, id, e.as_json
        Kennel.out.puts "Updated #{e.class.api_resource} #{e.tracking_id} #{e.class.url(id)}"
      end

      @delete.each do |id, _, a|
        klass = a.fetch(:klass)
        @api.delete klass.api_resource, id
        tracking_id = klass.parse_tracking_id(a)
        Kennel.out.puts "Deleted #{klass.api_resource} #{tracking_id} #{id}"
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
      @update = []
      @delete = []
      @id_map = {}

      actual = Progress.progress("Downloading definitions") { download_definitions }

      # resolve dependencies to avoid diff
      populate_id_map actual
      @expected.each { |e| @id_map[e.tracking_id] ||= :new }
      resolve_linked_tracking_ids! @expected

      filter_by_project! actual

      Progress.progress "Diffing" do
        items = actual.map do |a|
          e = matching_expected(a)
          if e && @expected.delete(e)
            [e, a]
          else
            [nil, a]
          end
        end

        # fill details of things we need to compare
        detailed = Hash.new { |h, k| h[k] = [] }
        items.each { |e, a| detailed[a[:klass]] << a if e }
        detailed.each { |klass, actuals| @api.fill_details! klass.api_resource, actuals }

        # pick out things to update or delete
        items.each do |e, a|
          id = a.fetch(:id)
          if e
            diff = e.diff(a)
            @update << [id, e, a, diff] if diff.any?
          elsif a.fetch(:klass).parse_tracking_id(a) # was previously managed
            @delete << [id, nil, a]
          end
        end

        ensure_all_ids_found
        @create = @expected.map { |e| [nil, e] }
      end

      @delete.sort_by! { |_, _, a| DELETE_ORDER.index a.fetch(:klass).api_resource }
    end

    def download_definitions
      Utils.parallel(Models::Record.subclasses) do |klass|
        results = @api.list(klass.api_resource, with_downtimes: false) # lookup monitors without adding unnecessary downtime information
        results = results[results.keys.first] if results.is_a?(Hash) # dashboards are nested in {dashboards: []}
        results.each { |c| c[:klass] = klass } # store api resource for later diffing
      end.flatten(1)
    end

    def ensure_all_ids_found
      @expected.each do |e|
        next unless id = e.id
        resource = e.class.api_resource
        raise "Unable to find existing #{resource} with id #{id}\nIf the #{resource} was deleted, remove the `id: -> { #{e.id} }` line."
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
      @lookup_map["#{klass.api_resource}:#{a.fetch(:id)}"] || @lookup_map[klass.parse_tracking_id(a)]
    end

    def print_plan(step, list, color)
      return if list.empty?
      list.each do |_, e, a, diff|
        klass = (e ? e.class : a.fetch(:klass))
        Kennel.out.puts Utils.color(color, "#{step} #{klass.api_resource} #{e&.tracking_id || klass.parse_tracking_id(a)}")
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

    def populate_id_map(actual)
      actual.each { |a| @id_map[a.fetch(:klass).parse_tracking_id(a)] = a.fetch(:id) }
    end

    def resolve_linked_tracking_ids!(list, force: false)
      list.each { |e| e.resolve_linked_tracking_ids!(@id_map, force: force) }
    end

    def filter_by_project!(definitions)
      return unless @project_filter
      definitions.select! do |a|
        id = a.fetch(:klass).parse_tracking_id(a)
        !id || id.start_with?("#{@project_filter}:")
      end
    end
  end
end
