# frozen_string_literal: true
module Kennel
  class Syncer
    CACHE_FILE = "tmp/cache/details" # keep in sync with .travis.yml caching
    TRACKING_FIELDS = [:message, :description].freeze
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
      @expected.each { |e| add_tracking_id e }
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
      changed = (@create + @update).map { |_, e| e } unless @create.empty?

      @create.each do |_, e|
        e.resolve_linked_tracking_ids!({}, force: true)

        reply = @api.create e.class.api_resource, e.as_json
        id = reply.fetch(:id)

        # resolve ids we could previously no resolve
        changed.delete e
        resolve_linked_tracking_ids! from: [reply], to: changed

        Kennel.out.puts "Created #{e.class.api_resource} #{tracking_id(e.as_json)} #{e.url(id)}"
      end

      @update.each do |id, e|
        e.resolve_linked_tracking_ids!({}, force: true)
        @api.update e.class.api_resource, id, e.as_json
        Kennel.out.puts "Updated #{e.class.api_resource} #{tracking_id(e.as_json)} #{e.url(id)}"
      end

      @delete.each do |id, _, a|
        @api.delete a.fetch(:api_resource), id
        Kennel.out.puts "Deleted #{a.fetch(:api_resource)} #{tracking_id(a)} #{id}"
      end
    end

    private

    def noop?
      @create.empty? && @update.empty? && @delete.empty?
    end

    def calculate_diff
      @update = []
      @delete = []

      actual = Progress.progress("Downloading definitions") { download_definitions }
      resolve_linked_tracking_ids! from: actual, to: @expected
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

        details_cache do |cache|
          # fill details of things we need to compare (only do this part in parallel for safety & balancing)
          Utils.parallel(items.select { |e, _| e && e.class::API_LIST_INCOMPLETE }) { |_, a| fill_details(a, cache) }
        end

        # pick out things to update or delete
        items.each do |e, a|
          id = a.fetch(:id)
          if e
            diff = e.diff(a)
            @update << [id, e, a, diff] if diff.any?
          elsif tracking_id(a) # was previously managed
            @delete << [id, nil, a]
          end
        end

        ensure_all_ids_found
        @create = @expected.map { |e| [nil, e] }
        @create.sort_by! { |_, e| -DELETE_ORDER.index(e.class.api_resource) }
      end

      @delete.sort_by! { |_, _, a| DELETE_ORDER.index a.fetch(:api_resource) }
    end

    # Make diff work even though we cannot mass-fetch definitions
    def fill_details(a, cache)
      resource = a.fetch(:api_resource)
      args = [resource, a.fetch(:id)]
      full = cache.fetch(args, a[:modified] || a.fetch(:modified_at)) do
        @api.show(*args)
      end
      a.merge!(full)
    end

    def details_cache(&block)
      cache = FileCache.new CACHE_FILE, Kennel::VERSION
      cache.open(&block)
    end

    def download_definitions
      Utils.parallel(Models::Record.subclasses.map(&:api_resource)) do |api_resource|
        results = @api.list(api_resource, with_downtimes: false) # lookup monitors without adding unnecessary downtime information
        results = results[results.keys.first] if results.is_a?(Hash) # dashboards are nested in {dashboards: []}
        results.each { |c| c[:api_resource] = api_resource } # store api resource for later diffing
      end.flatten(1)
    end

    def ensure_all_ids_found
      @expected.each do |e|
        next unless id = e.id
        raise "Unable to find existing #{e.class.api_resource} with id #{id}"
      end
    end

    def matching_expected(a)
      # index list by all the thing we look up by: tracking id and actual id
      @lookup_map ||= @expected.each_with_object({}) do |e, all|
        keys = [tracking_id(e.as_json)]
        keys << "#{e.class.api_resource}:#{e.id}" if e.id
        keys.compact.each do |key|
          raise "Lookup #{key} is duplicated" if all[key]
          all[key] = e
        end
      end

      @lookup_map["#{a.fetch(:api_resource)}:#{a.fetch(:id)}"] || @lookup_map[tracking_id(a)]
    end

    def print_plan(step, list, color)
      return if list.empty?
      list.each do |_, e, a, diff|
        api_resource = (e ? e.class.api_resource : a.fetch(:api_resource))
        Kennel.out.puts Utils.color(color, "#{step} #{api_resource} #{e&.tracking_id || tracking_id(a)}")
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

    # Do not add tracking-id when working with existing ids on a branch,
    # so resource do not get deleted fr:om merges to master.
    # Also make sure the diff still makes sense, by kicking out the now noop-update.
    #
    # Note: ideally we'd never add tracking in the first place, but at that point we do not know the diff yet
    def prevent_irreversible_partial_updates
      return unless @project_filter
      @update.select! do |_, e, _, diff|
        next true unless e.id # short circuit for performance

        diff.select! do |field_diff|
          (_, field, old, new) = field_diff
          next true unless tracking_field?(field)

          if (old_tracking = tracking_value(old))
            old_tracking == tracking_value(new) || raise("do not update! (atm unreachable)")
          else
            field_diff[3] = remove_tracking_id(e) # make plan output match update
            old != field_diff[3]
          end
        end

        !diff.empty?
      end
    end

    def resolve_linked_tracking_ids!(from:, to:)
      map = from.each_with_object({}) { |a, lookup| lookup[tracking_id(a)] = a.fetch(:id) }
      to.each { |e| map[e.tracking_id] ||= :new }
      to.each { |e| e.resolve_linked_tracking_ids!(map, force: false) }
    end

    def filter_by_project!(definitions)
      return unless @project_filter
      definitions.select! do |a|
        id = tracking_id(a)
        !id || id.start_with?("#{@project_filter}:")
      end
    end

    def add_tracking_id(e)
      json = e.as_json
      field = tracking_field(json)
      raise "remove \"-- Managed by kennel\" line it from #{field} to copy a resource" if tracking_value(json[field])
      json[field] = "#{json[field]}\n-- Managed by kennel #{e.tracking_id} in #{e.project.class.file_location}, do not modify manually".lstrip
    end

    def remove_tracking_id(e)
      json = e.as_json
      field = tracking_field(json)
      value = json[field]
      json[field] = value.dup.sub!(/\n?-- Managed by kennel .*/, "") || raise("did not find tracking id in #{value}")
    end

    def tracking_id(a)
      tracking_value a[tracking_field(a)]
    end

    def tracking_value(content)
      content.to_s[/-- Managed by kennel (\S+:\S+)/, 1]
    end

    def tracking_field(a)
      TRACKING_FIELDS.detect { |f| a.key?(f) }
    end

    def tracking_field?(field)
      TRACKING_FIELDS.include?(field.to_sym)
    end
  end
end
