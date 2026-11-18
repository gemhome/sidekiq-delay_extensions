Sidekiq Delay Extensions
==============

[![Gem Version](https://badge.fury.io/rb/sidekiq-delay_extensions.svg)](https://rubygems.org/gems/sidekiq-delay_extensions)
![Build](https://github.com/gemhome/sidekiq-delay_extensions/workflows/CI/badge.svg)

The [Sidekiq delay extensions were deprecated in 6.x and were removed from 7.x](https://github.com/mperham/sidekiq/issues/5076).

This gem extracts the delay extensions from the latest 6.x release, 6.5.12.
Version 8.x of this gem supports Sidekiq 7.x and 8.x. Version 7.x of this gem supports Sidekiq 7.x.

This gem is maintained independent of Sidekiq. Maintainers wanted.

Requirements
-----------------

Version 8.x of this gem requires Ruby 3.3 or later with either Sidekiq version. Rails is optional.

| Sidekiq version | Data store | Rails integration | Upstream requirements |
| --- | --- | --- | --- |
| 7.x | Redis 6.2+, or Dragonfly 1.13+ with Sidekiq 7.2+ | Rails 6.0+ | [Sidekiq 7 documentation](https://github.com/sidekiq/sidekiq/blob/v7.3.10/README.md#requirements) |
| 8.x | Redis 7.0+, Valkey 7.2+, or Dragonfly 1.27+ | Rails 7.0+ | [Sidekiq 8 documentation](https://github.com/sidekiq/sidekiq/blob/main/docs/8.0-Upgrade.md#version-support) |

Sidekiq 8.0.0 specifically requires Redis 7.2 or later. Redis 7.0 support starts with Sidekiq 8.0.1. [Sidekiq 8.0.1 release notes](https://github.com/sidekiq/sidekiq/blob/main/Changes.md#801)

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
