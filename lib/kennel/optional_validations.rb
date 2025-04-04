# frozen_string_literal: true
module Kennel
  module OptionalValidations
    ValidationMessage = Struct.new(:tag, :text)

    UNIGNORABLE = :unignorable
    UNUSED_IGNORES = :unused_ignores

    def self.included(base)
      base.settings :ignored_errors
      base.defaults(ignored_errors: -> { [] })
      base.attr_reader :validation_errors
    end

    def initialize(...)
      super
      @validation_errors = []
    end

    def invalid!(tag, message)
      validation_errors << ValidationMessage.new(tag, message)
    end

    def self.valid?(parts)
      parts_with_errors = parts.map { |p| [p, filter_validation_errors(p)] }
      return true if parts_with_errors.all? { |_, errors| errors.empty? }

      # print errors in order
      example_tag = nil
      Kennel.err.puts
      parts_with_errors.sort_by! { |p, _| p.safe_tracking_id }
      parts_with_errors.each do |part, errors|
        errors.each do |err|
          Kennel.err.puts "#{part.safe_tracking_id} [#{err.tag.inspect}] #{err.text.gsub("\n", " ")}"
          example_tag = err.tag unless err.tag == :unignorable
        end
      end
      Kennel.err.puts

      if example_tag
        Kennel.err.puts <<~MESSAGE
          If a particular error cannot be fixed, it can be marked as ignored via `ignored_errors`, e.g.:
            Kennel::Models::Monitor.new(
              ...,
              ignored_errors: [#{example_tag.inspect}]
            )

        MESSAGE
      end

      false
    end

    def self.filter_validation_errors(part)
      errors = part.validation_errors
      ignored_tags = part.ignored_errors

      if errors.empty? # 95% case, so keep it fast
        if ignored_tags.empty? || ignored_tags.include?(UNUSED_IGNORES)
          []
        else
          # tell users to remove the whole line and not just an element
          [
            ValidationMessage.new(
              UNUSED_IGNORES,
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

        # let users know when they can remove an ignore ... unless they don't care (for example for a generic monitor)
        unless ignored_tags.include?(UNUSED_IGNORES)
          unused_ignored_tags = ignored_tags - errors.map(&:tag)
          if unused_ignored_tags.any?
            reported_errors << ValidationMessage.new(
              UNUSED_IGNORES,
              "Unused ignores #{unused_ignored_tags.map(&:inspect).sort.uniq.join(" ")}. Remove these from `ignored_errors`"
            )
          end
        end

        reported_errors
      end
    end
  end
end
