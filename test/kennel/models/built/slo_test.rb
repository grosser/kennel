# frozen_string_literal: true
require_relative "../../../test_helper"

SingleCov.covered!

describe Kennel::Models::Built::Slo do
  with_test_classes

  def slo(options = {})
    Kennel::Models::Slo.new(
      options.delete(:project) || project,
      {
        type: -> { "metric" },
        name: -> { "Foo" },
        kennel_id: -> { "m1" }
      }.merge(options)
    )
  end

  let(:project) { TestProject.new }
  let(:id_map) { Kennel::IdMap.new }

  describe "#resolve_linked_tracking_ids!" do
    it "ignores empty caused by ignore_default" do
      slo = slo(monitor_ids: -> { nil }).build!
      slo.resolve_linked_tracking_ids!(id_map, force: false)
      refute slo.as_json[:monitor_ids]
    end

    it "does nothing for hardcoded ids" do
      slo = slo(monitor_ids: -> { [123] }).build!
      slo.resolve_linked_tracking_ids!(id_map, force: false)
      slo.as_json[:monitor_ids].must_equal [123]
    end

    it "resolves relative ids" do
      slo = slo(monitor_ids: -> { ["#{project.kennel_id}:mon"] }).build!
      id_map.set("monitor", "#{project.kennel_id}:mon", 123)
      slo.resolve_linked_tracking_ids!(id_map, force: false)
      slo.as_json[:monitor_ids].must_equal [123]
    end

    it "does not resolve missing ids so they can resolve when monitor was created" do
      slo = slo(monitor_ids: -> { ["#{project.kennel_id}:mon"] }).build!
      id_map.set("monitor", "#{project.kennel_id}:mon", Kennel::IdMap::NEW)
      slo.resolve_linked_tracking_ids!(id_map, force: false)
      slo.as_json[:monitor_ids].must_equal ["test_project:mon"]
    end

    it "fails with typos" do
      slo = slo(monitor_ids: -> { ["#{project.kennel_id}:mon"] }).build!
      assert_raises Kennel::UnresolvableIdError do
        slo.resolve_linked_tracking_ids!(id_map, force: false)
      end
    end
  end
end
