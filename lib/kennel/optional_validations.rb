# frozen_string_literal: true
module Kennel
  module OptionalValidations
    def self.included(base)
      base.settings :validate, :skip_validations
      base.defaults(validate: true, skip_validations: -> { [] })
    end

    private

    def validate_json(data)
      bad = Kennel::Utils.all_keys(data).grep_v(Symbol)
      return if bad.empty?
      invalid!(
        :hash_keys_must_be_symbols,
        "Only use Symbols as hash keys to avoid permanent diffs when updating.\n" \
        "Change these keys to be symbols (usually 'foo' => 1 --> 'foo': 1)\n" \
        "#{bad.map(&:inspect).join("\n")}"
      )
    end
  end
end
