# frozen_string_literal: true

module Kennel
  module Models
    module Built
      class Record
        def initialize(
          as_json:,
          project:,
          unbuilt_class:,
          tracking_id:,
          id:,
          unfiltered_validation_errors:
        )
          @as_json = as_json
          @project = project
          @unbuilt_class = unbuilt_class
          @tracking_id = tracking_id.freeze
          @id = id.freeze
          @unfiltered_validation_errors = unfiltered_validation_errors
        end

        attr_reader :as_json, :project, :unbuilt_class, :tracking_id, :id, :unfiltered_validation_errors

        def filtered_validation_errors
          []
        end

        # Can raise DisallowedUpdateError
        def validate_update!(*)
        end

        def invalid_update!(field, old_value, new_value)
          raise DisallowedUpdateError, "#{tracking_id} Datadog does not allow update of #{field} (#{old_value.inspect} -> #{new_value.inspect})"
        end

        def diff(actual)
          expected = as_json
          expected.delete(:id)

          unbuilt_class.normalize(expected, actual)

          # strict: ignore Integer vs Float
          # similarity: show diff when not 100% similar
          # use_lcs: saner output
          Hashdiff.diff(actual, expected, use_lcs: false, strict: false, similarity: 1)
        end

        def resolve_linked_tracking_ids!(*)
        end

        def add_tracking_id
          json = as_json
          if unbuilt_class.parse_tracking_id(json)
            raise "#{tracking_id} Remove \"-- #{unbuilt_class::MARKER_TEXT}\" line from #{unbuilt_class::TRACKING_FIELD} to copy a resource"
          end
          json[unbuilt_class::TRACKING_FIELD] =
            "#{json[unbuilt_class::TRACKING_FIELD]}\n" \
          "-- #{unbuilt_class::MARKER_TEXT} #{tracking_id} in #{project.class.file_location}, do not modify manually".lstrip
        end

        def remove_tracking_id
          unbuilt_class.remove_tracking_id(as_json)
        end

        def resolve(value, type, id_map, force:)
          return value unless tracking_id?(value)
          resolve_link(value, type, id_map, force: force)
        end

        private

        def tracking_id?(id)
          id.is_a?(String) && id.include?(":")
        end

        def resolve_link(sought_tracking_id, sought_type, id_map, force:)
          if id_map.new?(sought_type.to_s, sought_tracking_id)
            if force
              raise UnresolvableIdError, <<~MESSAGE
                #{tracking_id} #{sought_type} #{sought_tracking_id} was referenced but is also created by the current run.
                It could not be created because of a circular dependency. Try creating only some of the resources.
              MESSAGE
            else
              nil # will be re-resolved after the linked object was created
            end
          elsif id = id_map.get(sought_type.to_s, sought_tracking_id)
            id
          else
            raise UnresolvableIdError, <<~MESSAGE
              #{tracking_id} Unable to find #{sought_type} #{sought_tracking_id}
              This is either because it doesn't exist, and isn't being created by the current run;
              or it does exist, but is being deleted.
            MESSAGE
          end
        end
      end
    end
  end
end
