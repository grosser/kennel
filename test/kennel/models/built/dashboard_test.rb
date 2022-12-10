# frozen_string_literal: true
require_relative "../../../test_helper"

SingleCov.covered!

describe Kennel::Models::Built::Dashboard do
  with_test_classes

  let(:project) { TestProject.new }
  let(:id_map) { Kennel::IdMap.new }

  def dashboard(extra = {})
    Kennel::Models::Dashboard.new(project, { kennel_id: 'd', title: -> { "Hello" }, layout_type: -> { "ordered" } }.merge(extra))
  end

  let(:dashboard_with_requests) do
    dashboard(
      widgets: -> { [{ definition: { requests: [{ q: "foo", display_type: "area" }], type: "timeseries", title: "bar" } }] }
    )
  end

  describe "#resolve_linked_tracking_ids" do
    let(:built) { dashboard_with_requests.build! }
    let(:definition) { built.as_json[:widgets][0][:definition] }

    def resolve(force: false)
      built.resolve_linked_tracking_ids!(id_map, force: force)
      built.as_json[:widgets][0][:definition]
    end

    it "does nothing for regular widgets" do
      resolve.keys.must_equal [:requests, :type, :title]
    end

    it "ignores widgets without definition" do
      built.as_json[:widgets][0].delete :definition
      resolve.must_be_nil
    end

    describe "uptime" do
      before { definition[:type] = "uptime" }

      it "does not change without monitor" do
        refute resolve.key?(:monitor_ids)
      end

      it "does not change with id" do
        definition[:monitor_ids] = [123]
        resolve[:monitor_ids].must_equal [123]
      end

      it "resolves full id" do
        definition[:monitor_ids] = ["#{project.kennel_id}:b"]
        id_map.set("monitor", "a:c", 1)
        id_map.set("monitor", "#{project.kennel_id}:b", 123)
        resolved = resolve
        resolved[:monitor_ids].must_equal [123]
      end

      it "fail hard when id is still missing after dependent monitors were created by syncer" do
        definition[:monitor_ids] = ["missing:the_id"]
        id_map.set("monitor", "missing:the_id", Kennel::IdMap::NEW)
        e = assert_raises Kennel::UnresolvableIdError do
          resolve(force: true)
        end
        e.message.must_include "circular dependency"
      end
    end

    describe "alert_graph" do
      before { definition[:type] = "alert_graph" }

      it "does not change the alert widget without monitor" do
        refute resolve.key?(:alert_id)
      end

      it "does not change the alert widget with a string encoded id" do
        definition[:alert_id] = "123"
        resolve[:alert_id].must_equal "123"
      end

      it "resolves the alert widget with full id" do
        definition[:alert_id] = "#{project.kennel_id}:b"
        id_map.set("monitor", "a:c", 1)
        id_map.set("monitor", "#{project.kennel_id}:b", 123)
        resolved = resolve
        resolved[:alert_id].must_equal "123"
      end

      it "does not fail hard when id is missing to not break when adding new monitors" do
        definition[:alert_id] = "a:b"
        id_map.set("monitor", "a:b", Kennel::IdMap::NEW)
        resolve[:alert_id].must_equal "a:b"
      end
    end

    describe "slo" do
      before { definition[:type] = "slo" }

      it "does not modify regular ids" do
        definition[:slo_id] = "abcdef1234567"
        resolve[:slo_id].must_equal "abcdef1234567"
      end

      it "resolves the slo widget with full id" do
        definition[:slo_id] = "#{project.kennel_id}:b"
        id_map.set("slo", "a:c", "1")
        id_map.set("slo", "#{project.kennel_id}:b", "123")
        resolved = resolve
        resolved[:slo_id].must_equal "123"
      end

      it "resolves nested slo widget with full id" do
        definition[:widgets] = [{ definition: { slo_id: "#{project.kennel_id}:b", type: "slo" } }]
        id_map.set("slo", "a:c", "1")
        id_map.set("slo", "#{project.kennel_id}:b", "123")
        resolved = resolve
        resolved[:widgets][0][:definition][:slo_id].must_equal "123"
      end
    end
  end

  describe "#validate_update!" do
    it "allows update of title" do
      dashboard.build!.validate_update!(nil, [["~", "title", "foo", "bar"]])
    end

    it "disallows update of layout_type" do
      e = assert_raises Kennel::DisallowedUpdateError do
        dashboard.build!.validate_update!(nil, [["~", "layout_type", "foo", "bar"]])
      end
      e.message.must_match(/datadog.*allow.*layout_type/i)
    end
  end
end
