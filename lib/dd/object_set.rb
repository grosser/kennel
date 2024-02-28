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

      new(items)
    end

    def initialize(items)
      push(*items)

      @lookup_index =
        begin
          each_with_object({}) do |item, h|
            klass = item.class::ID_NAMESPACE
            (h[klass] || (h[klass] = {}))[item.id.to_s] = item
          end.freeze
        end
      @lookup_index.values.each(&:freeze)

      freeze
    end

    def inspect
      "#<ObjectSet of #{count} items>"
    end

    alias :pretty_inspect :inspect

    def pretty_print(_)
      puts inspect
    end

    def lookup(klass, id)
      @lookup_index.dig(klass, id.to_s)
    end

    def each_monitor(type = nil)
      return enum_for(:each_monitor, type) unless block_given?

      includeable_type = (type if type.respond_to?(:include?))

      each do |item|
        if item.is_a?(DD::Native::Model::Monitor)
          yield item if type.nil? || (type === item.type) \
              || includeable_type&.include?(item.type)
        end
      end
    end

    def each_dashboard_widget(type = nil)
      return enum_for(:each_dashboard_widget, type) unless block_given?

      includeable_type = (type if type.respond_to?(:include?))

      each do |item|
        if item.is_a?(DD::Native::Model::Dashboard)
          queue = item.widgets.dup

          while (item = queue.shift)
            yield item if type.nil? || (type === item.type) \
              || includeable_type&.include?(item.type)

            if item.type == "group"
              queue.unshift *item.definition.widgets
            end
          end
        end
      end
    end
  end
end
