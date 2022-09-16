# frozen_string_literal: true

module Kennel
  module Compatibility
    def self.included(into)
      class << into
        %I[out err strict_imports ].each do |sym|
          define_method(sym) do |*args|
            warn "Using legacy Kennel.#{sym} from #{caller[1..1]}"
            instance.config.public_send(sym, *args)
          end

          define_method("#{sym}=") do |value|
            warn "Using even-more-legacy Kennel.#{sym}= from #{caller[1..1]}"
            instance.config.instance_variable_set("@#{sym}", value)
          end
        end

        %I[generate plan update].each do |sym|
          define_method(sym) do |*args|
            warn "Using legacy Kennel.#{sym} from #{caller[1..1]}"
            instance.public_send(sym, *args)
          end
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
