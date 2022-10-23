# frozen_string_literal: true
require_relative "../test_helper"

SingleCov.covered!

describe Kennel::Downloader do
  let(:api) { stub("api") }
  let(:downloader) { Kennel::Downloader.new(api) }

  let(:dashboards) { [item, item] }
  let(:monitors) { [item, item] }
  let(:slos) { [item, item] }
  let(:synthetics) { [item, item] }

  before do
    api.stubs(:list).once.with("dashboard", anything).returns(dashboards: dashboards)
    api.stubs(:list).once.with("monitor", anything).returns(monitors)
    api.stubs(:list).once.with("slo", anything).returns(data: slos)
    api.stubs(:list).once.with("synthetics/tests", anything).returns(synthetics)
  end

  def item
    # Not realistic IDs (wrong type and/or wrong format),
    # but that shouldn't matter for these tests
    @seq = (@seq || 0) + 1
    { id: @seq }
  end

  it "downloads" do
    answer = downloader.all_by_class
    expected = {
      Kennel::Models::Dashboard => dashboards,
      Kennel::Models::Monitor => monitors,
      Kennel::Models::Slo => slos,
      Kennel::Models::SyntheticTest => synthetics
    }
    answer.must_equal(expected)
  end

  it "memoizes" do
    answer0 = downloader.all_by_class
    answer1 = downloader.all_by_class
    answer0.must_equal(answer1)
    # See also the 'once' assertions on the api stub
  end
end
