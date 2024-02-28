# frozen_string_literal: true

module DD
  module MetricAnalysis
    def self.each_metric_query(set)
      return enum_for(:each_metric_query, set) unless block_given?

      set.each do |item|
        case item["api_resource"]
        when "monitor"
          case item["type"]
          when "query alert"
            yield item["query"]
          end
        end
      end
    end

    def self.scan_widgets(set)
      return enum_for(:scan_widgets, set) unless block_given?

      set.each_dashboard_widget do |w|
        q = [w]

        while (item = q.shift)
          case item
          when Array
            q.unshift(*item)
          when Hash
            q.unshift(*item.values)
          when /:.*\{/
            yield item
          end
        end
      end
    end
  end
end
