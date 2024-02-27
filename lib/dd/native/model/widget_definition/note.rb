# frozen_string_literal:true

module DD
  module Native
    class Model
      class WidgetDefinition
        class Note < WidgetDefinition
          REQUIRED_KEYS = [
            "content",
            "type",
          ].map(&:to_s).freeze

          OPTIONAL_KEYS = [
            "background_color",
            "font_size",
            "has_padding",
            "show_tick",
            "text_align",
            "tick_edge",
            "tick_pos",
            "vertical_align",
          ].map(&:to_s).freeze

          attr_reader *REQUIRED_KEYS, *OPTIONAL_KEYS
        end
      end
    end
  end
end
