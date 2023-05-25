# frozen_string_literal: true
module Kennel
  module TagsValidation
    def validate_json(data)
      super

      # ideally we'd avoid duplicated tags, but that happens regularly when importing existing monitors
      data[:tags] = data[:tags].uniq

      # keep tags clean (TODO: reduce this list)
      bad_tags = data[:tags].grep(/[^A-Za-z:_0-9.\/*@!#-]/)
      invalid! :tags_invalid, "Only use A-Za-z:_0-9./*@!#- in tags (bad tags: #{bad_tags.sort.inspect})" if bad_tags.any?
    end
  end
end
