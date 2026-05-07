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
#  1.  Proxy payload shape  — 4-tuple emitted for delay / delay_for / delay_until
#  2.  Payload slots         — target, method, args, kwargs each in the right slot
#  3.  Edge cases            — kwargs-only, positional-only, positional Hash ≠ kwargs
#  4.  Module target         — Proxy works on plain modules, not just classes
#  5.  YAML symbol round-trip — kwargs keys survive serialisation as symbols
#  6.  GenericJob dispatch   — perform re-splats kwargs correctly from 4-tuple
#  7.  dispatch_class        — display_class is correct with 4-tuple payload
#  8.  display_args          — positional/kwargs shown separately when kwargs present
#  9.  Full round-trip        — enqueue via Proxy, execute inline via GenericJob
# 10.  DelayedModel          — all three job subclasses exercised
# 11.  DelayedMailer         — mailer 4-tuple emission + dispatch without ArgumentError
# 12.  Sidekiq 6.4 compat    — exact 4-tuple YAML from the old built-in dispatches OK
# 13.  Regression scenario   — exact broken call from discussion #6979
# 14.  Backward compat       — legacy 3-tuple payloads dispatched without new exceptions
# 15.  GenericProxy unchanged — use_generic_proxy=true path is unaffected

require_relative "helper"
require "sidekiq/api"
require "active_record"
require "action_mailer"
Sidekiq::DelayExtensions.enable_delay!

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
  def welcome(name:, locale: :en)
    name
  end
end

# Minimal AR-like class for DelayedModel tests (avoids sqlite3 setup)
class KwargsRecord
  def self.process(entity_id, action:, priority: :normal)
    [entity_id, action, priority]
  end
end

# ---------------------------------------------------------------------------
# YAML helpers
# ---------------------------------------------------------------------------

