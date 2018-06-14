# frozen_string_literal: true
require_relative "../test_helper"

SingleCov.covered!

describe Kennel::FileCache do
  in_temp_dir

  let(:cache) { Kennel::FileCache.new("foo", "1") }

  describe "#open" do
    it "ignores missing files" do
      cache.open { |c| c.instance_variable_get(:@data).must_equal({}) }
    end

    it "ignores broken" do
      File.write("foo", "Whoops")
      cache.open { |c| c.instance_variable_get(:@data).must_equal({}) }
    end

    it "removes expired" do
      File.write("foo", Marshal.dump(a: [1, 2, Time.now.to_i - 1]))
      cache.open { |c| c.instance_variable_get(:@data).must_equal({}) }
    end

    it "keeps fresh" do
      t = Time.now.to_i + 123
      File.write("foo", Marshal.dump(a: [1, 2, t]))
      cache.open { |c| c.instance_variable_get(:@data).must_equal(a: [1, 2, t]) }
    end

    it "persists changes" do
      cache.open do |c|
        c.fetch(:a, 3) { 4 }.must_equal 4
      end
      data = Marshal.load(File.read("foo")) # rubocop:disable Security/MarshalLoad
      data.must_equal(a: [4, [3, "1"], cache.instance_variable_get(:@expires)])
    end

    it "can use nested file" do
      cache = Kennel::FileCache.new("foo/bar", "1")
      cache.open do |c|
        c.fetch(:a, 3) { 4 }.must_equal 4
      end
      Marshal.load(File.read("foo/bar")) # rubocop:disable Security/MarshalLoad
    end
  end

  describe "#fetch" do
    it "returns old" do
      File.write("foo", Marshal.dump(a: [1, [2, "1"], Time.now.to_i + 123]))
      cache.open do |c|
        c.fetch(:a, 2) { raise }.must_equal 1
      end
    end

    it "stores new when old is missing" do
      cache.open do |c|
        c.fetch(:a, 2) { 3 }.must_equal 3
        c.fetch(:a, 2) { 4 }.must_equal 3
      end
    end

    it "stores new when old is outdated" do
      File.write("foo", Marshal.dump(a: [1, 2, Time.now.to_i + 123]))
      cache.open do |c|
        c.fetch(:a, 3) { 4 }.must_equal 4
        c.fetch(:a, 3) { 5 }.must_equal 4
      end
    end
  end
end
