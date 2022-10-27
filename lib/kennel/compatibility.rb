# frozen_string_literal: true

module Kennel
  module Compatibility
    def self.included(into)
      class << into
        %I[out out= err err= strict_imports strict_imports=].each do |sym|
          define_method(sym) { |*args| instance.public_send(sym, *args) }
        end

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
