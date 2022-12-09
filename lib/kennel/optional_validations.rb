# frozen_string_literal: true
module Kennel
  module OptionalValidations
    ValidationMessage = Struct.new(:tag, :text)

    UNIGNORABLE = :unignorable

    def self.included(base)
      base.settings :ignored_errors
      base.defaults(ignored_errors: -> { [] })
    end

    def self.valid?(parts)
      parts_with_errors = parts.reject do |part|
        part.filtered_validation_errors.empty?
      end

      return true if parts_with_errors.empty?

      example_tag = nil

      Kennel.err.puts
      parts_with_errors.sort_by(&:tracking_id).each do |part|
        part.filtered_validation_errors.each do |err|
          Kennel.err.puts "#{part.tracking_id} [#{err.tag.inspect}] #{err.text.gsub("\n", " ")}"
          example_tag = err.tag unless err.tag == :unignorable
        end
      end
      Kennel.err.puts

      Kennel.err.puts <<~MESSAGE if example_tag
        If a particular error cannot be fixed, it can be marked as ignored via `ignored_errors`, e.g.:
          Kennel::Models::Monitor.new(
            ...,
            ignored_errors: [#{example_tag.inspect}]
          )

      MESSAGE

      false
    end

    private

    def validate_json(data)
      bad = Kennel::Utils.all_keys(data).grep_v(Symbol).sort.uniq
      return if bad.empty?
      invalid!(
        :hash_keys_must_be_symbols,
        "Only use Symbols as hash keys to avoid permanent diffs when updating.\n" \
        "Change these keys to be symbols (usually 'foo' => 1 --> 'foo': 1)\n" \
        "#{bad.map(&:inspect).join("\n")}"
      )
    end

    def filter_validation_errors
      if unfiltered_validation_errors.empty?
        if ignored_errors.empty?
          []
        else
          [ValidationMessage.new(UNIGNORABLE, "`ignored_errors` is non-empty, but there are no errors to ignore. Remove `ignored_errors`")]
        end
      else
        to_report =
          if ENV["NO_IGNORED_ERRORS"]
            # Turn off all suppressions, to see what errors are actually being suppressed
            unfiltered_validation_errors
          else
            unfiltered_validation_errors.reject do |err|
              err.tag != UNIGNORABLE && ignored_errors.include?(err.tag)
            end
          end

        unused_ignores = ignored_errors - unfiltered_validation_errors.map(&:tag)

        unless unused_ignores.empty?
          to_report << ValidationMessage.new(UNIGNORABLE, "Unused ignores #{unused_ignores.map(&:inspect).sort.uniq.join(" ")}. Remove these from `ignored_errors`")
        end

        to_report
      end
    end
  end
end
