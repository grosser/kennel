# frozen_string_literal: true

module Kennel
  class Importer
    TITLES = [:name, :title].freeze
    SORT_ORDER = [*TITLES, :id, :kennel_id, :type, :tags, :query, *Models::Record.subclasses.map { |k| k::TRACKING_FIELDS }, :template_variables].freeze

    def initialize(api)
      @api = api
    end

    def import(resource, id)
      if ["screen", "dash"].include?(resource)
        raise ArgumentError, "resource 'screen' and 'dash' are deprecated, use 'dashboard'"
      end

      model =
        Kennel::Models::Record.subclasses.detect { |c| c.api_resource == resource } ||
        raise(ArgumentError, "#{resource} is not supported")

      data = @api.show(model.api_resource, id)
      id = data.fetch(:id) # keep native value
      model.normalize({}, data) # removes id
      data[:id] = id

      title_field = TITLES.detect { |f| data[f] }
      title = data.fetch(title_field)
      title.tr!(Kennel::Models::Record::LOCK, "") # avoid double lock icon

      # calculate or reuse kennel_id
      data[:kennel_id] =
        if tracking_id = model.parse_tracking_id(data)
          model.remove_tracking_id(data)
          tracking_id.split(":").last
        else
          Kennel::Utils.parameterize(title)
        end

      case resource
      when "monitor"
        # flatten monitor options so they are all on the base which is how Monitor builds them
        data.merge!(data.delete(:options))
        data.merge!(data.delete(:thresholds) || {})

        # clean up values that are the default
        data.delete(:notify_no_data) if data[:notify_no_data] # Monitor uses true by default
        data.delete(:notify_audit) unless data[:notify_audit] # Monitor uses false by default

        # keep all values that are settable
        data = data.slice(*model.instance_methods)

        # make query use critical method if it matches
        critical = data[:critical]
        query = data[:query]
        if query && critical
          query.sub!(/([><=]) (#{Regexp.escape(critical.to_f.to_s)}|#{Regexp.escape(critical.to_i.to_s)})$/, "\\1 \#{critical}")
        end

        # using float in query is not allowed, so convert here
        data[:critical] = data[:critical].to_i if data[:type] == "event alert"

        data[:type] = "query alert" if data[:type] == "metric alert"
      when "dashboard"
        widgets = data[:widgets]&.flat_map { |widget| widget.dig(:definition, :widgets) || [widget] }
        widgets&.each do |widget|
          convert_widget_to_compact_format!(widget)
          dry_up_widget_metadata!(widget)
          (widget.dig(:definition, :markers) || []).each { |m| m[:label]&.delete! " " }
        end
      when "synthetics/tests"
        data[:locations] = :all if data[:locations].sort == Kennel::Models::SyntheticTest::LOCATIONS.sort
      else
        # noop
      end

      data.delete(:tags) if data[:tags] == [] # do not create super + [] call

      # simplify template_variables to array of string when possible
      if vars = data[:template_variables]
        vars.map! { |v| v[:default] == "*" && v[:prefix] == v[:name] ? v[:name] : v }
      end

      pretty = pretty_print(data).lstrip.gsub("\\#", "#")
      <<~RUBY
        #{model.name}.new(
          self,
          #{pretty}
        )
      RUBY
    end

    private

    # reduce duplication in imports by using dry `q: :metadata` when possible
    def dry_up_widget_metadata!(widget)
      (widget.dig(:definition, :requests) || []).each do |request|
        next unless request.is_a?(Hash)
        next unless metadata = request[:metadata]
        next unless query = request[:q]&.dup
        metadata.each do |m|
          next unless exp = m[:expression]
          query.sub!(exp, "")
        end
        request[:q] = :metadata if query.delete(", ") == ""
      end
    end

    # new api format is very verbose, so use old dry format when possible
    def convert_widget_to_compact_format!(widget)
      (widget.dig(:definition, :requests) || []).each do |request|
        next unless request.is_a?(Hash)
        next if request[:formulas] && request[:formulas] != [{ formula: "query1" }]
        next if request[:queries]&.size != 1
        next if request[:queries].any? { |q| q[:data_source] != "metrics" }
        next if widget.dig(:definition, :type) != request[:response_format]
        request.delete(:formulas)
        request.delete(:response_format)
        request[:q] = request.delete(:queries).first.fetch(:query)
      end
    end

    def pretty_print(hash)
      sort_widgets hash

      sort_hash(hash).map do |k, v|
        pretty_value =
          if v.is_a?(Hash) || (v.is_a?(Array) && !v.all? { |e| e.is_a?(String) })
            # update answer here when changing https://stackoverflow.com/questions/8842546/best-way-to-pretty-print-a-hash
            # (exclude last indent gsub)
            pretty = JSON.pretty_generate(v)
              .gsub(": null", ": nil")
              .gsub(/(^\s*)"([a-zA-Z][a-zA-Z\d_]*)":/, "\\1\\2:") # "foo": 1 -> foo: 1
              .gsub(/: \[\n\s+\]/, ": []") # empty arrays on a single line
              .gsub(/^/, "    ") # indent
              .gsub('q: "metadata"', "q: :metadata") # bring symbols back

            "\n#{pretty}\n  "
          elsif k == :message
            "\n    <<~TEXT\n#{v.each_line.map { |l| l.strip.empty? ? "\n" : "      #{l}" }.join}\n      \#{super()}\n    TEXT\n  "
          elsif k == :tags
            " super() + #{v.inspect} "
          else
            " #{v.inspect} "
          end
        "  #{k}: -> {#{pretty_value}}"
      end.join(",\n")
    end

    # sort dashboard widgets + nesting
    def sort_widgets(outer)
      outer[:widgets]&.each do |widgets|
        definition = widgets[:definition]
        definition.replace sort_hash(definition)
        sort_widgets definition
      end
    end

    # important to the front and rest deterministic
    def sort_hash(hash)
      Hash[hash.sort_by { |k, _| [SORT_ORDER.index(k) || 999, k] }]
    end
  end
end
