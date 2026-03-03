## Unreleased

* Fix `SplashBuilder` so reactive errors only take over when they block bootstrap:
  * initial reactive run failure (no previous value), or
  * trigger-caused reactive refresh failure.
* Non-trigger runtime reactive failures after successful bootstrap no longer replace app content with splash error UI.
* Add tests for reactive error visibility rules.

## 0.0.1

* Initial release

## 0.0.2

* Major test suite expansion with comprehensive test coverage
* Performance optimizations in `splash_builder.dart` (Set → List conversion, counter optimizations)
* Performance optimizations in `splash_task.dart` (early return logic, stopwatch optimization)
* String caching in `SplashTaskError`
* Immutability guarantees for `SplashConfig` lists
* Dependency updates
