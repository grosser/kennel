# frozen_string_literal: true

module Kennel
  class Importer
    TITLES = [:name, :title, :board_title].freeze
    SORT_ORDER = [*TITLES, :id, :kennel_id, :type, :tags, :query, :message, :description, :template_variables].freeze

    def initialize(api)
      @api = api
    end

    def import(resource, id)
      begin
        model =
          begin
            Kennel::Models.const_get(resource.capitalize)
          rescue NameError
            raise ArgumentError, "#{resource} is not supported"
          end
        data = @api.show(model.api_resource, id)
      rescue StandardError => e
        retried ||= 0
        retried += 1
        raise e if retried != 1 || resource != "dash" || !e.message.match?(/No \S+ matches that/)
        resource = "screen"
        retry
      end

      data = data[resource.to_sym] || data
      id = data.fetch(:id) # store numerical id returned from the api
      model.normalize({}, data)
      data[:id] = id
      data[:kennel_id] = Kennel::Utils.parameterize(data.fetch(TITLES.detect { |t| data[t] }))

      if resource == "monitor"
        # flatten monitor options so they are all on the base
        data.merge!(data.delete(:options))
        data.merge!(data.delete(:thresholds) || {})
        data = data.slice(*model.instance_methods)

        # make query use critical method if it matches
        critical = data[:critical]
        query = data[:query]
        if query && critical
          query.sub!(/([><=]) (#{Regexp.escape(critical.to_f.to_s)}|#{Regexp.escape(critical.to_i.to_s)})$/, "\\1 \#{critical}")
        end
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
      list = hash.sort_by { |k, _| [SORT_ORDER.index(k) || 999, k] } # important to the front and rest deterministic
      list.map do |k, v|
        pretty_value =
          if v.is_a?(Hash) || (v.is_a?(Array) && !v.all? { |e| e.is_a?(String) })
            # update answer here when changing https://stackoverflow.com/questions/8842546/best-way-to-pretty-print-a-hash
            # (exclude last indent gsub)
            pretty = JSON.pretty_generate(v)
              .gsub(": null", ": nil")
              .gsub(/(^\s*)"([a-zA-Z][a-zA-Z\d_]*)":/, "\\1\\2:") # "foo": 1 -> foo: 1
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
  end
end
