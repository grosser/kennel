# frozen_string_literal:true

module DD
  module Native
    class Model
      class WidgetDefinition
        class Group < WidgetDefinition
          REQUIRED_KEYS = [
            :layout_type,
            :title,
            :type,
            :widgets,
          ].map(&:to_s).freeze

          OPTIONAL_KEYS = [
            :background_color,
            :banner_img,
            :show_title,
            :title_align,
          ].map(&:to_s).freeze

          attr_reader *REQUIRED_KEYS, *OPTIONAL_KEYS

          def initialize(item)
            super
            @widgets = Widget.from_multi(widgets, allow_nil: false)
          end
        end
      end
    end
  end
end
