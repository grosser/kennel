# frozen_string_literal: true
module Kennel
  module OptionalValidations
    def self.included(base)
      base.settings :validate
      base.defaults(validate: -> { true })
    end

    # https://stackoverflow.com/questions/20235206/ruby-get-all-keys-in-a-hash-including-sub-keys/53876255#53876255
    def self.all_keys(items)
      case items
      when Hash then items.keys + items.values.flat_map { |v| all_keys(v) }
      when Array then items.flat_map { |i| all_keys(i) }
      else []
      end
    end

    private

    def validate_json(data)
      bad = OptionalValidations.all_keys(data).grep_v(Symbol)
      return if bad.empty?
      invalid!(
        "Only use Symbols as hash keys to avoid permanent diffs when updating.\n" \
        "Change these keys to be symbols (usually 'foo' => 1 --> 'foo': 1)\n" \
        "#{bad.map(&:inspect).join("\n")}"
      )
    end
  end
end
