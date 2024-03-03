# frozen_string_literal: true

module DD
  module MetricFilter
    module Nodes
      SimpleValue = JData.define(:value)
      TemplateValue = JData.define(:name)
      TemplateVariable = JData.define(:name)
      CommaList = JData.define(:items)
      OrList = JData.define(:items)
      AndList = JData.define(:items)
      Bang = JData.define(:item)
      Not = JData.define(:item)
      KeyValuePair = JData.define(:key, :value)
      KeyOnly = JData.define(:key)
      InClause = Data.define(:needle, :haystack)
      InList = Data.define(:items)
      Star = Data.define()
    end
  end
end
