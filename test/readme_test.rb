# frozen_string_literal: true
require_relative "test_helper"
require "tmpdir"

SingleCov.not_covered!

describe "Readme.md" do
  def rake_tasks(content)
    content.scan(/(rake [^\[\s`]+)/).flatten(1).sort.uniq
  end

  let(:readme) { "Readme.md" }
  let(:ruby_block_start) { "```Ruby" }

  it "has working code blocks" do
    lines = File.readlines(readme)

    # code blocks with line number so when the eval fails we get a usable error
    code_blocks = lines
      .each_with_index.map { |_, n| n } # we only care for line numbers
      .select { |l| lines[l].include?("```") } # ignore start or end of block
      .each_slice(2) # group by blocks
      .select { |start, _| lines[start].include?(ruby_block_start) } # only ruby code blocks
      .map { |start, stop| [lines[(start + 1)...stop].join, start + 2] } # grab block of code

    code_blocks.reject! { |block, _| block.match?(/^\s+\.\.\./) } # ignore broken blocks

    code_blocks.each { |block, line| eval(block, nil, readme, line) } # rubocop:disable Security/Eval

    Kennel::Models::Project.recursive_subclasses.each { |p| p.new.parts.each(&:as_json) }
  end

  it "has language selected for all code blocks so 'working' test above is reliable" do
    code_blocks_starts = File.read(readme).scan(/```.*/).each_slice(2).map(&:first).map(&:strip)
    code_blocks_starts.uniq.sort.must_equal ["```Bash", ruby_block_start]
  end

  it "documents all public rake tasks" do
    documented = rake_tasks(File.read("Readme.md"))
    documented -= ["rake play"] # in parent repo

    output = `cd template && rake -T`
      .gsub("kennel:plan", "plan") # alias in template/Rakefile
      .gsub("kennel:generate", "generate") # alias in template/Rakefile
    available = rake_tasks(output)
    available -= ["rake kennel:no_diff"] # in template/.travis.yml
    available -= ["rake kennel:ci"] # in template/.travis.yml

    assert available == documented, <<~MSG
      Documented and available rake tasks are not the same:
      #{documented}
      #{available}
      ~#{(Set.new(documented) ^ Set.new(available)).to_a}
    MSG
  end
end
