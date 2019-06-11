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

          if yaxis = w[:definition][:yaxis]
            rename yaxis, :include_zero, :includeZero
          end

          w[:definition][:markers]&.each { |m| rename m, :display_type, :type }

          w[:definition][:requests].each do |r|
            rename r, :display_type, :type
            if style = r[:style]
              rename style, :line_type, :type
              rename style, :line_width, :width
            end

            # hash to array
            if metadata = r[:metadata]
              r[:metadata] = metadata.map { |k, v| { alias_name: v[:alias].to_s, expression: k.to_s } }
            end

            if apm_query = r[:apm_query]
              rename apm_query, :group_by, :groupBy
            end
          end
        end
      end

      def self.normalize(expected, actual)
        super

        # metadata needs to be in same sort order as live to avoid diff (was hash before so we had random ordering)
        expected[:widgets].each_with_index do |w, wi|
          w[:definition][:requests].each_with_index do |r, ri|
            if metadata = r[:metadata]
              metadata.sort_by! { |m| actual.dig(:widgets, wi, :definition, :requests, ri, :metadata)&.index(m) || 999 }
            end
          end
        end
      end

      def rename(hash, to, from)
        hash[to] = hash.delete(from) if hash.key?(from)
      end
    end
  end
end
