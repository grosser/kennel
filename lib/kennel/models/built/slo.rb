# frozen_string_literal: true

module Kennel
  module Models
    module Built
      class Slo < Record
        def resolve_linked_tracking_ids!(id_map, **args)
          return unless ids = as_json[:monitor_ids] # ignore_default can remove it
          as_json[:monitor_ids] = ids.map do |id|
            resolve(id, :monitor, id_map, **args) || id
          end
        end
      end
    end
  end
end
