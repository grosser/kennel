# frozen_string_literal: true

module DD
  module Native
    class Model
      class Dashboard < Model
        ID_NAMESPACE = "dashboard"

        REQUIRED_KEYS = ["id", "created_at", "modified_at", "deleted_at", "description", "layout_type",
                "author_handle", "author_name", "is_read_only", "notify_list",
                "restricted_roles", "template_variables", "title", "widgets"].freeze

        OPTIONAL_KEYS = ["template_variable_presets", "reflow_type", "tags"].freeze

        attr_reader *REQUIRED_KEYS, *OPTIONAL_KEYS

        def initialize(item)
          super do
            @widgets = Widget.from_multi(widgets, allow_nil: false)
            @template_variables = TemplateVariable.from_multi(template_variables, allow_nil: true)

            raise unless notify_list.nil? || notify_list.all? { |s| s.is_a?(String) } # email addresses
            raise unless restricted_roles.nil? || restricted_roles.all? { |s| s.is_a?(String) } # UUIDs
          end
        end

        # [DD::Native::Model::Dashboard, "notify_list", Array]=>8378,
        #  [DD::Native::Model::Dashboard, "template_variable_presets", Array]=>438,
        # [DD::Native::Model::Dashboard, "restricted_roles", Array]=>11258,
        #  [DD::Native::Model::Dashboard, "template_variables", Array]=>10518,
        #  [DD::Native::Model::Dashboard, "widgets", Array]=>11258,
        #  [DD::Native::Model::Dashboard, "tags", Array]=>2782,
      end
    end
  end
end
