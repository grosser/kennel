# frozen_string_literal: true

module Kennel
  module DependencyChecker
    class ItemUtils
      class Base

        def initialize(key, object)
          @resource = key.resource.to_s
          @id = key.id
          @object = object
        end

        attr_reader :resource, :id, :object

        def kennel_id
          text = kennel_id_text
          return unless text

          m = text.match(/Managed by kennel (\S+) in ([^,]+),/)
          m or return

          KennelId.new(id: m[1], in: m[2])
        end

        protected

        def scan_text_for_dependencies(text, _context)
          text&.scan(/https:\/\/zendesk\.datadoghq\.com\/dashboard\/(\w\w\w-\w\w\w-\w\w\w)\//) do |id, _|
            # puts "found dashboard #{id} in #{context}"
            yield ResourceId.new(resource: "dashboard", id: id)
          end

          text&.scan(/https:\/\/zendesk\.datadoghq\.com\/monitors\/(\d+)\//) do |id, _|
            # puts "found monitor #{id} in #{context}"
            yield ResourceId.new(resource: "monitor", id: id)
          end

          text&.scan(/https:\/\/zendesk\.datadoghq\.com\/slo\?(?:\w+=\w+&)*slo_id=(\w+)/) do |id, _|
            # puts "found slo #{id} in #{context}"
            yield ResourceId.new(resource: "slo", id: id)
          end
        end

      end
    end
  end
end
