# frozen_string_literal: true
require_relative "../test_helper"

SingleCov.covered!

describe Kennel::FileCache do
  in_temp_dir

  describe "#initialize" do
    it "ignores missing files" do
      Kennel::FileCache.new("foo/bar").instance_variable_get(:@data).must_equal({})
    end

    it "ignores broken" do
      File.write("foo", "Whoops")
      Kennel::FileCache.new("foo").instance_variable_get(:@data).must_equal({})
    end

    it "removes expired" do
      File.write("foo", Marshal.dump(a: [1, 2, Time.now.to_i - 1]))
      Kennel::FileCache.new("foo").instance_variable_get(:@data).must_equal({})
    end

    it "keeps fresh" do
      t = Time.now.to_i + 123
      File.write("foo", Marshal.dump(a: [1, 2, t]))
      Kennel::FileCache.new("foo").instance_variable_get(:@data).must_equal(a: [1, 2, t])
    end
  end

  describe "#fetch" do
    it "returns old" do
      File.write("foo", Marshal.dump(a: [1, 2, Time.now.to_i + 123]))
      Kennel::FileCache.new("foo").fetch(:a, 2) { raise }.must_equal 1
    end

    it "stores new when old is missing" do
      c = Kennel::FileCache.new("foo")
      c.fetch(:a, 2) { 3 }.must_equal 3
      c.fetch(:a, 2) { 4 }.must_equal 3
    end

    it "stores new when old is outdated" do
      File.write("foo", Marshal.dump(a: [1, 2, Time.now.to_i + 123]))
      c = Kennel::FileCache.new("foo")
      c.fetch(:a, 3) { 4 }.must_equal 4
      c.fetch(:a, 3) { 5 }.must_equal 4
    end
  end

  describe "#persist" do
    it "persists changes" do
      c = Kennel::FileCache.new("bar/foo")
      c.fetch(:a, 3) { 4 }.must_equal 4
      c.persist
      data = Marshal.load(File.read("bar/foo")) # rubocop:disable Security/MarshalLoad
      data.must_equal(a: [4, 3, c.instance_variable_get(:@expires)])
    end
  end
end
