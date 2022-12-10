# frozen_string_literal: true
require_relative "../../../test_helper"

SingleCov.covered!

describe Kennel::Models::Built::Monitor do
  with_test_classes

  def monitor(options = {})
    Kennel::Models::Monitor.new(
      options.delete(:project) || project,
      {
        type: -> { "query alert" },
        kennel_id: -> { "m1" },
        query: -> { "avg(last_5m) > #{critical}" },
        critical: -> { 123.0 }
      }.merge(options)
    )
  end

  let(:project) { TestProject.new }
  let(:id_map) { Kennel::IdMap.new }

  describe "#resolve_linked_tracking_ids" do
    let(:mon) do
      monitor(query: -> { "%{#{project.kennel_id}:mon}" }).build!
    end

    it "does nothing for regular monitors" do
      mon.resolve_linked_tracking_ids!(id_map, force: false)
      mon.as_json[:query].must_equal "%{#{project.kennel_id}:mon}"
    end

    describe "composite monitor" do
      let(:mon) do
        monitor(type: -> { "composite" }, query: -> { "%{foo:mon_a} || !%{bar:mon_b}" }).build!
      end

      it "fails when matching monitor is missing" do
        e = assert_raises Kennel::UnresolvableIdError do
          mon.resolve_linked_tracking_ids!(id_map, force: false)
        end
        e.message.must_include "test_project:m1 Unable to find monitor foo:mon_a"
      end

      it "does not fail when unable to try to resolve" do
        id_map.set("monitor", "foo:mon_a", Kennel::IdMap::NEW)
        id_map.set("monitor", "bar:mon_b", Kennel::IdMap::NEW)
        mon.resolve_linked_tracking_ids!(id_map, force: false)
        mon.as_json[:query].must_equal "%{foo:mon_a} || !%{bar:mon_b}", "query not modified"
      end

      it "resolves correctly with a matching monitor" do
        id_map.set("monitor", "foo:mon_x", 3)
        id_map.set("monitor", "foo:mon_a", 1)
        id_map.set("monitor", "bar:mon_b", 2)
        mon.resolve_linked_tracking_ids!(id_map, force: false)
        mon.as_json[:query].must_equal("1 || !2")
      end
    end

    describe "slo alert monitor" do
      let(:mon) do
        monitor(type: -> { "slo alert" }, query: -> { "error_budget(\"%{foo:slo_a}\").over(\"7d\") > #{critical}" }).build!
      end

      it "fails when matching monitor is missing" do
        e = assert_raises Kennel::UnresolvableIdError do
          mon.resolve_linked_tracking_ids!(id_map, force: false)
        end
        e.message.must_include "test_project:m1 Unable to find slo foo:slo_a"
      end

      it "resolves correctly with a matching monitor" do
        id_map.set("slo", "foo:slo_x", "3")
        id_map.set("slo", "foo:slo_a", "1")
        id_map.set("slo", "foo:slo_b", "2")
        mon.resolve_linked_tracking_ids!(id_map, force: false)
        mon.as_json[:query].must_equal("error_budget(\"1\").over(\"7d\") > 123.0")
      end
    end
  end

  describe "#validate_update!" do
    it "allows update of name" do
      monitor.build!.validate_update!(nil, [["~", "name", "foo", "bar"]])
    end

    it "disallows update of type" do
      e = assert_raises Kennel::DisallowedUpdateError do
        monitor.build!.validate_update!(nil, [["~", "type", "foo", "bar"]])
      end
      e.message.must_match(/datadog.*allow.*type/i)
    end

    it "allows update of metric to query which is used by the importer" do
      monitor.build!.validate_update!(nil, [["~", "type", "metric alert", "query alert"]])
    end
  end
end
