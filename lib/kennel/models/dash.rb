# frozen_string_literal: true
#
# Reuses dashboard by translating old definitions, migrate all customers and then remove this
module Kennel
  module Models
    class Dash < Dashboard
      settings :graphs

      defaults(
        graphs: -> { [] }
      )

      def layout_type
        "ordered"
      end

      def widgets
        graphs
      end

      def render_widgets
        widgets = super
        widgets.each do |w|
          w[:definition][:title] ||= w.delete(:title)
          w[:definition][:type] ||= w[:definition].delete(:viz)
          w[:definition][:requests].each do |r|
            r[:display_type] ||= r.delete(:type)
          end
        end
      end
    end
  end
end
