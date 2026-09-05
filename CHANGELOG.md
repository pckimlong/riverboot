## Unreleased

* Add task-scoped provider policies through `SplashTaskRef`.
* Add `watchForSplash`, `watch`, `wait`, `retain`, and retry dependency
  registration for isolated startup tasks.
* Remove the legacy `ReactiveTask` trigger/run API.
* Add coverage based on Easy Inventory's bootstrap dependency graph.

## 0.0.1

* Initial release

## 0.0.2

* Major test suite expansion with comprehensive test coverage
* Performance optimizations in `splash_builder.dart` (Set → List conversion, counter optimizations)
* Performance optimizations in `splash_task.dart` (early return logic, stopwatch optimization)
* String caching in `SplashTaskError`
* Immutability guarantees for `SplashConfig` lists
* Dependency updates
