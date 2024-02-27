# frozen_string_literal: true

module DD
  module Native
    class Model
      class TemplateVariable < Model
        REQUIRED_KEYS = ["name"].freeze

        OPTIONAL_KEYS = [
          "available_values",
          "default",
          "defaults",
          "prefix"
        ].freeze

        attr_reader *REQUIRED_KEYS, *OPTIONAL_KEYS
      end
    end
  end
end
