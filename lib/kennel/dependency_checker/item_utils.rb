# frozen_string_literal: true

require_relative './item_utils/dashboard'
require_relative './item_utils/monitor'
require_relative './item_utils/slo'
require_relative './item_utils/synthetic_test'

module Kennel
  module DependencyChecker
    class ItemUtils

      def self.new(key, object)
        case key.resource.to_s
        when TYPE_DASHBOARD
          Dashboard.new(key, object)
        when TYPE_MONITOR
          Monitor.new(key, object)
        when TYPE_SLO
          SLO.new(key, object)
        when TYPE_SYNTHETIC
          SyntheticTest.new(key, object)
        else
          raise "Unexpected resource #{key}"
        end
      end

    end
  end
end
