# frozen_string_literal: true

module Kennel
  module AttrPredicate
    def self.included(into)
      into.extend(ClassMethods)
    end

    module ClassMethods
      def attr_predicate(*symbols)
        symbols.each do |sym|
          if name = sym.to_s[/\A(\w+)\?\z/, 1]
            define_method(sym) { !!instance_variable_get("@#{name}") }
          else
            raise NameError, "Bad predicate name #{sym}"
          end
        end
      end
    end
  end
end
