Sidekiq Delay Extensions
==============

[![Gem Version](https://badge.fury.io/rb/sidekiq-delay_extensions.svg)](https://rubygems.org/gems/sidekiq-delay_extensions)
![Build](https://github.com/gemhome/sidekiq-delay_extensions/workflows/CI/badge.svg)

The [Sidekiq delay extensions were deprecated in 6.x and were removed from 7.x](https://github.com/mperham/sidekiq/issues/5076).

This gem extracts the delay extensions from the latest 6.x release, 6.5.12.
Version 7.x of this gem will maintain compatibility with Sidekiq 7.x.

This gem is maintained independent of Sidekiq. Maintainers wanted.

Migrating from Sidekiq 6 to 7 (kwargs fix)
-----------------

If you are upgrading from Sidekiq 6 (which had delay extensions built-in) to
Sidekiq 7 + this gem, ensure you are on **7.2.0 or later**.

### What broke and why

Sidekiq 6.4's built-in `Proxy` serialised every delay call as a **4-tuple**:

```yaml
- !ruby/class 'User'
- :send_welcome
- ["alice@example.com"]   # positional args
- :locale: :en             # kwargs — always in their own slot
```

Versions 7.0.0–7.1.x of this gem regressed to a **3-tuple** because
`Proxy#method_missing` lacked the `**kwargs` parameter.  On Ruby 3.1+ keyword
arguments are no longer auto-promoted from a trailing positional Hash, so

```ruby
User.delay.send_welcome("alice@example.com", locale: :en)
```

produced `{locale: :en}` folded into `*args` instead:

```yaml
- !ruby/class 'User'
- :send_welcome
- ["alice@example.com", {locale: :en}]   # 3-tuple — kwargs lost!
```

On dispatch, `GenericJob#perform` called `target.__send__(method, *args)` which
passed the hash as a positional argument and raised
`ArgumentError: wrong number of arguments` for any method with named keywords.

### Fix (7.2.0+)

`Proxy#method_missing` is restored to `def method_missing(name, *args, **kwargs)`
and the 4-tuple payload format is re-established.  `GenericJob#perform`
destructures all four slots and re-splats kwargs correctly.

### Handling jobs already in the queue at deploy time

Jobs enqueued before the upgrade (3-tuple format) will still be in your queue,
retry set, and scheduled set when you deploy 7.2.0.  `GenericJob#perform`
treats the missing kwargs slot as an empty `{}` — the same no-kwargs dispatch
path as before — so **no new exceptions are introduced for those jobs**.

However, because the kwargs were folded into positional args at enqueue time,
they cannot be recovered retroactively.  Those jobs will continue to fail (as
they did on the old version) for methods that require keyword arguments.

**Recommended approach for the transition window:**

1. Deploy 7.2.0.  All *new* delay calls from this point forward are correct.
2. Drain or discard any existing 3-tuple jobs that call methods with required
   kwargs (they were already failing, so discarding them is safe).
3. Over the following days, the retry / scheduled sets will naturally empty out
   as those jobs exhaust their retries.

If you need zero downtime and cannot tolerate the failure window, enqueue a
migration job before deploying that moves affected jobs out of the retry/dead
sets, or use a Sidekiq server middleware to detect and re-enqueue the 3-tuple
payloads with corrected kwargs (see the discussion in
[#6979](https://github.com/sidekiq/sidekiq/discussions/6979)).

### `display_args` format change

When kwargs are present, `Sidekiq::JobRecord#display_args` now returns
`[positional_args, kwargs_hash]` instead of a flat merged array:

```ruby
# Before 7.2.0 (3-tuple, kwargs merged into positional)
job.display_args  #=> ["alice@example.com", {locale: :en}]

# 7.2.0+ (4-tuple, structured separation)
job.display_args  #=> [["alice@example.com"], {locale: :en}]
```

If your code inspects `display_args` directly (e.g. in custom Web UI
extensions, log scrapers, or observability tooling), update those consumers
accordingly.

### Ruby version sensitivity

The gem records whatever Ruby's calling convention puts in `*args` vs
`**kwargs` at the call site.  Ruby 3.0 changed this convention — a trailing
positional `Hash` is no longer auto-promoted to keyword arguments.  So the
*same source line* produces a different payload (and a different dispatch
shape) depending on the Ruby version:

```ruby
KwargsTarget.delay.foo({color: :blue})

# Ruby 2.7  (auto-promotes, deprecation warning):
#   payload = [KwargsTarget, :foo, [],                {color: :blue}]
# Ruby 3.0+ (separation enforced):
#   payload = [KwargsTarget, :foo, [{color: :blue}],  {}]
```

This is Ruby's behaviour, not the gem's, but worth being aware of when
upgrading Ruby alongside the gem.  **Avoid the literal-Hash-as-positional
form** (`delay.foo({color: :blue})`) because the intent is ambiguous across
Ruby versions.  Use:

- `delay.foo(color: :blue)` — explicit kwargs, identical on every Ruby.
- `delay.foo(opts)` where `opts = {color: :blue}` is a local variable and
  the target method declares a positional Hash parameter — explicit
  positional, identical on every Ruby.

A useful side effect of Ruby 2.7's auto-promotion: legacy 3-tuple payloads
enqueued by gem 7.0–7.1 actually *recover* their kwargs at dispatch time on
Ruby 2.7 (the language splat re-routes the folded Hash into `**kwargs` for
us).  On Ruby 3.0+, those payloads dispatch identically to pre-7.2.0 — the
Hash stays positional, no new exceptions.

### Other Sidekiq plugins (Pro, Cron, unique-jobs, alive)

Sidekiq Pro, sidekiq-cron, sidekiq-unique-jobs, and sidekiq_alive treat the
delay job's `args[0]` as an opaque marshalled string — they do not parse the
YAML payload themselves.  This change is therefore transparent to those
plugins and requires no coordinated upgrade.

Requirements
-----------------

- See https://github.com/sidekiq/sidekiq/blob/main/Changes.md#700
  - Redis: 6.2+
  - Ruby: MRI 2.7+ or JRuby 9.3+.
  - Sidekiq 7.0 supports Rails 6.0+ but does not require it.

Installation
-----------------

    bundle add sidekiq
    bundle add sidekiq-delay_extensions

In your initializers, include the line:

    Sidekiq::DelayExtensions.enable_delay!

Upgrading (IMPORTANT): Also add

```ruby
# To handle any existing delayed jobs at time of upgrade.
module Sidekiq::Extensions
end
Sidekiq::Extensions::DelayedClass = Sidekiq::DelayExtensions::DelayedClass
Sidekiq::Extensions::DelayedModel = Sidekiq::DelayExtensions::DelayedModel
Sidekiq::Extensions::DelayedMailer = Sidekiq::DelayExtensions::DelayedMailer
```

Testing
-----------------

In your test environment, include the line:

```ruby
require "sidekiq/delay_extensions/testing"
```

Contributing
-----------------

Please see [the contributing guidelines](https://github.com/gemhome/sidekiq-delay_extensions/blob/main/.github/contributing.md).


License
-----------------

Please see [LICENSE](https://github.com/gemhome/sidekiq-delay_extensions/blob/main/LICENSE) for licensing details.


Original Author
-----------------

Mike Perham, [@getajobmike](https://twitter.com/getajobmike) / [@sidekiq](https://twitter.com/sidekiq), [https://www.mikeperham.com](https://www.mikeperham.com) / [https://www.contribsys.com](https://www.contribsys.com)
