# frozen_string_literal: true

module Kennel
  class Downloader
    def initialize(api)
      @api = api
      @mutex = Mutex.new
    end

    def all_by_class
      @mutex.synchronize { @all_by_class ||= download }
    end

    attr_reader :time_taken

    private

    def download
      t0 = Time.now
      Utils.parallel(Models::Record.subclasses) do |klass|
        results = @api.list(klass.api_resource, with_downtimes: false) # lookup monitors without adding unnecessary downtime information
        results = results[results.keys.first] if results.is_a?(Hash) # dashboards are nested in {dashboards: []}
        [klass, results]
      end.to_h.tap do
        @time_taken = Time.now - t0
      end
    end
  end
end
