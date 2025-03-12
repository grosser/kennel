# frozen_string_literal: true
require_relative "../test_helper"
require "stringio"

SingleCov.covered!

describe Kennel::UnmutedAlerts do
  capture_all

  let(:tag) { "team:compute" }
  let(:monitors) { [monitor] }
  let(:triggered) { (Time.now - 10).to_i }
  let(:monitor) do
    {
      id: 12345,
      tags: [tag],
      name: "monitor_name",
      state: {
        groups: {
          "pod:pod10": { status: "Alert", name: "pod:pod10", last_triggered_ts: triggered },
          "pod:pod3": { status: "Foo", name: "pod:pod3", last_triggered_ts: triggered },
          "pod:pod3,project:foo,team:bar": {
            status: "Alert", name: "pod:pod3,project:foo,team:bar", last_triggered_ts: triggered
          }
        }
      },
      overall_state: "Alert",
      options: { silenced: { "pod:pod10": nil } }
    }
  end

  before do
    time = Time.now
    Time.stubs(:now).returns(time)
  end

  it "can display all colors" do
    Kennel::UnmutedAlerts::COLORS.each_value do |color|
      Kennel::Console::COLORS.fetch(color)
    end
  end

  describe "#print" do
    it "prints alerts" do
      Kennel::UnmutedAlerts.send(:sort_groups!, monitor)
      Kennel::UnmutedAlerts.expects(:filtered_monitors).returns([monitor])
      out = Kennel::Console.capture_stdout do
        Kennel.out.stubs(:tty?).returns(true)
        Kennel::UnmutedAlerts.send(:print, nil, tag)
      end
      out.must_equal <<~TEXT
        monitor_name
        https://app.datadoghq.com/monitors/12345
        \e[0mFoo\e[0m\tpod:pod3\t00:00:10
        \e[31mAlert\e[0m\tpod:pod3,project:foo,team:bar\t00:00:10
        \e[31mAlert\e[0m\tpod:pod10\t00:00:10

      TEXT
    end

    it "does not print alerts when there are no monitors" do
      Kennel::UnmutedAlerts.expects(:filtered_monitors).returns([])
      out = Kennel::Console.capture_stdout do
        Kennel::UnmutedAlerts.send(:print, nil, tag)
      end
      out.must_equal "No unmuted alerts found\n"
    end
  end

  describe "#sort_groups!" do
    it "sorts naturally" do
      sorted = Kennel::UnmutedAlerts.send(:sort_groups!, monitor)
      sorted.map { |g| g[:name] }.must_equal ["pod:pod3", "pod:pod3,project:foo,team:bar", "pod:pod10"]
    end
  end

  describe "#filtered_monitors" do
    let(:api) { Kennel::Api.new("app", "api") }

    def result
      stub_datadog_request(:get, "monitor", "&monitor_tags=#{tag}&group_states=all&with_downtimes=true").to_return(body: monitors.to_json)
      Kennel::UnmutedAlerts.send(:filtered_monitors, api, tag)
    end

    it "does not filter unmuted alerts" do
      result.size.must_equal 1
    end

    # see https://help.datadoghq.com/hc/requests/174099
    # overall_state is not reliable, but the only tool we have to shut datadog up, so we have to use it :(
    it "removes monitors that claim to be OK since even though it is not reliable for No-Data" do
      monitor[:overall_state] = "OK"
      result.size.must_equal 0
    end

    it "removes monitors that are Ignored since that just means recovered" do
      monitor[:state][:groups].each_value { |v| v[:status] = "Ignored" }
      result.size.must_equal 0
    end

    it "removes completely muted alerts" do
      monitor[:options] = { silenced: { "*": "foo" } }
      result.size.must_equal 0
    end

    it "removes monitors that are silenced via partial silences" do
      monitor[:options] = { silenced: { "pod:pod10": "foo", "pod:pod3": "foo" } }
      result.size.must_equal 0
    end

    it "removes monitors that are covered by matching downtimes" do
      groups = ["pod:pod3", "pod:pod3,project:foo,team:bar"]
      monitor[:matching_downtimes] = [
        { end: nil, start: triggered - 10, groups: groups, active: true, scope: ["pod:pod3"] },
        { end: nil, start: triggered - 10, groups: [], active: true, scope: ["pod:pod7"] }
      ]
      result.size.must_equal 0
    end

    it "alerts users when no monitor has selected tag" do
      monitors.pop
      e = assert_raises(RuntimeError) { result }
      e.message.must_equal "No monitors for team:compute found, check your spelling"
    end

    it "removes groups that match multi-key silence" do
      monitor[:options] = { silenced: { "project:foo,team:bar": "foo" } }
      result.first[:state][:groups].size.must_equal 2
    end

    it "only keeps alerting groups in monitor" do
      result.first[:state][:groups].size.must_equal 2
    end
  end

  describe "#time_since" do
    before do
      time = Time.now
      Time.stubs(:now).returns(time)
    end

    it "builds for 0" do
      Kennel::UnmutedAlerts.send(:time_since, Time.now.to_i).must_equal "00:00:00"
    end

    it "builds for full" do
      diff = (99 * 60 * 60) + (59 * 60) + 59
      Kennel::UnmutedAlerts.send(:time_since, Time.now.to_i - diff).must_equal "99:59:59"
    end

    it "can overflow" do
      diff = (100 * 60 * 60) + 123
      Kennel::UnmutedAlerts.send(:time_since, Time.now.to_i - diff).must_equal "100:02:03"
    end
  end
end
