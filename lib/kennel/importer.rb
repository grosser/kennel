# frozen_string_literal: true

module Kennel
  class Importer
    TITLES = [:name, :title].freeze
    SORT_ORDER = [*TITLES, :id, :kennel_id, :type, :tags, :query, :message, :description, :template_variables].freeze

    def initialize(api)
      @api = api
    end

    def import(resource, id)
      if ["screen", "dash"].include?(resource)
        raise ArgumentError, "resource 'screen' and 'dash' are deprecated, use 'dashboard'"
      end

      model =
        begin
          Kennel::Models.const_get(resource.capitalize)
        rescue NameError
          raise ArgumentError, "#{resource} is not supported"
        end

      data = @api.show(model.api_resource, id)
      id = data.fetch(:id) # keep native value
      model.normalize({}, data) # removes id
      data[:id] = id

      title_field = TITLES.detect { |t| data[t] }
      title = data.fetch(title_field)
      title.tr!(Kennel::Models::Base::LOCK, "") # avoid double lock icon
      data[:kennel_id] = Kennel::Utils.parameterize(title)

      if resource == "monitor"
        # flatten monitor options so they are all on the base
        data.merge!(data.delete(:options))
        data.merge!(data.delete(:thresholds) || {})
        [:notify_no_data, :notify_audit].each { |k| data.delete(k) if data[k] } # monitor uses true by default
        data = data.slice(*model.instance_methods)

        # make query use critical method if it matches
        critical = data[:critical]
        query = data[:query]
        if query && critical
          query.sub!(/([><=]) (#{Regexp.escape(critical.to_f.to_s)}|#{Regexp.escape(critical.to_i.to_s)})$/, "\\1 \#{critical}")
        end
      end

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

            "\n#{pretty}\n  "
          elsif k == :message
            "\n    <<~TEXT\n#{v.each_line.map { |l| l.strip.empty? ? "\n" : "      #{l}" }.join}\n    TEXT\n  "
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
