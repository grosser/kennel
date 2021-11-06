# frozen_string_literal: true
require_relative "../test_helper"

SingleCov.covered!

describe Kennel::IdMap do
  it "stores ids" do
    id_map = Kennel::IdMap.new
    id_map.set("monitor", "a:b", 1)
    id_map.get("monitor", "a:b").must_equal 1
    assert_nil id_map.get("monitor", "a:c")
  end

  it "stores ids by type" do
    id_map = Kennel::IdMap.new

    id_map.set("monitor", "a:b", 1)
    id_map.set("slo", "a:b", "2")

    id_map.get("monitor", "a:b").must_equal 1
    id_map.get("slo", "a:b").must_equal "2"
  end

  it "stores new values" do
    id_map = Kennel::IdMap.new
    id_map.set("monitor", "a:b", 1)
    id_map.set_new("monitor", "a:c")

    id_map.new?("monitor", "a:b").must_equal false
    id_map.new?("monitor", "a:c").must_equal true
  end
end
