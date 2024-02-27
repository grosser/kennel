# frozen_string_literal: true

module DD
  module Native
    class Model
      class SyntheticsTests < Model
        REQUIRED_KEYS = ["id",
                         "config", "created_at", "creator", "locations", "message",
                         "modified_at", "monitor_id", "name", "options", "status",
                         "type"].freeze

        OPTIONAL_KEYS = ["subtype", "tags"].freeze

        attr_reader *REQUIRED_KEYS, *OPTIONAL_KEYS

        # [DD::Native::Model::SyntheticsTests, "config", Hash]=>278,
        #   [DD::Native::Model::SyntheticsTests, "creator", Hash]=>278,
        #   [DD::Native::Model::SyntheticsTests, "locations", Array]=>278,
        #     [DD::Native::Model::SyntheticsTests, "options", Hash]=>278,
        #   [DD::Native::Model::SyntheticsTests, "tags", Array]=>278}
      end
    end
  end
end
