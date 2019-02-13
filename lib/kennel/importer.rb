# frozen_string_literal: true

module Kennel
  class Importer
    SORT_ORDER = [:title, :name, :board_title, :id, :kennel_id, :query, :message, :description, :template_variables].freeze

    def initialize(api)
      @api = api
    end

    def import(resource, id)
      model =
        begin
          Kennel::Models.const_get(resource.capitalize)
        rescue NameError
          raise ArgumentError, "#{resource} is not supported"
        end

      data = @api.show(model.api_resource, id)
      data = data[resource.to_sym] || data
      id = data.fetch(:id) # store numerical id returned from the api
      model.normalize({}, data)
      data[:id] = id
      data[:kennel_id] = "pick_something_descriptive"

      # flatten monitor options so they are all on the base
      if resource == "monitor"
        data.merge!(data.delete(:options))
        data.merge!(data.delete(:thresholds) || {})
        data = data.slice(*model.instance_methods)
      end

      <<~RUBY
        #{model.name}.new(
          self,
          #{pretty_print(data).lstrip}
        )
      RUBY
    end

    private

    def pretty_print(hash)
      list = hash.sort_by { |k, _| [SORT_ORDER.index(k) || 999, k] } # important to the front and rest deterministic
      list.map do |k, v|
        case v
        when Hash, Array
          # update answer here when changing https://stackoverflow.com/questions/8842546/best-way-to-pretty-print-a-hash
          # (exclude indent line)
          pretty = JSON.pretty_generate(v)
            .gsub(": null", ": nil")
            .gsub(/(^\s*)"([a-zA-Z][a-zA-Z\d_]*)":/, "\\1\\2:") # "foo": 1 -> foo: 1
            .gsub(/(^\s*)(".*?"):/, "\\1\\2 =>") # "123": 1 -> "123" => 1
            .gsub(/^/, "    ") # indent

          "  #{k}: -> {\n#{pretty}\n  }"
        else
          "  #{k}: -> { #{v.inspect} }"
        end
      end.join(",\n")
    end
  end
end
