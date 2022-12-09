# frozen_string_literal: true

module Kennel
  module Models
    module Built
      class Dashboard < Record
        def resolve_linked_tracking_ids!(id_map, **args)
          widgets = as_json[:widgets].flat_map { |w| [w, *w.dig(:definition, :widgets) || []] }
          widgets.each do |widget|
            next unless definition = widget[:definition]
            case definition[:type]
            when "uptime"
              if ids = definition[:monitor_ids]
                definition[:monitor_ids] = ids.map do |id|
                  resolve(id, :monitor, id_map, **args) || id
                end
              end
            when "alert_graph"
              if id = definition[:alert_id]
                resolved = resolve(id, :monitor, id_map, **args) || id
                definition[:alert_id] = resolved.to_s # even though it's a monitor id
              end
            when "slo"
              if id = definition[:slo_id]
                definition[:slo_id] = resolve(id, :slo, id_map, **args) || id
              end
            end
          end
        end

        def validate_update!(_actuals, diffs)
          _, path, from, to = diffs.find { |diff| diff[1] == "layout_type" }
          invalid_update!(path, from, to) if path
        end
      end
    end
  end
end
