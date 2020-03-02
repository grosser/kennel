# frozen_string_literal: true
require_relative "../test_helper"

SingleCov.covered!

describe Kennel::SettingsAsMethods do
  class TestSetting
    include Kennel::SettingsAsMethods
    settings :foo, :bar, :override, :unset
    defaults(
      bar: -> { "bar" },
      override: -> { "parent" }
    )
  end

  class TestSettingMethod < TestSetting
    SETTING_OVERRIDABLE_METHODS = [:name].freeze
    settings :name
  end

  class ChildTestSetting < TestSetting
    settings :baz
    defaults(
      foo: -> { "foo-child" },
      override: -> { "child-#{super()}" }
    )
  end

  describe "#initialize" do
    it "can set options" do
      TestSetting.new(foo: -> { 111 }).foo.must_equal 111
    end

    it "fails when setting unsupported options" do
      e = assert_raises(ArgumentError) { TestSetting.new(nope: -> { 111 }) }
      e.message.must_equal "Unsupported setting :nope, supported settings are :foo, :bar, :override, :unset"
    end

    it "fails nicely when given non-hash" do
      e = assert_raises(ArgumentError) { TestSetting.new("FOOO") }
      e.message.must_equal "Expected TestSetting.new options to be a Hash, got a String"
    end

    it "fails nicely when given non-procs" do
      e = assert_raises(ArgumentError) { TestSetting.new(id: 12345) }
      e.message.must_equal "Expected TestSetting.new option :id to be Proc, for example `id: -> { 12 }`"
    end

    it "stores invocation_location" do
      model = Kennel::Models::Monitor.new(TestProject.new)
      location = model.instance_variable_get(:@invocation_location).sub(/:\d+/, ":123")
      location.must_equal "lib/kennel/models/record.rb:123:in `initialize'"
    end

    it "stores invocation_location from first outside project line" do
      Kennel::Models::Monitor.any_instance.expects(:caller).returns(
        [
          "/foo/bar.rb",
          "#{Dir.pwd}/baz.rb"
        ]
      )
      model = Kennel::Models::Monitor.new(TestProject.new)
      location = model.instance_variable_get(:@invocation_location).sub(/:\d+/, ":123")
      location.must_equal "baz.rb"
    end
  end

  describe ".defaults" do
    it "returns defaults" do
      ChildTestSetting.new.foo.must_equal "foo-child"
    end

    it "inherits" do
      ChildTestSetting.new.bar.must_equal "bar"
    end

    it "can override" do
      ChildTestSetting.new.foo.must_equal "foo-child"
    end

    it "can call super" do
      ChildTestSetting.new.override.must_equal "child-parent"
    end

    it "explains when user forgets to set an option" do
      e = assert_raises(ArgumentError) { TestSetting.new.unset }
      e.message.must_include "'unset' on TestSetting"
    end

    it "does not crash when location was unable to be stored" do
      s = TestSetting.new
      s.instance_variable_set(:@invocation_location, nil)
      e = assert_raises(ArgumentError) { s.unset }
      e.message.must_equal "'unset' on TestSetting was not set or passed as option"
    end

    it "explains when user forgets to set an option" do
      e = assert_raises(ArgumentError) { TestSetting.new.unset }
      e.message.must_include "'unset' on TestSetting"
    end

    it "cannot set unknown settings on base" do
      e = assert_raises(ArgumentError) { TestSetting.defaults(baz: -> {}) }
      e.message.must_include "Unsupported setting :baz, supported settings are :foo, :bar, :override, :unset"
    end

    it "cannot set unknown settings on child" do
      e = assert_raises(ArgumentError) { ChildTestSetting.defaults(nope: -> {}) }
      e.message.must_include "Unsupported setting :nope, supported settings are :foo, :bar, :override, :unset, :baz"
    end
  end

  describe ".settings" do
    it "fails when already defined to avoid confusion and typos" do
      e = assert_raises(ArgumentError) { TestSetting.settings :foo }
      e.message.must_equal "Settings :foo are already defined"
    end

    it "does not allow overwriting base methods" do
      e = assert_raises(ArgumentError) { TestSetting.settings(:inspect) }
      e.message.must_equal "Settings :inspect are already used as methods"
    end
  end
end
