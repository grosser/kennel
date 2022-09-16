# frozen_string_literal: true

# The options which affect the running of Kennel.
#
# The options are:
#
# * `out` - where kennel prints output (an `IO`; default: `$stdout`)
# * `err` - where kennel prints errors (an `IO`; default: `$stderr`)
# * `strict_imports` - whether kennel should abort if asked to create a part, and the part has an `id:`,
#   but there is no such object in Datadog (boolean; default: true)
#
# To build the default config:
#
#   config = Kennel::Config.new
#
# To build a config which reads its settings from various ENV variables:
#
#   config = Kennel::Config.from_env
#
# To build a config from a hash, or from another config:
#
#   config = Kennel::Config.new(from)
#
# A block can be passed to `.new` or `.from_env`. If a block is given,
# then after any settings have been copied from `from` (if given),
# a mutable config object will be yielded to the block, so that
# the config can be set up:
#
#   config = Kennel::Config.new do |c|
#     c.strict_imports = false
#   end
#
# Once built, a config object is immutable.
#
# For each config option (e.g. `strict_imports`):
#
# * the config has a read accessor (`config.strict_imports`);
# * if still mutable, the config has a write accessor (`config.strict_imports = ...`)
# * if a `from` is passed to `.new`, then the option will be copied over (`config.strict_imports = from.to_h[:strict_imports]`)

module Kennel
  class Config
    ATTRS = %I[
      out
      err
      strict_imports
    ].freeze
    private_constant :ATTRS

    attr_reader(*ATTRS)

    def self.from_env(&block)
      new(&block)
    end

    def initialize(from = nil, &block)
      set_defaults
      update_from_hash(from.to_h) if from
      block&.call(self)
      freeze
    end

    def to_h
      ATTRS.to_h { |k| [k.to_sym, public_send(k)] }
    end

    def out=(arg)
      raise ":out must be an IO" unless arg.is_a?(IO)

      @out = arg
    end

    def err=(arg)
      raise ":err must be an IO" unless arg.is_a?(IO)

      @err = arg
    end

    def strict_imports=(arg)
      @strict_imports = !!arg
    end

    def frozen?
      false
    end

    private

    def set_defaults
      @out = $stdout
      @err = $stderr
      @strict_imports = true
    end

    def update_from_hash(hash)
      hash.each do |k, v|
        public_send("#{k}=", v)
      end
    end

    def freeze
      ATTRS.each do |k|
        singleton_class.undef_method("#{k}=")
      end

      define_singleton_method(:freeze) {}
      define_singleton_method(:frozen?) { true }
    end
  end
end
