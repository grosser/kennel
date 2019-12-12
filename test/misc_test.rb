# frozen_string_literal: true
require_relative "test_helper"
require "tmpdir"

SingleCov.not_covered!

describe "Misc" do
  it "does not hardcode zendesk anywhere" do
    Dir["{lib,template}/**/*.rb"].grep_v("/vendor/").each do |file|
      refute File.read(file).include?("zendesk"), "#{file} should not reference zendesk"
    end
  end
end
