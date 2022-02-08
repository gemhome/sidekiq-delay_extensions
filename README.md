Sidekiq Delay Extensions
==============

[![Gem Version](https://badge.fury.io/rb/sidekiq-delay_extensions.svg)](https://rubygems.org/gems/sidekiq-delay_extensions)
![Build](https://github.com/gehome/sidekiq-delay_extensions/workflows/CI/badge.svg)

The [Sidekiq delay extensions are deprecated in 6.x and will be removed from 7.x](https://github.com/mperham/sidekiq/issues/5076).

This gem extracts the delay extensions from the latest 6.x release and will match
Sidekiq 6.x version numbers.  

When Sidekiq reaches 7.0, this gem will begin being maintained on its own. Maintainers wanted.

Requirements
-----------------

- See https://github.com/mperham/sidekiq/tree/v6.4.0
  - Redis: 4.0+
  - Ruby: MRI 2.5+ or JRuby 9.2+.
  - Sidekiq 6.0 supports Rails 5.0+ but does not require it.

Installation
-----------------

    gem install sidekiq
    gem install sidekiq-delay_extensions

In your initializers, include the line:

    Sidekiq::DelayExtensions.enable_delay!

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
