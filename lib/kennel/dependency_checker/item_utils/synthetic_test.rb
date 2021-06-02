# frozen_string_literal: true

require_relative './base'

module Kennel
  module DependencyChecker
    class ItemUtils

      class SyntheticTest < Base
        def kennel_id_text
          nil
        end

        def dependencies
          nil
        end

        def url
          "synthetics/details/#{id}"
        end

        def name
          object.fetch(:name)
        end

        def author
          nil
        end

        def tags
          object.fetch(:tags)
        end
      end

    end
  end
end
