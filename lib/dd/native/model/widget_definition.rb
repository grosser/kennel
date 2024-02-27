# frozen_string_literal:true

module DD
  module Native
    class Model
      class WidgetDefinition < Model
        require_relative "widget_definition/group"
        require_relative "widget_definition/note"
        require_relative "widget_definition/timeseries"

        TYPE_MAP = {
          group: Group,
          note: Note,
          timeseries: TimeSeries,
        }.freeze

        # ["alert_graph",
        #  "alert_value",
        #  "change",
        #  "check_status",
        #  "custom",
        #  "distribution",
        #  "event_stream",
        #  "event_timeline",
        #  "free_text",
        #  "geomap",
        #  "group",
        #  "heatmap",
        #  "hostmap",
        #  "iframe",
        #  "image",
        #  "list_stream",
        #  "log_stream",
        #  "manage_status",
        #  "note",
        #  "powerpack",
        #  "query_table",
        #  "query_value",
        #  "scatterplot",
        #  "servicemap",
        #  "slo",
        #  "slo_list",
        #  "split_group",
        #  "sunburst",
        #  "timeseries",
        #  "toplist",
        #  "topology_map",
        #  "trace_service",
        #  "treemap"]

        TYPE_FIELD = :type
      end
    end
  end
end