# 3-tuple YAML as the broken 7.1.0 Proxy emitted on Ruby 3.1 when called with
# keyword arguments — kwargs are folded as a trailing element of *args.
def legacy_3tuple_yml(target, method_sym, positional_args, kwargs_hash)
  ::YAML.dump([target, method_sym, positional_args + [kwargs_hash]])
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
  end

  after do
    Sidekiq::DelayExtensions.use_generic_proxy = false
  end

  # =========================================================================
  # 1–4. Proxy payload shape
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

    it "emits kwargs-only as [] args + kwargs hash" do
      q = Sidekiq::Queue.new
      KwargsTarget.delay.kwargs_only(name: "alice", value: 42)
      raw = ::YAML.unsafe_load(q.first["args"].first)
      assert_equal [], raw[2]
      assert_equal({name: "alice", value: 42}, raw[3])
    end

    it "does not conflate a positional Hash with kwargs" do
      q = Sidekiq::Queue.new
      KwargsTarget.delay.positional_hash({color: :blue})
      raw = ::YAML.unsafe_load(q.first["args"].first)
      assert_equal [{color: :blue}], raw[2], "positional hash must stay in args slot"
      assert_equal({}, raw[3], "kwargs slot must be empty")
    end
  end

  describe "Proxy payload shape — .delay_for and .delay_until" do
    it "delay_for emits a 4-tuple with kwargs" do
      ss = Sidekiq::ScheduledSet.new
      KwargsTarget.delay_for(5.minutes).mixed("a", "b", kw_a: :x)
      assert_equal 1, ss.size
      raw = ::YAML.unsafe_load(ss.first["args"].first)
      assert_equal 4, raw.length
      # Only explicitly-passed kwargs are in the payload; kw_b default is applied at dispatch.
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
  # 4. Module target
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
  # 5. YAML symbol key round-trip
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
      # This is the core correctness guarantee: if keys were stringified by YAML,
      # **kwargs dispatch would raise ArgumentError.
      yml = canonical_4tuple_yml(KwargsTarget, :mixed, ["a", "b"], {kw_a: :x, kw_b: :y})
      result = Sidekiq::DelayExtensions::DelayedClass.new.perform(yml)
      assert_equal ["a", "b", :x, :y], result, "symbol-keyed kwargs must dispatch without ArgumentError"
    end
  end

  # =========================================================================
  # 6. GenericJob#perform dispatch
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
  end

  # =========================================================================
  # 7. display_class
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
  # 8. display_args
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
  # 9. Full round-trip (Proxy → inline GenericJob)
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
  # 10. DelayedModel
  # =========================================================================

  describe "DelayedModel (AR model subclass of GenericJob)" do
    it "emits a 4-tuple when delay is called on an AR-like class" do
      q = Sidekiq::Queue.new
      # Use the DelayedModel job class explicitly via the client_push path
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

  # =========================================================================
  # 11. DelayedMailer
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

    it "does not raise ArgumentError when kwargs are supplied via 4-tuple on perform" do
      yml = canonical_4tuple_yml(KwargsMailer, :welcome, [], {name: "carol", locale: :fr})
      begin
        Sidekiq::DelayExtensions::DelayedMailer.new.perform(yml)
      rescue => e
        refute_match(/wrong number of arguments/, e.message,
          "kwargs mismatch ArgumentError must not occur — got: #{e.message}")
      end
    end
  end

  # =========================================================================
  # 12. Sidekiq 6.4 built-in payload compatibility
  # =========================================================================
  #
  # Any job enqueued by Sidekiq 6.4's built-in delay extension and still
  # sitting in the queue / retry set at deploy time must dispatch correctly
  # with 7.2.0.  The 6.4 built-in used the same 4-tuple format.

  describe "Sidekiq 6.4 built-in payload compatibility" do
    it "dispatches a 6.4-style 4-tuple payload with symbol kwargs" do
      # Replicate the exact YAML that sidekiq-6.4.0 lib/sidekiq/extensions/generic_proxy.rb
      # would produce: [target, method_sym, positional_args, kwargs_hash]
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
  # 13. Regression scenario — exact broken call from discussion #6979
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
      assert_equal 4, raw.length,
        "broken 7.1.0 produced a 3-tuple — must be 4-tuple now"
      assert_equal ["1"], raw[2], "positional args must be in slot 2"
      assert_equal({hello: "there"}, raw[3], "kwargs must be in slot 3, not folded into args"
      )
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
      assert_equal expected, gem_payload,
        "gem 7.2.0 payload must be identical to Sidekiq 6.4 built-in payload"
    end
  end

  # =========================================================================
  # 14. Backward compatibility — legacy 3-tuple payloads
  # =========================================================================
  #
  # Jobs enqueued by gem 7.0–7.1 on Ruby 3.1 are 3-tuples with kwargs folded
  # into args.  After upgrading to 7.2.0, those payloads are still in the
  # queue.  The fix must not introduce any NEW exception for those jobs.

  describe "backward compatibility — legacy 3-tuple payloads" do
    it "pure positional 3-tuple (no kwargs ever involved) dispatches correctly" do
      yml = ::YAML.dump([KwargsTarget, :positional_only, [5, 6]])
      assert_equal 11, Sidekiq::DelayExtensions::DelayedClass.new.perform(yml)
    end

    it "3-tuple with folded kwargs: hash stays positional — no new exception" do
      yml = legacy_3tuple_yml(KwargsTarget, :splat_kwargs, ["x"], {flag: true})
      # kwargs slot is absent → treated as {} → dispatched without ** splat.
      # On Ruby 3.1 the hash stays as a positional element in *args.
      result = Sidekiq::DelayExtensions::DelayedClass.new.perform(yml)
      assert_equal [["x", {flag: true}], {}], result,
        "behaviour must be identical to pre-7.2.0: no new exception, hash stays positional"
    end

    it "3-tuple with empty folded hash dispatches as before (ArgumentError for arity mismatch)" do
      # The broken proxy emitted an empty {} as a trailing positional arg even
      # when no kwargs were passed, so positional_only would get 3 args not 2.
      yml = legacy_3tuple_yml(KwargsTarget, :positional_only, [10, 20], {})
      assert_raises(ArgumentError) do
        Sidekiq::DelayExtensions::DelayedClass.new.perform(yml)
      end
    end

    it "3-tuple does NOT incorrectly promote the trailing hash to kwargs" do
      # Heuristic promotion would be wrong for positional-hash methods.
      yml = legacy_3tuple_yml(KwargsTarget, :splat_kwargs, [], {a: 1})
      result = Sidekiq::DelayExtensions::DelayedClass.new.perform(yml)
      # The hash must land in *args, not in **kwargs.
      assert_equal [[{a: 1}], {}], result,
        "legacy 3-tuple trailing hash must NOT be promoted to **kwargs"
    end
  end

  # =========================================================================
  # 15. GenericProxy (use_generic_proxy=true) — unchanged
  # =========================================================================

  describe "GenericProxy path (use_generic_proxy=true) is unaffected" do
    before { Sidekiq::DelayExtensions.use_generic_proxy = true }
    after  { Sidekiq::DelayExtensions.use_generic_proxy = false }

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
