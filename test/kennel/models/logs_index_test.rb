# frozen_string_literal: true
require_relative "../../test_helper"

SingleCov.covered!

describe Kennel::Models::LogsIndex do
  class TestLogIndex < Kennel::Models::LogsIndex
  end
  # generate readables diffs when things are not equal
  def assert_json_equal(a, b)
    JSON.pretty_generate(a).must_equal JSON.pretty_generate(b)
  end

  def index(options={})
    Kennel::Models::LogsIndex.new(
      'Kennel::Models::LogsIndex',
      options
    )
  end

  let(:expected_basic_json) do
    {
      name: 'Kennel::Models::LogsIndex',
      filter: { query: '*' },
      exclusion_filters: []
    }
  end

  describe '#initialize' do
    it 'sets defaults' do
      index.exclusion_filters.must_equal []
      index.filter[:query].must_equal '*'
    end
  end

  describe '#as_json' do
    it 'creates a basic json' do
      assert_json_equal(
        index.as_json,
        expected_basic_json
      )
    end

    it 'can set filter' do
      new_index_filter = { query: 'service:foo' }
      index(filter: -> { new_index_filter }).as_json.dig(:filter, :query).must_equal 'service:foo'
    end

    it 'can set exclusion filters' do
      new_exclusion_filter = [{
        name: 'exclusion_filter1',
        is_enabled: true,
        filter: {
          query: 'service:bar',
          sample_rate: 0.5
        }
      }]
      index(exclusion_filters: -> { new_exclusion_filter }).exclusion_filters[0][:name].must_equal 'exclusion_filter1'
    end
  end

  describe '.sorted' do
    before do
      Kennel::Models::LogsIndex.reset!
    end
    it 'tracks the index sort order' do
      TestLogIndex.new('TestLogIndex1', order: -> { 100 })
      TestLogIndex.new('TestLogIndex2')
      TestLogIndex.new('TestLogIndex3', order: -> { 1 })
      Kennel::Models::LogsIndex.sorted.must_equal ['TestLogIndex3', 'TestLogIndex1', 'TestLogIndex2']
    end
  end
end
