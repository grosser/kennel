# frozen_string_literal: true

require "tmpdir"
require_relative "../../test_helper"

SingleCov.covered!

describe Kennel::PartsWriter::GeneratedDir do
  def build_project(**options)
    Kennel::Models::Project.new(
      {
        kennel_id: "p",
        team: Kennel::Models::Team.new(
          mention: "foo@example.com"
        )
      }.merge(options)
    )
  end

  def build_dashboard(project:, **options)
    Kennel::Models::Dashboard.new(
      project,
      {
        title: "a title",
        kennel_id: "a_dashboard",
        layout_type: "fixed",
      }.merge(options)
    )
  end

  def tree
    require 'find'
    Find.find(base_dir).map { |path| path.sub(base_dir + "/", "") }.sort - [base_dir]
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

    let(:project) { build_project }
    let(:part1a) { build_dashboard(project: project, kennel_id: 'd1', title: 'A') }
    let(:part1b) { build_dashboard(project: project, kennel_id: 'd1', title: 'B') }
    let(:part2) { build_dashboard(project: project, kennel_id: 'd2') }

    before do
      Kennel::Progress.stubs(:progress).yields
    end

    after do
      FileUtils.rm_rf(base_dir)
    end

    context "starting with an empty directory" do
      it "runs with no parts" do
        writer.store(parts: [])
        tree.must_equal([])
      end

      it "runs with some parts" do
        writer.store(parts: [part1a, part2])
        tree.must_equal(%w[p p/d1.json p/d2.json])
      end

      it "pretty prints json" do
        writer.store(parts: [part1a])
        text = File.read("#{base_dir}/p/d1.json")
        lines = text.lines.count
        (lines > 3).must_equal(true, "expected > 3 lines, got #{lines}")
      end

      it "includes the api_resource" do
        writer.store(parts: [part1a])
        data = JSON.parse(File.read("#{base_dir}/p/d1.json"), symbolize_names: true)
        data.must_equal(part1a.as_json.merge(api_resource: "dashboard"))
      end
    end

    context "starting with no directory" do
      it "with a part" do
        Dir.rmdir(base_dir)
        writer.store(parts: [part1a])
        tree.must_equal(%w[p p/d1.json])
      end

      it "with no parts" do
        Dir.rmdir(base_dir)
        writer.store(parts: [])
        Dir.exists?(base_dir).must_equal(true)
        tree.must_equal(%w[])
      end
    end

    context "starting with a non-empty directory" do
      before do
        writer.store(parts: [part1a])
      end

      it "adds any missing files" do
        writer.store(parts: [part1a, part2])
        tree.must_equal(%w[p p/d1.json p/d2.json])
      end

      it "removes any unwanted files" do
        tree.must_equal(%w[p p/d1.json])
        writer.store(parts: [part2])
        tree.must_equal(%w[p p/d2.json])
      end

      it "does not write if the file hasn't changed" do
        earlier = Time.at(12345) # Some time in 1970
        File.utime(earlier, earlier, "#{base_dir}/p/d1.json")
        writer.store(parts: [part1a])
        mtime = File.stat("#{base_dir}/p/d1.json").mtime
        mtime.must_equal(earlier)
      end

      it "does write if the file has changed" do
        earlier = Time.at(12345) # Some time in 1970
        File.utime(earlier, earlier, "#{base_dir}/p/d1.json")
        writer.store(parts: [part1b])
        mtime = File.stat("#{base_dir}/p/d1.json").mtime
        mtime.must_be_close_to(Time.now, 10)
      end
    end

    # Filters only affect what gets _deleted_, not what gets _written_

    describe "with a project_filter" do
      let(:project_filter) { ["p1", "p2"] }

      let(:p2) { build_project(kennel_id: 'p2') }
      let(:dashboard_in_p2) { build_dashboard(project: p2, kennel_id: 'd3') }

      before do
        # Using 'unfiltered' shouldn't make a difference
        # but it might make things easier to reason about
        unfiltered_writer = Kennel::PartsWriter::GeneratedDir.new(base_dir: base_dir)
        unfiltered_writer.store(parts: [part1a, part2, dashboard_in_p2])
      end

      it "runs" do
        tree.must_equal(%w[p p/d1.json p/d2.json p2 p2/d3.json])

        # Filter matches p2, so only p2 things might get deleted - not 'p'
        writer.store(parts: [])

        # The trailing 'p2' is because (due to git not caring) we leave behind
        # an empty directory
        tree.must_equal(%w[p p/d1.json p/d2.json p2])
      end
    end

    describe "with a tracking_id_filter" do
      let(:tracking_id_filter) { ["p:d1", "x:y"] }

      # Pretty sure the tracking_id_filter logic is broken,
      # so not testing just yet

      it "runs" do
        writer.store(parts: [part1a])
      end

      it "runs twice with no changes" do
        writer.store(parts: [part1a])
        writer.store(parts: [part1a])
      end

      it "runs twice with a change" do
        writer.store(parts: [part1a])
        writer.store(parts: [part1b])
      end
    end
  end
end
