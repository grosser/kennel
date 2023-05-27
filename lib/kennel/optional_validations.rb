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
      parts_with_errors.sort_by(&:safe_tracking_id).each do |part|
        part.filtered_validation_errors.each do |err|
          Kennel.err.puts "#{part.safe_tracking_id} [#{err.tag.inspect}] #{err.text.gsub("\n", " ")}"
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

    def filter_validation_errors
      errors = unfiltered_validation_errors
      ignored_tags = ignored_errors

      if errors.empty? # 95% case, so keep it fast
        if ignored_tags.empty?
          []
        else
          # tell users to remove the whole line and not just an element
          [
            ValidationMessage.new(
              UNIGNORABLE,
              "`ignored_errors` is non-empty, but there are no errors to ignore. Remove `ignored_errors`"
            )
          ]
        end
      else
        reported_errors =
          if ENV["NO_IGNORED_ERRORS"] # let users see what errors are suppressed
            errors
          else
            errors.select { |err| err.tag == UNIGNORABLE || !ignored_tags.include?(err.tag) }
          end

        # let users know when they can remove an ignore
        unused_ignored_tags = ignored_tags - errors.map(&:tag)
        if unused_ignored_tags.any?
          reported_errors << ValidationMessage.new(
            UNIGNORABLE,
            "Unused ignores #{unused_ignored_tags.map(&:inspect).sort.uniq.join(" ")}. Remove these from `ignored_errors`"
          )
        end

        reported_errors
      end
    end
  end
end
