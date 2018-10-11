# frozen_string_literal: true
require_relative "test_helper"
require "tmpdir"

SingleCov.not_covered!

describe "Readme.md" do
  let(:readme) { "Readme.md" }
  let(:ruby_block_start) { "```Ruby" }

  it "has working code blocks" do
    lines = File.readlines(readme)

    # code blocks with line number so when the eval fails we get a usable error
    code_blocks = lines
      .each_with_index.map { |_, n| n } # we only care for line numbers
      .select { |l| lines[l].include?("```") } # start or end of block
      .each_slice(2) # group by blocks
      .select { |start, _| lines[start].include?(ruby_block_start) } # only ruby code blocks
      .map { |start, stop| [lines[(start + 1)...stop].join, start + 2] } # grab block of code

    code_blocks.each { |block, line| eval(block, nil, readme, line) } # rubocop:disable Security/Eval

    Kennel::Models::Project.recursive_subclasses.each { |p| p.new.parts.each(&:as_json) }
  end

  it "has language selected for all code blocks so 'working' test above is reliable" do
    code_blocks_starts = File.read(readme).scan(/```.*/).each_slice(2).map(&:first).map(&:strip)
    code_blocks_starts.uniq.sort.must_equal ["```Bash", ruby_block_start]
  end
end
