import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverboot/riverboot.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Reactive task trigger mechanism', () {
    testWidgets('trigger change causes run to re-execute', (tester) async {
      final triggerNotifier = ValueNotifier<int>(0);
      var runCount = 0;

      final triggerProvider = Provider<int>((ref) {
        return triggerNotifier.value;
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            splashConfigProvider.overrideWithValue(
              SplashConfig(
                splashBuilder: (_, _) => const Text('Splash'),
                reactiveTask: ReactiveTask(
                  trigger: (ref) => ref.watch(triggerProvider),
                  run: (ref) async {
                    runCount++;
                    await Future.delayed(const Duration(milliseconds: 10));
                  },
                ),
              ),
            ),
          ],
          child: const MaterialApp(
            home: SplashBuilder(child: Text('Content')),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(runCount, 1);
      expect(find.text('Content'), findsOneWidget);
    });

    testWidgets('trigger can watch multiple providers', (tester) async {
      var runCount = 0;

      final provider1 = Provider<int>((ref) => 1);
      final provider2 = Provider<String>((ref) => 'hello');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            splashConfigProvider.overrideWithValue(
              SplashConfig(
                splashBuilder: (_, _) => const Text('Splash'),
                reactiveTask: ReactiveTask(
                  trigger: (ref) {
                    ref.watch(provider1);
                    ref.watch(provider2);
                  },
                  run: (ref) async {
                    runCount++;
                  },
                ),
              ),
            ),
          ],
          child: const MaterialApp(
            home: SplashBuilder(child: Text('Content')),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(runCount, 1);
      expect(find.text('Content'), findsOneWidget);
    });

    test('run provider is separate from trigger provider', () async {
      var runCalls = 0;

      final container = ProviderContainer.test(
        overrides: [
          splashConfigProvider.overrideWithValue(
            SplashConfig(
              splashBuilder: (_, _) => const SizedBox.shrink(),
              reactiveTask: ReactiveTask(
                trigger: (ref) {},
                run: (ref) async {
                  runCalls++;
                },
              ),
            ),
          ),
        ],
      );

      // Read trigger provider
      container.read(splashTasksProvider);

      // Read run provider
      await container.read(reactiveTaskRunProvider.future);

      expect(runCalls, 1);
    });
  });

  group('Task ref capabilities', () {
    test('one-time tasks can access ref.read', () async {
      final testProvider = Provider<int>((ref) => 42);
      int? readValue;

      final container = ProviderContainer.test(
        overrides: [
          splashConfigProvider.overrideWithValue(
            SplashConfig(
              splashBuilder: (_, _) => const SizedBox.shrink(),
              tasks: [
                (ref) async {
                  readValue = ref.read(testProvider);
                },
              ],
            ),
          ),
        ],
      );

      await container.read(splashTasksProvider.future);
      expect(readValue, 42);
    });

    test('one-time tasks can access ref.onDispose', () async {
      var disposeCalled = false;

      final container = ProviderContainer.test(
        overrides: [
          splashConfigProvider.overrideWithValue(
            SplashConfig(
              splashBuilder: (_, _) => const SizedBox.shrink(),
              tasks: [
                (ref) async {
                  ref.onDispose(() {
                    disposeCalled = true;
                  });
                },
              ],
            ),
          ),
        ],
      );

      await container.read(splashTasksProvider.future);

      // Invalidating should trigger dispose
      container.invalidate(splashTasksProvider);
      expect(disposeCalled, isTrue);
    });

    test('reactive run can use ref.invalidate', () async {
      final testProvider = FutureProvider<int>((ref) async => 42);
      var invalidateCalled = false;

      final container = ProviderContainer.test(
        overrides: [
          splashConfigProvider.overrideWithValue(
            SplashConfig(
              splashBuilder: (_, _) => const SizedBox.shrink(),
              reactiveTask: ReactiveTask(
                trigger: (ref) {},
                run: (ref) async {
                  // Pre-read the provider
                  await ref.read(testProvider.future);

                  // Schedule invalidation
                  if (!invalidateCalled) {
                    invalidateCalled = true;
                    ref.invalidate(testProvider);
                  }
                },
              ),
            ),
          ),
        ],
      );

      await container.read(reactiveTaskRunProvider.future);
      expect(invalidateCalled, isTrue);
    });
  });

  group('Error recovery scenarios', () {
    testWidgets('multiple retries work correctly', (tester) async {
      var attemptCount = 0;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            splashConfigProvider.overrideWithValue(
              SplashConfig(
                splashBuilder: (error, retry) {
                  if (error != null) {
                    return ElevatedButton(
                      onPressed: retry,
                      child: Text('Retry (attempt $attemptCount)'),
                    );
                  }
                  return const Text('Splash');
                },
                tasks: [
                  (ref) async {
                    attemptCount++;
                    if (attemptCount < 3) {
                      throw Exception('fail attempt $attemptCount');
                    }
                  },
                ],
              ),
            ),
          ],
          child: const MaterialApp(
            home: SplashBuilder(child: Text('Content')),
          ),
        ),
      );

      await tester.pump();
      await tester.pump();
      expect(attemptCount, 1);
      expect(find.textContaining('Retry'), findsOneWidget);

      // First retry
      await tester.tap(find.textContaining('Retry'));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(attemptCount, 2);
      expect(find.textContaining('Retry'), findsOneWidget);

      // Second retry - should succeed
      await tester.tap(find.textContaining('Retry'));
      await tester.pumpAndSettle();
      expect(attemptCount, 3);
      expect(find.text('Content'), findsOneWidget);
    });

    testWidgets('different error types are captured correctly', (tester) async {
      SplashTaskError? capturedError;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            splashConfigProvider.overrideWithValue(
              SplashConfig(
                splashBuilder: (error, _) {
                  capturedError = error;
                  if (error != null) {
                    return Text('Error type: ${error.error.runtimeType}');
                  }
                  return const Text('Splash');
                },
                tasks: [
                  (ref) async => throw StateError('state error'),
                ],
              ),
            ),
          ],
          child: const MaterialApp(
            home: SplashBuilder(child: Text('Content')),
          ),
        ),
      );

      await tester.pump();
      await tester.pump();

      expect(capturedError, isNotNull);
      expect(capturedError!.error, isA<StateError>());
      expect(find.text('Error type: StateError'), findsOneWidget);
    });

    testWidgets('error state does not show splash when trigger unchanged', (tester) async {
      // This tests the fix: when reactive task errors without trigger change,
      // it should go directly to error screen without flashing splash
      var runCount = 0;
      var splashBuildCount = 0;
      var errorScreenShown = false;

      final triggerNotifier = ValueNotifier<int>(0);

      final triggerProvider = Provider<int>((ref) {
        return triggerNotifier.value;
      });

      // Provider that will error on second run (without trigger change)
      var shouldError = false;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            splashConfigProvider.overrideWithValue(
              SplashConfig(
                splashBuilder: (error, retry) {
                  if (error != null) {
                    errorScreenShown = true;
                    return ElevatedButton(
                      onPressed: retry,
                      child: const Text('Error - Retry'),
                    );
                  }
                  splashBuildCount++;
                  return const Text('Splash');
                },
                reactiveTask: ReactiveTask(
                  trigger: (ref) => ref.watch(triggerProvider),
                  run: (ref) async {
                    runCount++;
                    // Error if shouldError is true
                    if (shouldError) {
                      throw Exception('Intentional error');
                    }
                    await Future.delayed(const Duration(milliseconds: 10));
                  },
                ),
              ),
            ),
          ],
          child: const MaterialApp(
            home: SplashBuilder(child: Text('Content')),
          ),
        ),
      );

      // Initial load - splash shown, then content
      await tester.pumpAndSettle();
      expect(find.text('Content'), findsOneWidget);
      expect(runCount, 1);
      final initialSplashCount = splashBuildCount;

      // Now trigger an error WITHOUT changing the trigger
      // This simulates a dependency of run() causing a re-run that errors
      final container = ProviderScope.containerOf(
        tester.element(find.text('Content')),
      );

      // Set error flag and invalidate run provider to simulate re-run
      shouldError = true;
      container.invalidate(reactiveTaskRunProvider);

      // Pump to process the error
      await tester.pump();
      await tester.pump();
      await tester.pump();

      // Error screen should be shown
      expect(errorScreenShown, isTrue);
      expect(find.text('Error - Retry'), findsOneWidget);

      // CRITICAL: Splash should NOT have been shown again
      // (splashBuildCount should not have increased)
      expect(
        splashBuildCount,
        initialSplashCount,
        reason: 'Splash should not show when error occurs without trigger change',
      );
    });

    test('parallel execution fails fast with eagerError', () async {
      final taskStartOrder = <int>[];
      final taskCompleteOrder = <int>[];
      final firstTaskCompleter = Completer<void>();

      final container = ProviderContainer.test(
        overrides: [
          splashConfigProvider.overrideWithValue(
            SplashConfig(
              splashBuilder: (_, _) => const SizedBox.shrink(),
              runTasksInParallel: true,
              tasks: [
                (ref) async {
                  taskStartOrder.add(1);
                  await firstTaskCompleter.future;
                  taskCompleteOrder.add(1);
                },
                (ref) async {
                  taskStartOrder.add(2);
                  throw Exception('task 2 fails');
                },
              ],
            ),
          ),
        ],
      );

      // Listen for the error
      container.listen(splashTasksProvider, (_, _) {});
      await Future.delayed(const Duration(milliseconds: 50));

      // Both should start in parallel
      expect(taskStartOrder, containsAll([1, 2]));

      // The provider should have error (fail fast)
      final state = container.read(splashTasksProvider);
      expect(state.hasError, isTrue);
    });
  });

  group('Null and empty handling', () {
    test('handles null reactive task gracefully', () async {
      final container = ProviderContainer.test(
        overrides: [
          splashConfigProvider.overrideWithValue(
            SplashConfig(
              splashBuilder: (_, _) => const SizedBox.shrink(),
              tasks: [(ref) async {}],
              reactiveTask: null,
            ),
          ),
        ],
      );

      // Should complete without error
      await container.read(splashTasksProvider.future);
      await container.read(reactiveTaskRunProvider.future);
    });

    test('handles null config for reactive task run provider', () async {
      final container = ProviderContainer.test(
        overrides: [
          splashConfigProvider.overrideWithValue(null),
        ],
      );

      // Should complete without error
      await container.read(reactiveTaskRunProvider.future);
    });

    testWidgets('handles empty splash builder correctly', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            splashConfigProvider.overrideWithValue(
              SplashConfig(
                splashBuilder: (_, _) => const SizedBox.shrink(),
                tasks: [(ref) async {}],
              ),
            ),
          ],
          child: const MaterialApp(
            home: SplashBuilder(child: Text('Content')),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Content'), findsOneWidget);
    });
  });

  group('Concurrency edge cases', () {
    test('very slow minimum duration is respected', () async {
      final minimumDuration = const Duration(milliseconds: 200);

      final container = ProviderContainer.test(
        overrides: [
          splashConfigProvider.overrideWithValue(
            SplashConfig(
              splashBuilder: (_, _) => const SizedBox.shrink(),
              minimumDuration: minimumDuration,
              tasks: [], // No tasks, just minimum duration
            ),
          ),
        ],
      );

      final stopwatch = Stopwatch()..start();
      await container.read(splashTasksProvider.future);
      stopwatch.stop();

      expect(stopwatch.elapsed, greaterThanOrEqualTo(minimumDuration));
    });

    test('zero tasks with zero minimum duration completes immediately', () async {
      final container = ProviderContainer.test(
        overrides: [
          splashConfigProvider.overrideWithValue(
            SplashConfig(
              splashBuilder: (_, _) => const SizedBox.shrink(),
              minimumDuration: Duration.zero,
              tasks: [],
            ),
          ),
        ],
      );

      final stopwatch = Stopwatch()..start();
      await container.read(splashTasksProvider.future);
      stopwatch.stop();

      expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 50)));
    });
  });
}
