# frozen_string_literal: true
# encapsulates knowledge around how the api works
# especially 1-off weirdness that should not lak into other parts of the code
module Kennel
  class Downloader
    def initialize(api)
      @api = api
      @mutex = Mutex.new
    end

    def definitions
      @mutex.synchronize { @definitions ||= download_definitions }
    end

    attr_reader :time_taken

    private

    def download_definitions
      t0 = Time.now
      Utils.parallel(Models::Record.subclasses) do |klass|
        results = @api.list(klass.api_resource, with_downtimes: false) # lookup monitors without adding unnecessary downtime information
        results = results[results.keys.first] if results.is_a?(Hash) # dashboards are nested in {dashboards: []}
        results.each { |a| cache_metadata(a, klass) }
      end.flatten(1).tap do
        @time_taken = Time.now - t0
      end
    end

    def cache_metadata(a, klass)
      a[:klass] = klass
      a[:tracking_id] = a.fetch(:klass).parse_tracking_id(a)
    end
  end
end
