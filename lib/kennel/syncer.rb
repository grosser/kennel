# frozen_string_literal: true
module Kennel
  class Syncer
    CACHE_FILE = "tmp/cache/details" # keep in sync with .travis.yml caching
    TRACKING_FIELDS = [:message, :description].freeze

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
      @create.each do |_, e|
        reply = @api.create e.class.api_resource, e.as_json
        reply = unnest(e.class.api_resource, reply)
        Kennel.out.puts "Created #{e.class.api_resource} #{tracking_id(e.as_json)} #{e.url(reply.fetch(:id))}"
      end

      block_irreversible_partial_updates
      @update.each do |id, e|
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

      resolve_linked_tracking_ids actual

      Progress.progress "Diffing" do
        filter_by_project! actual

        details_cache do |cache|
          actual.each do |a|
            id = a.fetch(:id)

            if e = delete_matching_expected(a)
              fill_details(a, cache) if e.class::API_LIST_INCOMPLETE
              diff = e.diff(a)
              @update << [id, e, a, diff] if diff.any?
            elsif tracking_id(a) && !@lookup_map[tracking_id(a)] # was previously managed (need to check lookup map in case of dashboards)
              @delete << [id, nil, a]
            end
          end
        end

        ensure_all_ids_found
        @create = @expected.map { |e| [nil, e] }
      end
    end

    # Hack to get diff to work until we can mass-fetch definitions
    def fill_details(a, cache)
      resource = a.fetch(:api_resource)
      args = [resource, a.fetch(:id)]
      full = cache.fetch(args, a[:modified] || a.fetch(:modified_at)) do
        unnest(resource, @api.show(*args))
      end
      a.merge!(full)
    end

    # dashes are nested, others are not
    def unnest(api_resource, result)
      result[api_resource.to_sym] || result
    end

    def details_cache(&block)
      cache = FileCache.new CACHE_FILE, Kennel::VERSION
      cache.open(&block)
    end

    def download_definitions
      api_resources = Models::Base.subclasses.map do |m|
        next unless m.respond_to?(:api_resource)
        m.api_resource
      end

      Utils.parallel(api_resources.compact.uniq) do |api_resource|
        results = @api.list(api_resource, with_downtimes: false) # lookup monitors without adding unnecessary downtime information
        results = results[results.keys.first] if results.is_a?(Hash) # dashes/screens are nested in {dash: {}}
        results.each { |r| r[:id] = Integer(r[:id]) if r[:id] =~ /\A\d+\z/ } # screen ids are integers as strings
        results.each { |c| c[:api_resource] = api_resource } # store api resource for later diffing
      end.flatten(1)
    end

    def ensure_all_ids_found
      @expected.each do |e|
        next unless id = e.id
        raise "Unable to find existing #{e.class.api_resource} with id #{id}"
      end
    end

    def delete_matching_expected(a)
      # index list by all the thing we look up by: tracking id and actual id
      @lookup_map ||= @expected.each_with_object({}) do |e, all|
        keys = [tracking_id(e.as_json)]
        keys << "#{e.class.api_resource}:#{e.id}" if e.id
        keys.compact.each do |key|
          raise "Lookup #{key} is duplicated" if all[key]
          all[key] = e
        end
      end

      e = @lookup_map["#{a.fetch(:api_resource)}:#{a.fetch(:id)}"] || @lookup_map[tracking_id(a)]
      return if e && a[:api_resource] != e.class.api_resource
      @expected.delete(e) if e
    end

    def print_plan(step, list, color)
      return if list.empty?
      list.each do |_, e, a, diff|
        Kennel.out.puts Utils.color(color, "#{step} #{tracking_id(e&.as_json || a)}")
        print_diff(diff) if diff # only for update
      end
    end

    def print_diff(diff)
      diff.each do |type, field, old, new|
        if type == "+"
          temp = new.inspect
          new = old.inspect
          old = temp
        else # ~ and -
          old = old.inspect
          new = new.inspect
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

    def block_irreversible_partial_updates
      return unless @project_filter
      return if @update.none? do |_, e, _, diff|
        e.id && diff.any? do |_, field, old, new = nil|
          TRACKING_FIELDS.include?(field.to_sym) && tracking_value(old) != tracking_value(new)
        end
      end
      raise <<~TEXT
        Updates with PROJECT= filter should not update tracking id in #{TRACKING_FIELDS.join("/")} of resources with a set `id:`,
        since this makes them get deleted by a full update.
        Remove the `id:` to test them out, which will result in a copy being created and later deleted.
      TEXT
    end

    def resolve_linked_tracking_ids(actual)
      map = actual.each_with_object({}) { |a, lookup| lookup[tracking_id(a)] = a.fetch(:id) }
      @expected.each { |e| e.resolve_linked_tracking_ids(map) }
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

    def tracking_id(a)
      tracking_value a[tracking_field(a)]
    end

    def tracking_value(content)
      content.to_s[/-- Managed by kennel (\S+:\S+)/, 1]
    end

    def tracking_field(a)
      TRACKING_FIELDS.detect { |f| a.key?(f) }
    end
  end
end
