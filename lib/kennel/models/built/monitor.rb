# frozen_string_literal: true

module Kennel
  module Models
    module Built
      class Monitor < Record
        def resolve_linked_tracking_ids!(id_map, **args)
          case as_json[:type]
          when "composite", "slo alert"
            type = (as_json[:type] == "composite" ? :monitor : :slo)
            as_json[:query] = as_json[:query].gsub(/%{(.*?)}/) do
              resolve($1, type, id_map, **args) || $&
            end
          else # do nothing
          end
        end

        def validate_update!(_actuals, diffs)
          # ensure type does not change, but not if it's metric->query which is supported and used by importer.rb
          _, path, from, to = diffs.detect { |_, path, _, _| path == "type" }
          if path && !(from == "metric alert" && to == "query alert")
            invalid_update!(path, from, to)
          end
        end
      end
    end
  end
end
