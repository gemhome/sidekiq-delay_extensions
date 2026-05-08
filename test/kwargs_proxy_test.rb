# frozen_string_literal: true

# Tests for the Proxy 4-tuple kwargs fix (introduced in 7.2.0).
#
# Background
# ----------
# Sidekiq 6.4's built-in delay Proxy always emitted a 4-tuple YAML payload:
#   [target, method_name, positional_args, kwargs]
#
# sidekiq-delay_extensions 7.0–7.1 regressed to a 3-tuple because
# Proxy#method_missing lacked the **kwargs parameter.  On Ruby 3.1+, keyword
# arguments no longer auto-promote from a trailing positional Hash, so a call
# like User.delay.call("1", hello: :world) collapsed {hello: :world} into
# *args, producing:
#   [target, method_name, ["1", {hello: :world}]]   # kwargs silently lost
#
# That causes ArgumentError on dispatch for any method with named kwargs.
# See https://github.com/sidekiq/sidekiq/discussions/6979 for the full report.
#
# Coverage in this file
# ---------------------
#  1. Proxy payload shape — .delay
#  2. Proxy payload shape — .delay_for and .delay_until
#  3. Module target (non-class)
#  4. YAML symbol key round-trip
#  5. GenericJob#perform dispatch from 4-tuple
#  6. display_class with 4-tuple
#  7. display_args with 4-tuple
#  8. Full round-trip (Proxy → inline GenericJob)
#  9. DelayedModel — class-method and AR-instance-method paths
# 10. DelayedMailer — emission + dispatch with captured kwargs assertion
# 11. Sidekiq 6.4 built-in payload compatibility (real migration scenario)
# 12. Regression — discussion #6979 exact repro
# 13. Backward compatibility — legacy 3-tuple payloads (no new exceptions)
# 14. GenericProxy (use_generic_proxy=true) is unaffected

require_relative "helper"
require "sidekiq/api"
require "active_record"
require "action_mailer"
Sidekiq::DelayExtensions.enable_delay!

# Use the in-memory :test delivery method so KwargsMailer dispatch tests don't
# try to open an SMTP connection.  Captured deliveries land in
# ActionMailer::Base.deliveries which we ignore — the assertions inspect
# captured kwargs directly.
ActionMailer::Base.delivery_method = :test
ActionMailer::Base.perform_deliveries = true
ActionMailer::Base.raise_delivery_errors = false

# ---------------------------------------------------------------------------
# Support classes
# ---------------------------------------------------------------------------

class KwargsTarget
  def self.mixed(pos_a, pos_b, kw_a:, kw_b: :default)
    [pos_a, pos_b, kw_a, kw_b]
  end

  def self.kwargs_only(name:, value:)
    {name: name, value: value}
  end

  def self.positional_only(a, b)
    a + b
  end

  def self.no_args
    :called_without_args
  end

  # A positional Hash parameter — must NOT be treated as kwargs at enqueue time.
  def self.positional_hash(opts = {})
    opts
  end

  # Closest real-world pattern: splat + double-splat
  def self.splat_kwargs(*args, **kwargs)
    [args, kwargs]
  end

  # Exact method shape from discussion #6979
  def self.call(id, hello:)
    {id: id, hello: hello}
  end
end

module KwargsModule
  def self.compute(factor:, base: 10)
    base * factor
  end
end

class KwargsMailer < ActionMailer::Base
  # Mutable capture slot for assertions in dispatch tests — see test #10.
  cattr_accessor :captured_args, instance_accessor: false
  self.captured_args = nil

  def welcome(name:, locale: :en)
    KwargsMailer.captured_args = {name: name, locale: locale}
    # Build a real (test-mode) Mail::Message so the surrounding _perform's
    # `msg.deliver_now` call is a no-op via ActionMailer's :test delivery.
    mail(to: "to@test.invalid", from: "from@test.invalid", subject: "ok", body: "ok")
  end
end

# Minimal AR-like class for DelayedModel CLASS-method tests (avoids sqlite3 setup).
class KwargsRecord
  def self.process(entity_id, action:, priority: :normal)
    [entity_id, action, priority]
  end
end

