# frozen_string_literal: true

require "tmpdir"
require_relative "../../test_helper"

SingleCov.covered!

describe Kennel::PartsWriter::GeneratedDir do
  def a_project
    Kennel::Models::Project.new(
      kennel_id: "p",
      team: Kennel::Models::Team.new(
        mention: "foo@example.com"
      )
    )
  end

  def a_dashboard(title: "My dashboard")
    Kennel::Models::Dashboard.new(
      a_project,
      kennel_id: "a_monitor",
      layout_type: "fixed",
      title: title
    )
  end

  # For now, minimal "testing" just to pass test coverage.
  # The actual logic is currently tested in kennel_test.rb,
  # but should be moved here, with kennel_test.rb using stubs.

  describe "#store" do
    let!(:base_dir) { Dir.mktmpdir("generated") }
    let(:project_filter) { nil }
    let(:tracking_id_filter) { nil }

    let(:writer) do
      Kennel::PartsWriter::GeneratedDir.new(
        base_dir: base_dir,
        project_filter: project_filter,
        tracking_id_filter: tracking_id_filter
      )
    end

    before do
      Kennel::Progress.stubs(:progress).yields
    end

    after do
      FileUtils.rm_rf(base_dir)
    end

    it "runs" do
      writer.store(parts: [])
    end

    describe "with a project_filter" do
      let(:project_filter) { ["p1", "p2"] }

      it "runs" do
        writer.store(parts: [])
      end
    end

    describe "with a tracking_id_filter" do
      let(:tracking_id_filter) { ["p:t1", "p:t2"] }

      it "runs" do
        writer.store(parts: [a_dashboard])
      end

      it "runs twice with no changes" do
        writer.store(parts: [a_dashboard])
        writer.store(parts: [a_dashboard])
      end

      it "runs twice with a change" do
        writer.store(parts: [a_dashboard])
        writer.store(parts: [a_dashboard(title: "New title")])
      end
    end
  end
end
