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

      # screen never did that, but dashboard now does it
      def validate_template_variables(*)
      end

      # screen never did that, but dashboard now does it
      def validate_not_setting_unsettable(*)
      end

      def render_widgets
        widgets = super
        widgets.map! do |widget|
          widget = widget_defaults(widget[:type]).merge(widget)

          if widget[:tile_def]
            widget.merge!(widget.delete(:tile_def))
            widget.delete :viz
          end

          widget.delete(:status)

          if timeframe = widget.delete(:timeframe)
            widget[:time] = { live_span: timeframe }
          end

          supports_title = false

          case widget[:type]
          when "free_text"
            [:title_size, :title_align, :title, :title_text, :font_size].each { |a| widget.delete(a) }
          when "timeseries"
            rename widget, :show_legend, :legend
            supports_title = true
            if ax = widget[:yaxis]
              rename ax, :include_zero, :includeZero
            end
            widget.delete(:xaxis) if widget[:xaxis] == {}
            widget[:markers]&.each do |m|
              rename m, :display_type, :type
              m.delete(:dim)
              m.delete(:val)
            end
            # TODO: datadog bug dashboards api does not return conditional_formats
          when "manage_status"
            [:react_header, :showTitle, :userEditedTitle].each { |a| widget.delete(a) }
            rename widget, :title, :titleText
            rename widget, :hide_zero_counts, :hideZeroCounts
            rename widget, :title_size, :titleSize
            rename widget, :title_align, :titleAlign
            rename widget, :color_preference, :colorPreference
            rename widget, :display_format, :displayFormat
            widget[:query] = widget[:params].delete(:text)
            widget.merge!(widget.delete(:params))
          when "uptime"
            widget[:sli_type] ||= "time"
            widget[:source] ||= "single_monitor"
            rename widget, :group_type, :groupType
            widget[:monitor_ids] = [widget.delete(:monitor)].compact.map { |id| id.is_a?(Hash) ? id.fetch(:id) : id }
            if widget[:rules]
              widget[:conditional_formats] = widget.delete(:rules).values.reverse.map do |rule|
                rule[:palette] = rule.delete(:color)
                rule[:value] = rule.delete(:threshold)
                rule[:comparator] ||= "<"
                rule
              end
            end
          when "alert_graph"
            supports_title = true
            widget[:viz_type] = "timeseries"
          when "note"
            rename widget, :content, :html
            widget.delete :bgcolor
            rename widget, :show_tick, :tick
          when "query_value"
            supports_title = true
            widget.delete(:font_size)
            widget[:precision] ||= 2 # maybe better as dashboard default
          when "toplist"
            supports_title = true
            widget[:requests]&.each do |r|
              r.delete(:type) if r[:type] == "lines"
            end
          when "image", "iframe"
            widget.delete(:title)
            widget.delete(:title_text)
            widget.delete(:margin)
          end

          if widget[:title] == false
            has_title = false
            # previously title would be returned even if it was diabled
            widget.delete(:title)
            widget.delete(:title_text)
          elsif supports_title
            has_title = true
          end
          rename widget, :title, :title_text

          widget[:height] += 2 if supports_title

          if has_title
            widget[:title] = "" if widget[:title] == true # idk weird stuff ...
            widget[:title] ||= ""
          else
            [:title_size].each { |a| widget.delete(a) }
          end

          widget.delete(:add_timeframe)

          widget[:title_size] = widget[:title_size].to_s if widget[:title_size]

          widget[:requests]&.each do |r|
            rename r, :display_type, :type
            r.delete :display_type unless r[:display_type]
            if style = r[:style]
              rename style, :line_type, :type
              rename style, :line_width, :width
            end
          end

          {
            definition: widget,
            layout: { y: widget.delete(:y), x: widget.delete(:x), width: widget.delete(:width), height: widget.delete(:height) }
          }
        end
      end

      def rename(hash, to, from)
        hash[to] = hash.delete(from) if hash.key?(from)
      end

      def widget_defaults(type)
        basics = {
          title_size: "16",
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

      def self.normalize(expected, actual)
        super

        # conditional_formats is randomly sorted ... avoid diff
        expected[:widgets].each_with_index do |w, wi|
          if format = w[:definition][:conditional_formats]
            format.sort_by! { |m| actual.dig(:widgets, wi, :definition, :conditional_formats)&.index(m) || 999 }
          end
        end
      end
    end
  end
end
