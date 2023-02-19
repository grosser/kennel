# frozen_string_literal: true

module Kennel
  module PredicateAccessors
    def self.included(into)
      into.extend(::Kennel::PredicateAccessors::ClassMethods)
    end

    module ClassMethods
      def attr_reader(*symbols)
        symbols.each do |sym|
          if sym.to_s.end_with?("?")
            define_method(sym) { !!instance_variable_get("@#{sym.to_s.chop}") }
          else
            super(sym)
          end
        end
      end
    end
  end
end
