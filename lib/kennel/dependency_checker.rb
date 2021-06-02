module Kennel
  module DependencyChecker

    TYPE_DASHBOARD = "dashboard"
    TYPE_MONITOR = "monitor"
    TYPE_SLO = "slo"
    TYPE_SYNTHETIC = "synthetics/tests"

    class HashStruct < Struct
      def to_json(*args)
        to_h.to_json(*args)
      end
    end

    Dependency = HashStruct.new(:a, :b, keyword_init: true)
    ResourceId = HashStruct.new(:resource, :id, keyword_init: true)
    KennelId = HashStruct.new(:id, :in, keyword_init: true)

  end
end

require_relative 'dependency_checker/item_utils'
require_relative 'dependency_checker/collector'
require_relative 'dependency_checker/reporter'