# AR-style INSTANCE delay path: include the same module that
# Sidekiq::DelayExtensions wires onto ActiveRecord::Base in production.
# This exercises the user_instance.delay.method(kwarg: val) flow without
# requiring a real database connection.
class KwargsActiveModel
  include Sidekiq::DelayExtensions::ActiveRecord

  cattr_accessor :received, instance_accessor: false
  self.received = nil

  def update_with(new_status:, audited_by: :system)
    KwargsActiveModel.received = {new_status: new_status, audited_by: audited_by}
  end
end

# ---------------------------------------------------------------------------
# YAML helpers
# ---------------------------------------------------------------------------

# 3-tuple YAML matching what the broken 7.1.0 Proxy actually emitted on Ruby
# 3.1 when called with keyword arguments — kwargs end up folded as a trailing
# Hash inside the *args array (because **kwargs was missing from the proxy).
def legacy_3tuple_with_folded_kwargs(target, method_sym, positional_args, kwargs_hash)
  ::YAML.dump([target, method_sym, positional_args + [kwargs_hash]])
end

# 3-tuple YAML for a no-kwargs legacy call (what 7.1.0 emitted when no kwargs
# were passed at all — args is just the bare positional array).
def legacy_3tuple_positional_only(target, method_sym, positional_args)
  ::YAML.dump([target, method_sym, positional_args])
end

# 4-tuple YAML as the fixed 7.2.0 Proxy (and Sidekiq 6.4 built-in) emits.
def canonical_4tuple_yml(target, method_sym, positional_args, kwargs_hash)
  ::YAML.dump([target, method_sym, positional_args, kwargs_hash])
end

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

