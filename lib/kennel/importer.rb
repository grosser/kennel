# frozen_string_literal: true

module Kennel
  class Importer
    SORT_ORDER = [:title, :id, :description, :template_variables].freeze

    # TODO: make model diff normalization reusable
    IGNORED = Models::Base::READONLY_ATTRIBUTES - [:id] + [:created_by, :read_only]

    def initialize(api)
      @api = api
    end

    def import(resource, id)
      data = @api.show(resource, id)
      case resource
      when "dash"
        data = data[:dash]
        IGNORED.each { |k| data.delete(k) }
        <<~RUBY
          Kennel::Models::Dash.new(
            self,
            #{pretty_print(data).lstrip}
          )
        RUBY
      else
        raise ArgumentError, "#{resource} is not supported"
      end
    end

    private

    def pretty_print(hash)
      list = hash.sort_by { |k, _| SORT_ORDER.index(k) || 999 }
      list.map do |k, v|
        case v
        when Hash, Array
          pretty = JSON.pretty_generate(v)
            .gsub(/(^\s*)"(.*?)":/, "\\1\\2:") # "foo": 1 -> foo: 1
            .gsub(/^/, "    ") # indent
          "  #{k}: -> {\n#{pretty}\n  }"
        else
          "  #{k}: -> { #{v.inspect} }"
        end
      end.join(",\n")
    end
  end
end
