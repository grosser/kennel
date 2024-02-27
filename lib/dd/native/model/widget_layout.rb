# frozen_string_literal: true

module DD
  module Native
    class Model
      class WidgetLayout < Model
        REQUIRED_KEYS = ["y", "x"].freeze

        OPTIONAL_KEYS = ["width", "height", "is_column_break"].freeze

        attr_reader *REQUIRED_KEYS, *OPTIONAL_KEYS
      end
    end
  end
end
