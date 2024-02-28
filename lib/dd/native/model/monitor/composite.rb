# frozen_string_literal:true

module DD
  module Native
    class Model
      class Monitor
        class Composite < Monitor
          def referenced_monitor_ids
            query.scan(/\d+/).map(&:to_i).sort.uniq
          end

          def referenced_monitors(set)
            referenced_monitor_ids.map do |id|
              set.lookup(Monitor::ID_NAMESPACE, id)
            end
          end
        end
      end
    end
  end
end
