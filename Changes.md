# Sidekiq Delay Extensions Changes

[See Sidekiq for its changes](https://github.com/mperham/sidekiq/blob/main/Changes.md)

Unreleased
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
