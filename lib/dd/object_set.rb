# frozen_string_literal: true

require 'json'

module DD
  class ObjectSet < Array
    def self.from_dump
      items = File.open("tmp/dump.json") do |f|
        f.each_line.each_with_index.map do |text, number|
          data = JSON.parse(text)
          DumpObject.new(data)
        # rescue => e
        #   puts JSON.generate({ parse_error: e.to_s, line: number, backtrace: e.backtrace })
        #   nil
        end
      end.compact

      new.tap { |o| o.push(*items) }
    end

    def inspect
      "#<ObjectSet of #{count} items>"
    end

    alias :pretty_inspect :inspect

    def pretty_print(_)
      puts inspect
    end

    def each_metric_query
      return enum_for(:each_metric_query) unless block_given?

      each do |item|
        case item["api_resource"]
        when "monitor"
          case item["type"]
          when "query alert"
            yield item["query"]
          end
        end
      end
    end

    def scan_widgets
      return enum_for(:scan_widgets) unless block_given?

      each_dashboard_widget do |w|
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

    def each_dashboard_widget
      return enum_for(:each_dashboard_widget) unless block_given?

      each do |item|
        if item.is_a?(DD::Native::Model::Dashboard)
          queue = item.widgets.dup

          while (item = queue.shift)
            yield item

            if item.definition.type == "group"
              queue.unshift *item.definition.widgets
            end
          end
        end
      end
    end
  end
end
