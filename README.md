Sidekiq Delay Extensions
==============

[![Gem Version](https://badge.fury.io/rb/sidekiq-delay_extensions.svg)](https://rubygems.org/gems/sidekiq-delay_extensions)
![Build](https://github.com/gemhome/sidekiq-delay_extensions/workflows/CI/badge.svg)

The [Sidekiq delay extensions were deprecated in 6.x and were removed from 7.x](https://github.com/mperham/sidekiq/issues/5076).

This gem extracts the delay extensions from the latest 6.x release, 6.5.12.
Version 7.x of this gem will maintain compatibility with Sidekiq 7.x.

This gem is maintained independent of Sidekiq. Maintainers wanted.

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

    # To handle any existing delayed jobs at time of upgrade.
    Sidekiq::Extensions::DelayedClass = Sidekiq::DelayExtensions::DelayedClass
    Sidekiq::Extensions::DelayedModel = Sidekiq::DelayExtensions::DelayedModel
    Sidekiq::Extensions::DelayedMailer = Sidekiq::DelayExtensions::DelayedMailer

Testing
-----------------

In your test environment, include the line:

    require "sidekiq/delay_extensions/testing"

Contributing
-----------------

Please see [the contributing guidelines](https://github.com/gemhome/sidekiq-delay_extensions/blob/main/.github/contributing.md).


License
-----------------

Please see [LICENSE](https://github.com/gemhome/sidekiq-delay_extensions/blob/main/LICENSE) for licensing details.


Original Author
-----------------

Mike Perham, [@getajobmike](https://twitter.com/getajobmike) / [@sidekiq](https://twitter.com/sidekiq), [https://www.mikeperham.com](https://www.mikeperham.com) / [https://www.contribsys.com](https://www.contribsys.com)