describe "Proxy kwargs fix (4-tuple payload)" do
  before do
    @cfg = reset!
    Sidekiq::DelayExtensions.use_generic_proxy = false
    KwargsMailer.captured_args = nil
    KwargsActiveModel.received = nil
  end

  after do
    Sidekiq::DelayExtensions.use_generic_proxy = false
  end

  # =========================================================================
  # 1. Proxy payload shape — .delay
  # =========================================================================

  describe "Proxy payload shape — .delay" do
    it "emits a 4-tuple with kwargs in their own slot" do
      q = Sidekiq::Queue.new
      KwargsTarget.delay.mixed("a", "b", kw_a: :x, kw_b: :y)
      raw = ::YAML.unsafe_load(q.first["args"].first)
      assert_equal 4, raw.length, "expected [target, method, args, kwargs]"
      assert_equal KwargsTarget, raw[0]
      assert_equal :mixed, raw[1]
      assert_equal ["a", "b"], raw[2]
      assert_equal({kw_a: :x, kw_b: :y}, raw[3])
    end

    it "emits a 4-tuple when no kwargs given (empty kwargs slot)" do
      q = Sidekiq::Queue.new
      KwargsTarget.delay.positional_only(1, 2)
      raw = ::YAML.unsafe_load(q.first["args"].first)
      assert_equal 4, raw.length
      assert_equal [1, 2], raw[2]
      assert_equal({}, raw[3])
    end

    it "emits a 4-tuple for a no-args, no-kwargs call" do
      q = Sidekiq::Queue.new
      KwargsTarget.delay.no_args
      raw = ::YAML.unsafe_load(q.first["args"].first)
      assert_equal 4, raw.length
      assert_equal KwargsTarget, raw[0]
      assert_equal :no_args, raw[1]
      assert_equal [], raw[2]
      assert_equal({}, raw[3])
    end

    it "emits kwargs-only as [] args + kwargs hash" do
      q = Sidekiq::Queue.new
      KwargsTarget.delay.kwargs_only(name: "alice", value: 42)
      raw = ::YAML.unsafe_load(q.first["args"].first)
      assert_equal [], raw[2]
      assert_equal({name: "alice", value: 42}, raw[3])
    end

    it "preserves Ruby's own positional/kwargs split for a literal trailing Hash" do
      # The gem records whatever Ruby's calling convention puts in *args vs
      # **kwargs at the Proxy.method_missing call site.  Ruby itself differs
      # between versions for a literal trailing Hash:
      #   - Ruby 2.7  → auto-promotes the Hash to **kwargs (deprecation warning)
      #   - Ruby 3.0+ → keeps the Hash in *args (kwargs separation enforced)
      # Both outcomes are correct for the gem; this test asserts whichever is
      # appropriate for the running Ruby.  See README "Ruby version sensitivity".
      q = Sidekiq::Queue.new
      KwargsTarget.delay.positional_hash({color: :blue})
      raw = ::YAML.unsafe_load(q.first["args"].first)
      assert_equal 4, raw.length, "payload is always a 4-tuple regardless of Ruby version"
      if RUBY_VERSION >= "3.0"
        assert_equal [{color: :blue}], raw[2], "Ruby 3.0+: positional Hash stays in args slot"
        assert_equal({}, raw[3], "Ruby 3.0+: kwargs slot is empty")
      else
        assert_equal [], raw[2], "Ruby 2.7: trailing Hash auto-promoted out of args"
        assert_equal({color: :blue}, raw[3], "Ruby 2.7: trailing Hash auto-promoted into kwargs")
      end
    end
  end

  # =========================================================================
  # 2. Proxy payload shape — .delay_for and .delay_until
  # =========================================================================

  describe "Proxy payload shape — .delay_for and .delay_until" do
    it "delay_for emits a 4-tuple with kwargs" do
      ss = Sidekiq::ScheduledSet.new
      KwargsTarget.delay_for(5.minutes).mixed("a", "b", kw_a: :x)
      assert_equal 1, ss.size
      raw = ::YAML.unsafe_load(ss.first["args"].first)
      assert_equal 4, raw.length
      # Only explicitly-passed kwargs are captured; kw_b's default is applied
      # at dispatch time, not at enqueue time.
      assert_equal({kw_a: :x}, raw[3])
    end

    it "delay_until emits a 4-tuple with kwargs" do
      ss = Sidekiq::ScheduledSet.new
      KwargsTarget.delay_until(1.hour.from_now).kwargs_only(name: "bob", value: 7)
      assert_equal 1, ss.size
      raw = ::YAML.unsafe_load(ss.first["args"].first)
      assert_equal 4, raw.length
      assert_equal({name: "bob", value: 7}, raw[3])
    end
  end

  # =========================================================================
  # 3. Module target (non-class)
  # =========================================================================

  describe "Module target (non-class)" do
    it "emits a 4-tuple when delay is called on a module" do
      q = Sidekiq::Queue.new
      KwargsModule.delay.compute(factor: 3, base: 5)
      raw = ::YAML.unsafe_load(q.first["args"].first)
      assert_equal 4, raw.length
      assert_equal KwargsModule, raw[0]
      assert_equal :compute, raw[1]
      assert_equal [], raw[2]
      assert_equal({factor: 3, base: 5}, raw[3])
    end

    it "dispatches module kwargs correctly via GenericJob#perform" do
      yml = canonical_4tuple_yml(KwargsModule, :compute, [], {factor: 4, base: 3})
      result = Sidekiq::DelayExtensions::DelayedClass.new.perform(yml)
      assert_equal 12, result
    end
  end

  # =========================================================================
  # 4. YAML symbol key round-trip
  # =========================================================================

  describe "YAML symbol key round-trip" do
    it "preserves symbol keys through YAML dump/unsafe_load" do
      q = Sidekiq::Queue.new
      KwargsTarget.delay.mixed("a", "b", kw_a: :x, kw_b: :y)
      raw = ::YAML.unsafe_load(q.first["args"].first)
      kwargs_slot = raw[3]
      assert kwargs_slot.keys.all? { |k| k.is_a?(Symbol) },
        "kwargs keys must survive YAML round-trip as symbols, got: #{kwargs_slot.keys.inspect}"
    end

    it "preserves symbol values through YAML dump/unsafe_load" do
      q = Sidekiq::Queue.new
      KwargsTarget.delay.kwargs_only(name: :symbolic_name, value: :symbolic_value)
      raw = ::YAML.unsafe_load(q.first["args"].first)
      assert_equal :symbolic_name, raw[3][:name]
      assert_equal :symbolic_value, raw[3][:value]
    end

    it "symbol keys dispatch correctly after YAML round-trip (**kwargs splat)" do
      # If keys were stringified by YAML, **kwargs dispatch would raise
      # ArgumentError.  This is the core correctness guarantee.
      yml = canonical_4tuple_yml(KwargsTarget, :mixed, ["a", "b"], {kw_a: :x, kw_b: :y})
      result = Sidekiq::DelayExtensions::DelayedClass.new.perform(yml)
      assert_equal ["a", "b", :x, :y], result, "symbol-keyed kwargs must dispatch without ArgumentError"
    end
  end

  # =========================================================================
  # 5. GenericJob#perform dispatch from 4-tuple payload
  # =========================================================================

  describe "GenericJob#perform dispatch from 4-tuple payload" do
    it "re-splats mixed positional + keyword args" do
      yml = canonical_4tuple_yml(KwargsTarget, :mixed, ["a", "b"], {kw_a: :x, kw_b: :y})
      assert_equal ["a", "b", :x, :y], Sidekiq::DelayExtensions::DelayedClass.new.perform(yml)
    end

    it "uses method default when a kwarg is absent from the payload" do
      yml = canonical_4tuple_yml(KwargsTarget, :mixed, ["a", "b"], {kw_a: :x})
      assert_equal ["a", "b", :x, :default], Sidekiq::DelayExtensions::DelayedClass.new.perform(yml)
    end

    it "dispatches kwargs-only methods" do
      yml = canonical_4tuple_yml(KwargsTarget, :kwargs_only, [], {name: "alice", value: 42})
      assert_equal({name: "alice", value: 42}, Sidekiq::DelayExtensions::DelayedClass.new.perform(yml))
    end

    it "dispatches positional-only methods (empty kwargs slot)" do
      yml = canonical_4tuple_yml(KwargsTarget, :positional_only, [3, 4], {})
      assert_equal 7, Sidekiq::DelayExtensions::DelayedClass.new.perform(yml)
    end

    it "dispatches splat+double-splat methods" do
      yml = canonical_4tuple_yml(KwargsTarget, :splat_kwargs, ["x", "y"], {flag: true})
      assert_equal [["x", "y"], {flag: true}], Sidekiq::DelayExtensions::DelayedClass.new.perform(yml)
    end

    it "dispatches no-args, no-kwargs methods" do
      yml = canonical_4tuple_yml(KwargsTarget, :no_args, [], {})
      assert_equal :called_without_args, Sidekiq::DelayExtensions::DelayedClass.new.perform(yml)
    end
  end

  # =========================================================================
  # 6. display_class with 4-tuple payload
  # =========================================================================

  describe "display_class with 4-tuple payload" do
    it "shows 'ClassName.method_name' for class targets" do
      q = Sidekiq::Queue.new
      KwargsTarget.delay.mixed("a", "b", kw_a: :x)
      assert_equal "KwargsTarget.mixed", q.first.display_class
    end

    it "shows 'ModuleName.method_name' for module targets" do
      q = Sidekiq::Queue.new
      KwargsModule.delay.compute(factor: 2)
      assert_equal "KwargsModule.compute", q.first.display_class
    end
  end

  # =========================================================================
  # 7. display_args with 4-tuple payload
  # =========================================================================

  describe "display_args with 4-tuple payload" do
    it "returns flat positional array when kwargs slot is empty" do
      q = Sidekiq::Queue.new
      KwargsTarget.delay.positional_only(7, 8)
      assert_equal [7, 8], q.first.display_args
    end

    it "returns [positional_args, kwargs_hash] when kwargs are present" do
      q = Sidekiq::Queue.new
      KwargsTarget.delay.mixed("p", "q", kw_a: :one, kw_b: :two)
      assert_equal [["p", "q"], {kw_a: :one, kw_b: :two}], q.first.display_args
    end

    it "returns [[], kwargs_hash] for kwargs-only calls" do
      q = Sidekiq::Queue.new
      KwargsTarget.delay.kwargs_only(name: "dan", value: 0)
      assert_equal [[], {name: "dan", value: 0}], q.first.display_args
    end
  end

  # =========================================================================
  # 8. Full round-trip (Proxy → inline GenericJob)
  # =========================================================================

  describe "full round-trip via inline testing mode" do
    before do
      require "sidekiq/delay_extensions/testing"
      Sidekiq::Testing.inline!
    end

    after { Sidekiq::Testing.disable! }

    it "round-trips mixed positional + keyword args without loss" do
      result = nil
      KwargsTarget.stub(:mixed, ->(pos_a, pos_b, kw_a:, kw_b: :default) {
        result = [pos_a, pos_b, kw_a, kw_b]
      }) do
        KwargsTarget.delay.mixed("hello", "world", kw_a: :foo, kw_b: :bar)
      end
      assert_equal ["hello", "world", :foo, :bar], result
    end

    it "round-trips kwargs-only without loss" do
      result = nil
      KwargsTarget.stub(:kwargs_only, ->(name:, value:) { result = {name: name, value: value} }) do
        KwargsTarget.delay.kwargs_only(name: "bob", value: 99)
      end
      assert_equal({name: "bob", value: 99}, result)
    end

    it "round-trips a no-kwargs call (positional only) without loss" do
      result = nil
      KwargsTarget.stub(:positional_only, ->(a, b) { result = a + b }) do
        KwargsTarget.delay.positional_only(10, 32)
      end
      assert_equal 42, result
    end
  end

  # =========================================================================
  # 9. DelayedModel — class-method and AR-instance-method paths
  # =========================================================================

  describe "DelayedModel — class-method path" do
    it "emits a 4-tuple when delay is called on an AR-like class" do
      q = Sidekiq::Queue.new
      proxy = Sidekiq::DelayExtensions::Proxy.new(
        Sidekiq::DelayExtensions::DelayedModel, KwargsRecord
      )
      proxy.process(42, action: :archive, priority: :high)
      raw = ::YAML.unsafe_load(q.first["args"].first)
      assert_equal 4, raw.length
      assert_equal KwargsRecord, raw[0]
      assert_equal :process, raw[1]
      assert_equal [42], raw[2]
      assert_equal({action: :archive, priority: :high}, raw[3])
    end

    it "dispatches kwargs correctly via DelayedModel#perform" do
      yml = canonical_4tuple_yml(KwargsRecord, :process, [42], {action: :archive, priority: :high})
      result = Sidekiq::DelayExtensions::DelayedModel.new.perform(yml)
      assert_equal [42, :archive, :high], result
    end

    it "dispatches with default kwarg when optional kwarg omitted" do
      yml = canonical_4tuple_yml(KwargsRecord, :process, [7], {action: :sync})
      result = Sidekiq::DelayExtensions::DelayedModel.new.perform(yml)
      assert_equal [7, :sync, :normal], result
    end
  end

  describe "DelayedModel — AR-instance-method path (production usage shape)" do
    # In production, delay_extensions wires Sidekiq::DelayExtensions::ActiveRecord
    # onto ActiveRecord::Base via ActiveSupport.on_load(:active_record).  Each AR
    # instance gains #delay / #delay_for / #delay_until methods that target the
    # instance.  This test exercises that exact path with kwargs.

    it "instance.delay.method(kwarg: val) emits a 4-tuple targeting the instance" do
      q = Sidekiq::Queue.new
      instance = KwargsActiveModel.new
      instance.delay.update_with(new_status: :active, audited_by: :sso)
      raw = ::YAML.unsafe_load(q.first["args"].first)
      assert_equal 4, raw.length
      assert_kind_of KwargsActiveModel, raw[0], "instance must be the target slot"
      assert_equal :update_with, raw[1]
      assert_equal [], raw[2]
      assert_equal({new_status: :active, audited_by: :sso}, raw[3])
    end

    it "instance.delay round-trips kwargs through inline dispatch" do
      require "sidekiq/delay_extensions/testing"
      Sidekiq::Testing.inline!
      instance = KwargsActiveModel.new
      instance.delay.update_with(new_status: :active, audited_by: :sso)
      assert_equal({new_status: :active, audited_by: :sso}, KwargsActiveModel.received)
    ensure
      Sidekiq::Testing.disable!
    end
  end

  # =========================================================================
  # 10. DelayedMailer — emission + dispatch with captured kwargs assertion
  # =========================================================================

  describe "DelayedMailer (mailer subclass of GenericJob)" do
    it "emits a 4-tuple for mailer delay calls" do
      q = Sidekiq::Queue.new
      KwargsMailer.delay.welcome(name: "carol", locale: :fr)
      raw = ::YAML.unsafe_load(q.first["args"].first)
      assert_equal 4, raw.length
      assert_equal KwargsMailer, raw[0]
      assert_equal :welcome, raw[1]
      assert_equal [], raw[2]
      assert_equal({name: "carol", locale: :fr}, raw[3])
    end

    it "dispatches kwargs to the mailer method (asserted via captured args)" do
      # KwargsMailer#welcome stores its received kwargs in KwargsMailer.captured_args.
      # If the kwargs aren't re-splatted correctly, the method either raises
      # ArgumentError before capture or captures the wrong values.  Either way
      # the assertion below catches it — no silent vacuous pass.
      yml = canonical_4tuple_yml(KwargsMailer, :welcome, [], {name: "carol", locale: :fr})
      Sidekiq::DelayExtensions::DelayedMailer.new.perform(yml)
      assert_equal({name: "carol", locale: :fr}, KwargsMailer.captured_args)
    end
  end

  # =========================================================================
  # 11. Sidekiq 6.4 built-in payload compatibility
  # =========================================================================
  #
  # Any job enqueued by Sidekiq 6.4's built-in delay extension and still
  # sitting in the queue / retry set at deploy time must dispatch correctly
  # with 7.2.0.  The 6.4 built-in used the same 4-tuple format.

  describe "Sidekiq 6.4 built-in payload compatibility" do
    it "dispatches a 6.4-style 4-tuple payload with symbol kwargs" do
      # Replicates sidekiq-6.4.0 lib/sidekiq/extensions/generic_proxy.rb:
      #   obj = [@target, name, args, kwargs]
      sidekiq_64_yml = ::YAML.dump([KwargsTarget, :mixed, ["a", "b"], {kw_a: :x, kw_b: :y}])
      result = Sidekiq::DelayExtensions::DelayedClass.new.perform(sidekiq_64_yml)
      assert_equal ["a", "b", :x, :y], result
    end

    it "dispatches a 6.4-style payload for kwargs-only methods" do
      sidekiq_64_yml = ::YAML.dump([KwargsTarget, :kwargs_only, [], {name: "migration", value: 1}])
      result = Sidekiq::DelayExtensions::DelayedClass.new.perform(sidekiq_64_yml)
      assert_equal({name: "migration", value: 1}, result)
    end

    it "dispatches a 6.4-style payload for positional-only methods" do
      sidekiq_64_yml = ::YAML.dump([KwargsTarget, :positional_only, [5, 6], {}])
      result = Sidekiq::DelayExtensions::DelayedClass.new.perform(sidekiq_64_yml)
      assert_equal 11, result
    end
  end

  # =========================================================================
  # 12. Regression — discussion #6979 exact repro
  # =========================================================================
  #
  # The reporter called User.delay.call('1', hello: 'there') and got:
  #   ArgumentError: wrong number of arguments (given 3, expected 2)
  #   from generic_job.rb:48 in `_perform'

  describe "regression — discussion #6979 exact repro" do
    it "enqueues the correct 4-tuple for User.delay.call('1', hello: 'there')" do
      q = Sidekiq::Queue.new
      KwargsTarget.delay.call("1", hello: "there")
      raw = ::YAML.unsafe_load(q.first["args"].first)
      assert_equal 4, raw.length, "broken 7.1.0 produced a 3-tuple — must be 4-tuple now"
      assert_equal ["1"], raw[2], "positional args must be in slot 2"
      assert_equal({hello: "there"}, raw[3], "kwargs must be in slot 3, not folded into args")
    end

    it "dispatches without ArgumentError for the #6979 call pattern" do
      yml = canonical_4tuple_yml(KwargsTarget, :call, ["1"], {hello: "there"})
      result = Sidekiq::DelayExtensions::DelayedClass.new.perform(yml)
      assert_equal({id: "1", hello: "there"}, result)
    end

    it "produces the SAME payload shape as Sidekiq 6.4 built-in for the #6979 pattern" do
      q = Sidekiq::Queue.new
      KwargsTarget.delay.call("1", hello: "there")
      gem_payload = ::YAML.unsafe_load(q.first["args"].first)

      # Manually construct what Sidekiq 6.4 built-in generic_proxy.rb:22 produced:
      #   obj = [@target, name, args, kwargs]
      expected = [KwargsTarget, :call, ["1"], {hello: "there"}]
      assert_equal expected, gem_payload, "gem 7.2.0 payload must be identical to Sidekiq 6.4 built-in payload"
    end
  end

  # =========================================================================
  # 13. Backward compatibility — legacy 3-tuple payloads
  # =========================================================================
  #
  # Jobs enqueued by gem 7.0–7.1 on Ruby 3.1 are 3-tuples with kwargs folded
  # into args.  After upgrading to 7.2.0, those payloads are still in the
  # queue.  The fix must not introduce any NEW exception for those jobs —
  # dispatch behaviour must be identical to what 7.1.0 produced.

  describe "backward compatibility — legacy 3-tuple payloads" do
    it "pure positional 3-tuple (no kwargs ever passed) dispatches correctly" do
      yml = legacy_3tuple_positional_only(KwargsTarget, :positional_only, [5, 6])
      assert_equal 11, Sidekiq::DelayExtensions::DelayedClass.new.perform(yml)
    end

    it "3-tuple with folded kwargs dispatches without raising — version-appropriate result" do
      # The fix's contract for legacy 3-tuple payloads: do not introduce any new
      # exception relative to pre-7.2.0.  Final dispatch shape depends on Ruby:
      #   - Ruby 2.7  → _perform's **kwargs splat auto-promotes the trailing Hash,
      #                 happily routing the kwargs to the target method (rescue).
      #   - Ruby 3.0+ → no auto-promotion; the Hash stays positional, matching
      #                 the broken 7.1.0 dispatch path (no regression).
      yml = legacy_3tuple_with_folded_kwargs(KwargsTarget, :splat_kwargs, ["x"], {flag: true})
      result = Sidekiq::DelayExtensions::DelayedClass.new.perform(yml)
      if RUBY_VERSION >= "3.0"
        assert_equal [["x", {flag: true}], {}], result,
          "Ruby 3.0+: dispatch identical to pre-7.2.0 (hash stays positional)"
      else
        assert_equal [["x"], {flag: true}], result,
          "Ruby 2.7: language auto-promotion routes folded kwargs to **kwargs"
      end
    end

    it "the gem adds no heuristic kwargs promotion (delegates entirely to Ruby)" do
      # The gem must NOT add its own logic to promote a trailing positional
      # Hash to kwargs — that would be wrong for methods that legitimately
      # accept a positional Hash.  Whatever happens at dispatch is purely
      # Ruby's calling convention for the running version.
      yml = legacy_3tuple_with_folded_kwargs(KwargsTarget, :splat_kwargs, [], {a: 1})
      result = Sidekiq::DelayExtensions::DelayedClass.new.perform(yml)
      if RUBY_VERSION >= "3.0"
        assert_equal [[{a: 1}], {}], result,
          "Ruby 3.0+: no auto-promotion; trailing Hash stays positional in *args"
      else
        assert_equal [[], {a: 1}], result,
          "Ruby 2.7: language-level auto-promotion routes the Hash to **kwargs"
      end
    end
  end

  # =========================================================================
  # 14. GenericProxy (use_generic_proxy=true) — unchanged
  # =========================================================================

  describe "GenericProxy path (use_generic_proxy=true) is unaffected" do
    before { Sidekiq::DelayExtensions.use_generic_proxy = true }
    after { Sidekiq::DelayExtensions.use_generic_proxy = false }

    it "still emits a 3-element JSON array (not YAML 4-tuple)" do
      q = Sidekiq::Queue.new
      KwargsTarget.delay.splat_kwargs("a", flag: true)
      raw = ::JSON.parse(q.first["args"].first)
      assert_equal 3, raw.length, "GenericProxy always emits a JSON 3-tuple"
    end

    it "dispatches a 4-tuple payload correctly via the generic proxy perform path" do
      yml = canonical_4tuple_yml(KwargsTarget, :splat_kwargs, ["a"], {flag: true})
      result = Sidekiq::DelayExtensions::DelayedClass.new.perform(yml)
      assert_equal [["a"], {flag: true}], result
    end

    it "dispatches a kwargs-only call via the generic proxy perform path" do
      yml = canonical_4tuple_yml(KwargsTarget, :kwargs_only, [], {name: "gp", value: 5})
      result = Sidekiq::DelayExtensions::DelayedClass.new.perform(yml)
      assert_equal({name: "gp", value: 5}, result)
    end
  end
end
