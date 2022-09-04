module Kennel
  module Compatibility
    def self.included(into)
      class << into
        %I[out out= err err= strict_imports strict_imports= generate plan update].each do |sym|
          define_method(sym) { |*args| default_instance.public_send(sym, *args) }
        end

        private

        def default_instance
          @default_instance ||= Kennel::Engine.new
        end

        def api
          default_instance.send(:api)
        end
      end
    end
  end
end
