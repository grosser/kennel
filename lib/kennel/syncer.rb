# frozen_string_literal: true
module Kennel
  class Syncer
    CACHE_FILE = "tmp/cache/details" # keep in sync with .travis.yml caching

    def initialize(api, expected, project: nil)
      @api = api
      @project_filter = project
      @expected = expected
      @expected = @expected.select { |e| e.project.kennel_id == @project_filter } if @project_filter
      @expected.each { |e| add_tracking_id e }
      calculate_diff
    end

    def plan
      puts "Plan:"
      if noop?
        puts Utils.color(:green, "Nothing to do")
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
        puts "Created #{e.class.api_resource} #{tracking_id(e.as_json)} #{e.url(reply.fetch(:id))}"
      end

      @update.each do |id, e|
        @api.update e.class.api_resource, id, e.as_json
        puts "Updated #{e.class.api_resource} #{tracking_id(e.as_json)} #{e.url(id)}"
      end

      @delete.each do |id, _, a|
        @api.delete a.fetch(:api_resource), id
        puts "Deleted #{a.fetch(:api_resource)} #{tracking_id(a)} #{id}"
      end
    end

    private

    def noop?
      @create.empty? && @update.empty? && @delete.empty?
    end

    def calculate_diff
      @update = []
      @delete = []
      actual = Progress.progress "Downloading definitions" do
        filtered_resources_from_dd
      end

      Progress.progress "Diffing" do
        details_cache do |cache|
          actual.each do |a|
            id = a.fetch(:id)

            if e = delete_matching_expected(a)
              fill_details(a, cache) if e.class::API_LIST_INCOMPLETE
              diff = e.diff(a)
              if diff.any?
                @update << [id, e, a, diff]
              end
            elsif tracking_id(a) # was previously managed
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
      full = cache.fetch(args, a.fetch(:modified)) do
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
        # lookup monitors without adding unnecessary downtime information
        results = @api.list(api_resource, with_downtimes: false)
        if results.is_a?(Hash)
          results = results[results.keys.first]
          results.each { |r| r[:id] = Integer(r.fetch(:id)) }
        end
        results.each { |c| c[:api_resource] = api_resource }
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
      @expected.delete(e) if e
    end

    def print_plan(step, list, color)
      return if list.empty?
      list.each do |_, e, a, diff|
        puts Utils.color(color, "#{step} #{tracking_id(e&.as_json || a)}")
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
          puts "  #{type}#{field}"
          puts "    #{old} ->"
          puts "    #{new}"
        else
          puts "  #{type}#{field} #{old} -> #{new}"
        end
      end
    end

    def add_tracking_id(e)
      e.as_json[tracking_field(e.as_json)] +=
        "\n-- Managed by kennel #{e.tracking_id} in #{e.project.class.file_location}, do not modify manually"
    end

    def tracking_id(a)
      a[tracking_field(a)].to_s[/-- Managed by kennel (\S+:\S+)/, 1]
    end

    def tracking_field(a)
      a[:message] ? :message : :description
    end

    def filtered_resources_from_dd
      download_definitions.select do |a|
        if @project_filter
          tracking_id = tracking_id(a)
          tracking_id.nil? || tracking_id.start_with?("#{@project_filter}:")
        else
          true
        end
      end
    end
  end
end
