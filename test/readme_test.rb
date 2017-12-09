# frozen_string_literal: true
require_relative "test_helper"
require "tmpdir"

SingleCov.not_covered!

describe "Readme.md" do
  it "has working code blocks" do
    file = "Readme.md"
    lines = File.readlines(file)

    # code blocks with line number so when the eval fails we get a usable error
    code_blocks = lines.map(&:strip).each_with_index
      .select { |l, _| l.start_with?("```") }
      .each_slice(2)
      .map { |start, stop| [lines[(start.last + 1)...stop.last].join("\n"), start.last + 2] }

    code_blocks.each { |block, line| eval(block, nil, file, line) } # rubocop:disable Security/Eval

    Kennel::Models::Project.recursive_subclasses.each { |p| p.new.parts.each(&:as_json) }
  end
end
