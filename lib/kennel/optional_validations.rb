# frozen_string_literal: true
module Kennel
  module OptionalValidations
    def self.included(base)
      base.settings :validate
      base.defaults(validate: -> { true })
    end

    def self.valid?(parts)
      parts_with_errors = parts.reject do |part|
        part.filtered_validation_errors.empty?
      end

      return true if parts_with_errors.empty?

      Kennel.err.puts
      parts_with_errors.sort_by(&:safe_tracking_id).each do |part|
        part.filtered_validation_errors.each do |err|
          Kennel.err.puts "#{part.safe_tracking_id} #{err.text}"
        end
      end
      Kennel.err.puts

      false
    end

    private

    def validate_json(data)
      bad = Kennel::Utils.all_keys(data).grep_v(Symbol).sort.uniq
      return if bad.empty?
      invalid!(
        "Only use Symbols as hash keys to avoid permanent diffs when updating.\n" \
        "Change these keys to be symbols (usually 'foo' => 1 --> 'foo': 1)\n" \
        "#{bad.map(&:inspect).join("\n")}"
      )
    end

    def filter_validation_errors
      if validate
        unfiltered_validation_errors
      elsif unfiltered_validation_errors.empty?
        msg = "`validate` is set to false, but there are no validation errors to suppress. Remove `validate: false`"

        mode = ENV.fetch("UNNECESSARY_VALIDATE_FALSE") do
          if ENV.key?("PROJECT") || ENV.key?("TRACKING_ID")
            "fail"
          else
            nil
          end
        end

        if mode == "fail"
          [ValidationMessage.new(msg)]
        else
          Kennel.out.puts "#{safe_tracking_id} #{msg}" if mode == "show"
          []
        end
      else
        mode = ENV.fetch("SUPPRESSED_ERRORS", "ignore")

        if mode == "fail"
          unfiltered_validation_errors
        else
          if mode == "show"
            unfiltered_validation_errors.each do |err|
              Kennel.out.puts "#{safe_tracking_id} `validate: false` suppressing error: #{err.text.gsub("\n", " ")}"
            end
          end

          []
        end
      end
    end
  end
end
