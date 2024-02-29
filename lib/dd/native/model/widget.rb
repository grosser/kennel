# frozen_string_literal: true

require_relative "widget_definition"

module DD
  module Native
    class Model
      class Widget < Model
        REQUIRED_KEYS = ["id", "definition"].freeze

        OPTIONAL_KEYS = ["layout"].freeze

        attr_reader *REQUIRED_KEYS, *OPTIONAL_KEYS

        def initialize(item)
          super do
            @definition = WidgetDefinition.from_single(definition)
            @layout = WidgetLayout.new(layout) if layout
          end
        end

        def inspect
          if definition.is_a?(UnhandledType)
            "#<Widget of unhandled type #{definition.type.inspect}>"
          else
            "#<Widget of type #{definition.type.inspect}>"
          end
        end

        def type
          definition.type
        end
      end
    end
  end
end
