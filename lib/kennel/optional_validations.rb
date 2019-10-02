# frozen_string_literal: true
module Kennel
  module OptionalValidations
    def self.included(base)
      base.settings :validate
      base.defaults(validate: -> { true })
    end

    private

    def validate_json(data)
      bad = Kennel::Utils.all_keys(data).grep_v(Symbol)
      return if bad.empty?
      invalid!(
        "Only use Symbols as hash keys to avoid permanent diffs when updating.\n" \
        "Change these keys to be symbols (usually 'foo' => 1 --> 'foo': 1)\n" \
        "#{bad.map(&:inspect).join("\n")}"
      )
    end
  end
end
