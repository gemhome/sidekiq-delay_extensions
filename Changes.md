# Sidekiq Delay Extensions Changes

[See Sidekiq for its changes](https://github.com/mperham/sidekiq/blob/main/Changes.md)

Unreleased
---------

7.2.0
---------

### ⚠️ Visible behaviour changes — read before upgrading

1. **Wire-format change:** the YAML payload emitted for every `delay` /
   `delay_for` / `delay_until` call is now a 4-tuple
   `[target, method_name, positional_args, kwargs]` instead of a 3-tuple.
   This restores the format that Sidekiq 6.4's built-in delay extension
   always produced.  Jobs enqueued by 7.0–7.1 (3-tuple) are still dispatched
   correctly with no new exceptions — see the migration section in the
   README.

2. **`Sidekiq::JobRecord#display_args` format change for delay jobs:** when
   keyword arguments are present, `display_args` now returns
   `[positional_args, kwargs_hash]` instead of a flat merged array.  This
   restores the structured separation that the gem's `api.rb` was always
   written for.  If you have custom Web UI extensions, log scrapers, or
   observability tooling that read `display_args` for delay jobs, update
   those consumers — see the README "`display_args` format change" section
   for examples.

   ```ruby
   # 7.1.0 (3-tuple, kwargs merged into positional)
   job.display_args  #=> ["alice@example.com", {locale: :en}]

   # 7.2.0+ (4-tuple, structured separation)
   job.display_args  #=> [["alice@example.com"], {locale: :en}]
   ```

### Fix

- **`Proxy` now emits a 4-tuple YAML payload matching Sidekiq 6.4 semantics.**

  Prior to this release, `Proxy#method_missing` was declared as
  `def method_missing(name, *args)` — missing the `**kwargs` parameter.  On
  Ruby 3.1+ keyword arguments no longer auto-convert from a trailing positional
  Hash, so a call like `User.delay.call("1", locale: :en)` collapsed the
  `{locale: :en}` hash into `*args` instead of capturing it separately.  The
  resulting 3-tuple YAML payload (`[target, method, args_with_folded_kwargs]`)
  lost all kwargs information, causing `ArgumentError` on dispatch for any
  method with named keyword parameters.  See discussion
  [sidekiq#6979](https://github.com/sidekiq/sidekiq/discussions/6979).

  The fix restores the signature to `def method_missing(name, *args, **kwargs)`
  and emits a 4-tuple `[target, method_name, positional_args, kwargs]` —
  identical to the layout that Sidekiq 6.4's built-in delay extension always
  produced.  `GenericJob#perform` is updated to destructure all four slots and
  re-splat kwargs explicitly on dispatch.

### Backward compatibility

  Jobs already sitting in your queue / retry set / scheduled set at deploy
  time use the old 3-tuple format.  `GenericJob#perform` handles those
  gracefully: the missing kwargs slot is treated as an empty Hash, producing
  the same dispatch behaviour as before 7.2.0 (no new exceptions introduced).
  See the README migration section for guidance on draining or replaying
  affected jobs.

### Unchanged

- `GenericProxy` (`use_generic_proxy = true`) is unchanged; it already handled
  kwargs via its own JSON serialisation path.

7.1.0
---------

- New `Sidekiq::DelayExtensions::GenericJob` superclass for DelayedMailer, DelayedModel, DelayedClass
  - it has a `_perform` method which accepts the unmarshalled and processed
    `(target, method_name, *args, **kwargs)` and can be overridden or extended as needed.
- New (opt-in) `Sidekiq::DelayExtensions::GenericProxy` which can parse JSON or YAML delayed arguments
  into a `target`, `method_name`, `args`, and `kwargs` before.
- New (opt-in) setting `Sidekiq::DelayExtensions.use_generic_proxy` (defaults to false).
  - When false, there is no delayed proxy changes; the original `Sidekiq::DelayExtensions::Proxy` is used.
  - When true, the new `Sidekiq::DelayExtensions::GenericProxy` is used, which handles both `*args` and `**kwargs` more naturally.
    Be sure to test this works for you as expected when turning this on.
- Chore: Load YAML consistently via `::Sidekiq::DelayExtensions::YAML`

7.0.0
---------

- Require Sidekiq >= 7.0

6.5.12
---------

- Extracted from https://github.com/mperham/sidekiq/tree/v6.5.12

6.4.1
---------

- Extracted from https://github.com/mperham/sidekiq/tree/v6.4.1

6.4.0
---------

- Extracted from https://github.com/mperham/sidekiq/tree/v6.4.0
