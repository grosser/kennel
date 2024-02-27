# frozen_string_literal:true

module DD
  module Native
    class Model
      class WidgetDefinition
        class TimeSeries < WidgetDefinition
          REQUIRED_KEYS = [
            "requests",
            "type",
          ].map(&:to_s).freeze

          OPTIONAL_KEYS = [
            "custom_links",
            "events",
            "legend_columns",
            "legend_layout",
            "legend_size",
            "markers",
            "right_yaxis",
            "show_legend",
            "time",
            "title",
            "title_align",
            "title_size",
            "yaxis"
          ].map(&:to_s).freeze

          attr_reader *REQUIRED_KEYS, *OPTIONAL_KEYS

          # [DD::Native::Model::WidgetDefinition::TimeSeries, "requests", Array]=>58170,
          #  [DD::Native::Model::WidgetDefinition::TimeSeries, "markers", Array]=>18581,
          # [DD::Native::Model::WidgetDefinition::TimeSeries, "legend_columns", Array]=>23683,
          #  [DD::Native::Model::WidgetDefinition::TimeSeries, "events", Array]=>5104,
          #  [DD::Native::Model::WidgetDefinition::TimeSeries, "yaxis", Hash]=>19086,
          #  [DD::Native::Model::WidgetDefinition::TimeSeries, "custom_links", Array]=>2397,
          #  [DD::Native::Model::WidgetDefinition::TimeSeries, "time", Hash]=>6992,
          #  [DD::Native::Model::WidgetDefinition::TimeSeries, "right_yaxis", Hash]=>478,
        end
      end
    end
  end
end
