# frozen_string_literal: true

# Manage logging index configuration and ordering
# https://docs.datadoghq.com/api/?lang=python#logs-indexes
module Kennel
  module Models
    class LogsIndex < Base
      @@index_order = []
      class << self
        def sorted
          @@index_order.reject { |i| i.nil? }
        end

        def reset!
          @@index_order = []
        end
      end

      settings(:filter, :exclusion_filters, :order)
      defaults(
        filter: -> { {query: '*'} },
        exclusion_filters: -> { [] },
        order: -> { -1 }
      )

      def initialize(name, *args)
        @name = name
        super(*args)
        @@index_order.insert(self.order, @name)
      end

      def as_json
        @as_json ||= {
          name: @name,
          filter: filter,
          exclusion_filters: exclusion_filters
        }
      end
    end
  end
end
