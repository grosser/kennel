# frozen_string_literal: true

module Kennel
  module Compatibility
    def self.included(into)
      class << into
        def build_default
          Kennel::Engine.new
        end

        def instance
          @instance ||= build_default
        end

        private

        def api
          instance.send(:api)
        end
      end
    end
  end
end
