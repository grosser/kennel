# frozen_string_literal: true
require_relative "../test_helper"
require 'find'

SingleCov.covered!

describe Kennel::PartsWriter do
  def write(file, content)
    folder = File.dirname(file)
    FileUtils.mkdir_p folder unless File.exist?(folder)
    File.write file, content
  end

  let(:project_filter) { nil }
  let(:tracking_id_filter) { nil }

  let(:filter) do
    filter = "some filter".dup
    filter.stubs(:project_filter).returns(project_filter)
    filter.stubs(:tracking_id_filter).returns(tracking_id_filter)
    filter
  end

  capture_all

  def make_project(kennel_id, monitor_kennel_ids)
    Kennel::Models::Project.new(
      team: Kennel::Models::Team.new(
        kennel_id: 'team-id',
        mention: "@slack-whatever",
      ),
      name: kennel_id,
      kennel_id: kennel_id,
      parts: -> {
        monitor_kennel_ids.map do |id|
          Kennel::Models::Monitor.new(
            self,
            type: "query alert",
            kennel_id: id,
            query: "avg(last_5m) > 123",
            critical: 123,
          )
        end
      }
    )
  end

  in_temp_dir

  it "saves formatted json" do
    parts = make_project('temp_project', ['foo']).validated_parts
    Kennel::PartsWriter.new(filter: filter).write(parts)
    content = File.read("generated/temp_project/foo.json")
    assert content.start_with?("{\n") # pretty generated
    json = JSON.parse(content, symbolize_names: true)
    json[:query].must_equal "avg(last_5m) > 123"
  end

  it "keeps same" do
    parts = make_project('temp_project', ['foo']).validated_parts
    Kennel::PartsWriter.new(filter: filter).write(parts)

    old = Time.now - 10
    FileUtils.touch "generated/temp_project/foo.json", mtime: old

    Kennel::PartsWriter.new(filter: filter).write(parts)

    File.mtime("generated/temp_project/foo.json").must_equal old
  end

  it "overrides different" do
    parts = make_project('temp_project', ['foo']).validated_parts
    Kennel::PartsWriter.new(filter: filter).write(parts)

    old = Time.now - 10
    File.write "generated/temp_project/foo.json", "x"
    File.utime(old, old, "generated/temp_project/foo.json")

    Kennel::PartsWriter.new(filter: filter).write(parts)

    File.mtime("generated/temp_project/foo.json").wont_equal old
  end

  it "cleans up old stuff" do
    write "generated/old_project/some_file.json", "whatever"
    write "generated/temp_project/some_file.json", "whatever"
    Dir.mkdir "generated/old_empty_project"
    write "generated/stray_file_not_in_a_subfolder.json", "whatever"

    parts = make_project('temp_project', ['foo']).validated_parts
    Kennel::PartsWriter.new(filter: filter).write(parts)

    Find.find("generated").to_a.sort.must_equal [
      "generated",
      "generated/temp_project",
      "generated/temp_project/foo.json"
    ]
  end

  describe "project filtering" do
    # The filtering only applies to the _cleanup_, not to the _write_.
    # This is because filtering of what parts to write is handled by
    # Kennel.generated
    let(:project_filter) { ['included1', 'included2'] }

    it "filters the cleanup" do
      write "generated/included1/old_part.json", "whatever"
      write "generated/included2/old_part.json", "whatever"
      write "generated/excluded/old_part.json", "whatever"
      Dir.mkdir "generated/old_empty_project"
      write "generated/stray_file_not_in_a_subfolder.json", "whatever"

      parts = [
        *make_project('included1', ['foo1']).validated_parts,
        *make_project('included2', ['foo2']).validated_parts,
      ]
      Kennel::PartsWriter.new(filter: filter).write(parts)

      Find.find("generated").to_a.sort.must_equal %w[
        generated
        generated/excluded
        generated/excluded/old_part.json
        generated/included1
        generated/included1/foo1.json
        generated/included2
        generated/included2/foo2.json
        generated/old_empty_project
        generated/stray_file_not_in_a_subfolder.json
      ]
    end
  end

  describe "tracking_id filtering" do
    # The filtering only applies to the _cleanup_, not to the _write_.
    # This is because filtering of what parts to write is handled by
    # Kennel.generated
    #
    # For tracking_id filtering, this means that we never clean up.
    let(:project_filter) { ['included1', 'included2'] }
    let(:tracking_id_filter) { ['included1:foo1', 'included2:foo2'] }

    it "does not clean up" do
      write "generated/included1/included1:old_part.json", "whatever"
      write "generated/included1/old_part.json", "whatever"
      write "generated/included2/old_part.json", "whatever"
      write "generated/excluded/old_part.json", "whatever"
      Dir.mkdir "generated/old_empty_project"
      write "generated/stray_file_not_in_a_subfolder.json", "whatever"

      parts = [
        *make_project('included1', ['foo1']).validated_parts,
        *make_project('included2', ['foo2']).validated_parts,
      ]
      Kennel::PartsWriter.new(filter: filter).write(parts)

      Find.find("generated").to_a.sort.must_equal %w[
        generated
        generated/excluded
        generated/excluded/old_part.json
        generated/included1
        generated/included1/foo1.json
        generated/included1/included1:old_part.json
        generated/included1/old_part.json
        generated/included2
        generated/included2/foo2.json
        generated/included2/old_part.json
        generated/old_empty_project
        generated/stray_file_not_in_a_subfolder.json
      ]
    end
  end
end
