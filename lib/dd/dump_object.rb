# frozen_string_literal: true

require_relative "native/model"

module DD
  class DumpObject < Native::Model
    TYPE_MAP = {
      monitor: Monitor,
      slo: SLO,
      dashboard: Dashboard,
      "synthetics/tests": SyntheticsTests
    }

    def self.new(item)
      api_resource = item.fetch("api_resource")
      k_klass = item.fetch("klass", nil)
      tracking_id = item.fetch("tracking_id", nil)
      url = item.fetch("url", nil)

      klass = TYPE_MAP.fetch(api_resource.to_sym)

      klass.from_single(
        item.except("api_resource", "klass", "tracking_id", "url")
      )
    end
  end
end
