# frozen_string_literal: true

module Kennel
  module DependencyChecker
    class Collector

      def initialize(everything)
        build_indices(everything)
      end

      attr_reader :objects, :synthetics_by_monitor_id

      def collect
        dependencies.map do |dep|
          {
            from: render(dep.a),
            to: render(dep.b),
          }
        end
      end

      private

      def build_indices(everything)
        @synthetics_by_monitor_id = {}

        @objects = everything.each_with_object({}) do |item, hash|
          type = item.fetch(:api_resource)
          key = ResourceId.new(resource: type, id: item[:id].to_s)
          hash[key] = ItemUtils.new(key, item)

          if type.to_s == TYPE_SYNTHETIC
            @synthetics_by_monitor_id[item.fetch(:monitor_id).to_s] = key
          end
        end
      end

      def dependencies
        objects.entries.flat_map do |key, item|
          (item.dependencies || []).map do |dep|
            Dependency.new(a: key, b: dep)
          end
        end
      end

      def render(key)
        resolved_key = resolve(key)
        item = objects[resolved_key]

        if item.nil?
          return {
            key: key,
            exists: false,
          }
        end

        {
          key: key,
          exists: true,
          object: item.object,
          url: item.url,
          name: item.name,
          kennel_id: item.kennel_id,
          teams: item.tags&.select { |t| t.start_with?("team:") }&.sort&.uniq,
          author: item.author,
        }
      end

      def resolve(key)
        if !objects.key?(key) && key.resource == TYPE_MONITOR
          key = synthetics_by_monitor_id[key.id]
        end

        key
      end

    end
  end
end
