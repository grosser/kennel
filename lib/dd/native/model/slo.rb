# frozen_string_literal: true

module DD
  module Native
    class Model
      class SLO < Model
        REQUIRED_KEYS = ["id", "created_at", "modified_at",

                         "creator", "description", "monitor_tags", "name", "tags",
                         "thresholds", "timeframe", "type",
                         "type_id"
        ].freeze

        OPTIONAL_KEYS = ["query", "target_threshold", "warning_threshold",
                         "monitor_ids",
                         "groups"
        ].freeze

        attr_reader *REQUIRED_KEYS, *OPTIONAL_KEYS

        #  [DD::Native::Model::SLO, "creator", Hash]=>3815,
        #  [DD::Native::Model::SLO, "monitor_tags", Array]=>3815,
        #  [DD::Native::Model::SLO, "tags", Array]=>3815,
        #  [DD::Native::Model::SLO, "thresholds", Array]=>3815,
        #  [DD::Native::Model::SLO, "query", Hash]=>2007,
        #  [DD::Native::Model::SLO, "monitor_ids", Array]=>1808,
        #  [DD::Native::Model::SLO, "groups", Array]=>54,
      end
    end
  end
end
