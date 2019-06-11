# frozen_string_literal: true
#
# Reuses dashboard by translating old definitions, migrate all customers and then remove this
module Kennel
  module Models
    class Screen < Dashboard
      settings :board_title

      def layout_type
        "free"
      end

      def title
        board_title
      end

      def render_widgets
        widgets = super
        widgets.map! do |widget|
          widget = widget_defaults(widget[:type]).merge(widget)

          case widget[:type]
          when "free_text"
            [:title_size, :title_align, :title_text, :title].each { |a| widget.delete(a) } # never had a title
          when "timeseries"
            widget.merge!(widget.delete(:tile_def))
            widget.delete :viz
            widget[:title] = widget.delete(:title_text)
            widget[:title_size] = widget.delete(:title_size).to_s
            widget[:time] ||= { live_span: widget.delete(:timeframe) }
            widget[:show_legend] = widget.delete(:legend)
            widget[:height] += 2
          end

          if widget[:requests]
            widget[:requests] = widget[:requests].dup.each do |r|
              r[:display_type] = r.delete(:type)
            end
          end

          {
            definition: widget,
            layout: { y: widget.delete(:y), x: widget.delete(:x), width: widget.delete(:width), height: widget.delete(:height) }
          }
        end
      end

      def widget_defaults(type)
        basics = {
          title_size: 16,
          title_align: "left",
          height: 20,
          width: 30
        }

        custom =
          case type
          when "free_text"
            {
              font_size: "auto",
              text_align: "left",
              color: "#4d4d4d"
            }
          when "timeseries"
            {
              title: true,
              legend: false,
              legend_size: "0",
              show_legend: false
            }
          else
            {}
          end

        basics.merge(custom)
      end
    end
  end
end
