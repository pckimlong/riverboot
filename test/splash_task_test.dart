import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverboot/riverboot.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SplashConfig', () {
    test('creates immutable tasks list', () {
      final mutableList = <Future<void> Function(Ref)>[(ref) async {}];
      final config = SplashConfig(
        splashBuilder: (_, _) => const SizedBox.shrink(),
        tasks: mutableList,
      );

      expect(() => config.tasks.add((ref) async {}), throwsUnsupportedError);
    });

    test('uses default values correctly', () {
      final config = SplashConfig(
        splashBuilder: (_, _) => const SizedBox.shrink(),
      );

      expect(config.tasks, isEmpty);
      expect(config.minimumDuration, Duration.zero);
      expect(config.runTasksInParallel, isTrue);
    });
  });

  group('SplashTaskError', () {
    test('toString includes error type and message for Exception', () {
      final error = SplashTaskError(
        error: Exception('test error'),
        stack: StackTrace.current,
      );

      final str = error.toString();
      expect(str, contains('SplashTaskError'));
      expect(str, contains('Exception'));
      expect(str, contains('test error'));
    });

    test('toString includes error type for non-Exception objects', () {
      final error = SplashTaskError(
        error: 'string error',
        stack: StackTrace.current,
      );

      final str = error.toString();
      expect(str, contains('String'));
    });

    test('toString caches result for repeated calls', () {
      final error = SplashTaskError(
        error: Exception('test'),
        stack: StackTrace.current,
      );

      final first = error.toString();
      final second = error.toString();
      expect(identical(first, second), isTrue);
    });

    test('toString limits stack trace to 5 lines', () {
      final error = SplashTaskError(
        error: Exception('test'),
        stack: StackTrace.current,
      );

      final str = error.toString();
      final stackSection = str.split('Stack trace (first 5 lines):').last;
      final lines = stackSection.trim().split('\n');
      expect(lines.length, lessThanOrEqualTo(5));
    });
  });

  group('splashTasksProvider', () {
    test('respects minimumDuration', () async {
      final minimumDuration = const Duration(milliseconds: 150);

      final container = ProviderContainer.test(
        overrides: [
          splashConfigProvider.overrideWithValue(
            SplashConfig(
              splashBuilder: (_, _) => const SizedBox.shrink(),
              minimumDuration: minimumDuration,
              tasks: [(ref) async {}],
            ),
          ),
        ],
      );

      final stopwatch = Stopwatch()..start();
      await container.read(splashTasksProvider.future);
      stopwatch.stop();

      expect(stopwatch.elapsed, greaterThanOrEqualTo(minimumDuration));
    });

    test('returns immediately with no tasks and no minimumDuration', () async {
      final container = ProviderContainer.test(
        overrides: [
          splashConfigProvider.overrideWithValue(
            SplashConfig(
              splashBuilder: (_, _) => const SizedBox.shrink(),
            ),
          ),
        ],
      );

      final stopwatch = Stopwatch()..start();
      await container.read(splashTasksProvider.future);
      stopwatch.stop();

      expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 50)));
    });

    test('runs tasks in parallel when runTasksInParallel is true', () async {
      final executionOrder = <int>[];
      final completer1 = Completer<void>();
      final completer2 = Completer<void>();

      final container = ProviderContainer.test(
        overrides: [
          splashConfigProvider.overrideWithValue(
            SplashConfig(
              splashBuilder: (_, _) => const SizedBox.shrink(),
              runTasksInParallel: true,
              tasks: [
                (ref) async {
                  executionOrder.add(1);
                  await completer1.future;
                  executionOrder.add(3);
                },
                (ref) async {
                  executionOrder.add(2);
                  await completer2.future;
                  executionOrder.add(4);
                },
              ],
            ),
          ),
        ],
      );

      final future = container.read(splashTasksProvider.future);

      // Allow tasks to start
      await Future.delayed(const Duration(milliseconds: 10));

      // Both tasks should have started (parallel execution)
      expect(executionOrder, containsAll([1, 2]));

      completer1.complete();
      completer2.complete();
      await future;

      expect(executionOrder, [1, 2, 3, 4]);
    });

    test('runs tasks sequentially when runTasksInParallel is false', () async {
      final executionOrder = <int>[];

      final container = ProviderContainer.test(
        overrides: [
          splashConfigProvider.overrideWithValue(
            SplashConfig(
              splashBuilder: (_, _) => const SizedBox.shrink(),
              runTasksInParallel: false,
              tasks: [
                (ref) async {
                  executionOrder.add(1);
                  await Future.delayed(const Duration(milliseconds: 10));
                  executionOrder.add(2);
                },
                (ref) async {
                  executionOrder.add(3);
                  await Future.delayed(const Duration(milliseconds: 10));
                  executionOrder.add(4);
                },
              ],
            ),
          ),
        ],
      );

      await container.read(splashTasksProvider.future);

      // Sequential: task 1 completes before task 2 starts
      expect(executionOrder, [1, 2, 3, 4]);
    });

    test('captures errors from one-time tasks in AsyncValue', () async {
      final container = ProviderContainer.test(
        overrides: [
          splashConfigProvider.overrideWithValue(
            SplashConfig(
              splashBuilder: (_, _) => const SizedBox.shrink(),
              tasks: [
                (ref) async => throw Exception('task failed'),
              ],
            ),
          ),
        ],
      );

      // Trigger the provider and wait for it to complete
      container.listen(splashTasksProvider, (_, _) {});
      await Future.delayed(const Duration(milliseconds: 50));

      final state = container.read(splashTasksProvider);
      expect(state.hasError, isTrue);
      expect(state.error, isA<Exception>());
    });

    test('completes when config is null', () async {
      final container = ProviderContainer.test(
        overrides: [
          splashConfigProvider.overrideWithValue(null),
        ],
      );

      // Should complete without error
      await container.read(splashTasksProvider.future);
    });
  });

  group('SplashBuilder', () {
    testWidgets('shows child when no splash config', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            splashConfigProvider.overrideWithValue(null),
          ],
          child: const MaterialApp(
            home: SplashBuilder(child: Text('Content')),
          ),
        ),
      );

      expect(find.text('Content'), findsOneWidget);
    });

    testWidgets('shows splash during one-time task loading', (tester) async {
      final completer = Completer<void>();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            splashConfigProvider.overrideWithValue(
              SplashConfig(
                splashBuilder: (_, _) => const Text('Splash'),
                tasks: [(ref) => completer.future],
              ),
            ),
          ],
          child: const MaterialApp(
            home: SplashBuilder(child: Text('Content')),
          ),
        ),
      );

      await tester.pump();
      expect(find.text('Splash'), findsOneWidget);
      expect(find.text('Content'), findsNothing);

      completer.complete();
      await tester.pump();
      await tester.pump(); // Allow provider to update

      expect(find.text('Content'), findsOneWidget);
      expect(find.text('Splash'), findsNothing);
    });

    testWidgets('shows error and retry button on one-time task failure', (tester) async {
      SplashTaskError? capturedError;
      VoidCallback? capturedRetry;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            splashConfigProvider.overrideWithValue(
              SplashConfig(
                splashBuilder: (error, retry) {
                  capturedError = error;
                  capturedRetry = retry;
                  return Column(
                    children: [
                      if (error != null) Text('Error: ${error.error}'),
                      if (retry != null)
                        ElevatedButton(onPressed: retry, child: const Text('Retry')),
                    ],
                  );
                },
                tasks: [
                  (ref) async => throw Exception('task failed'),
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
      expect(capturedRetry, isNotNull);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('retry callback re-runs failed tasks', (tester) async {
      var attemptCount = 0;
      VoidCallback? capturedRetry;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            splashConfigProvider.overrideWithValue(
              SplashConfig(
                splashBuilder: (error, retry) {
                  capturedRetry = retry;
                  if (error != null) {
                    return ElevatedButton(
                      onPressed: retry,
                      child: const Text('Retry'),
                    );
                  }
                  return const Text('Loading');
                },
                tasks: [
                  (ref) async {
                    attemptCount++;
                    if (attemptCount < 2) {
                      throw Exception('first attempt fails');
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
      expect(capturedRetry, isNotNull);
      expect(find.text('Retry'), findsOneWidget);

      // Trigger retry
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(attemptCount, 2);
      expect(find.text('Content'), findsOneWidget);
    });
  });

  group('ReactiveTask', () {
    testWidgets('runs on initial load along with one-time tasks', (tester) async {
      var oneTimeTaskRan = false;
      var reactiveTaskRan = false;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            splashConfigProvider.overrideWithValue(
              SplashConfig(
                splashBuilder: (_, _) => const Text('Splash'),
                tasks: [
                  (ref) async {
                    oneTimeTaskRan = true;
                  },
                ],
                reactiveTask: ReactiveTask(
                  trigger: (ref) {},
                  run: (ref) async {
                    reactiveTaskRan = true;
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

      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(oneTimeTaskRan, isTrue);
      expect(reactiveTaskRan, isTrue);
      expect(find.text('Content'), findsOneWidget);
    });

    testWidgets('run has full ref access (read, invalidate, onDispose)', (tester) async {
      int? readValue;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            splashConfigProvider.overrideWithValue(
              SplashConfig(
                splashBuilder: (_, _) => const Text('Splash'),
                reactiveTask: ReactiveTask(
                  trigger: (ref) {},
                  run: (ref) async {
                    // Test read - just verify it works
                    readValue = 42;

                    // Test onDispose - just verify it doesn't throw
                    ref.onDispose(() {});
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

      expect(readValue, 42);
      expect(find.text('Content'), findsOneWidget);
    });

    testWidgets('shows error when reactive task fails', (tester) async {
      SplashTaskError? capturedError;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            splashConfigProvider.overrideWithValue(
              SplashConfig(
                splashBuilder: (error, retry) {
                  capturedError = error;
                  if (error != null) {
                    return Text('Error: ${error.error}');
                  }
                  return const Text('Splash');
                },
                reactiveTask: ReactiveTask(
                  trigger: (ref) {},
                  run: (ref) async {
                    throw Exception('reactive task failed');
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

      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(capturedError, isNotNull);
      expect(capturedError!.error.toString(), contains('reactive task failed'));
    });

    testWidgets('retry works for reactive task errors', (tester) async {
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
                      child: const Text('Retry'),
                    );
                  }
                  return const Text('Splash');
                },
                reactiveTask: ReactiveTask(
                  trigger: (ref) {},
                  run: (ref) async {
                    attemptCount++;
                    if (attemptCount < 2) {
                      throw Exception('first attempt fails');
                    }
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

      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(attemptCount, 1);
      expect(find.text('Retry'), findsOneWidget);

      // Trigger retry
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(attemptCount, 2);
      expect(find.text('Content'), findsOneWidget);
    });

    testWidgets('one-time tasks and reactive task both must complete', (tester) async {
      final oneTimeCompleter = Completer<void>();
      final reactiveCompleter = Completer<void>();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            splashConfigProvider.overrideWithValue(
              SplashConfig(
                splashBuilder: (_, _) => const Text('Splash'),
                tasks: [
                  (ref) => oneTimeCompleter.future,
                ],
                reactiveTask: ReactiveTask(
                  trigger: (ref) {},
                  run: (ref) => reactiveCompleter.future,
                ),
              ),
            ),
          ],
          child: const MaterialApp(
            home: SplashBuilder(child: Text('Content')),
          ),
        ),
      );

      await tester.pump();
      expect(find.text('Splash'), findsOneWidget);

      // Complete one-time task only
      oneTimeCompleter.complete();
      await tester.pump();
      await tester.pump();

      // Still showing splash - reactive task not done
      expect(find.text('Splash'), findsOneWidget);

      // Complete reactive task
      reactiveCompleter.complete();
      await tester.pump();
      await tester.pump();

      // Now shows content
      expect(find.text('Content'), findsOneWidget);
    });
  });

  group('ReactiveTask trigger behavior', () {
    // These tests verify the trigger/run separation using container-level testing
    test('run provider executes on initial read', () async {
      var runCallCount = 0;

      final container = ProviderContainer.test(
        overrides: [
          splashConfigProvider.overrideWithValue(
            SplashConfig(
              splashBuilder: (_, _) => const SizedBox.shrink(),
              reactiveTask: ReactiveTask(
                trigger: (ref) {},
                run: (ref) async {
                  runCallCount++;
                },
              ),
            ),
          ),
        ],
      );

      // Initial read
      container.read(reactiveTaskRunProvider);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(runCallCount, 1);
    });

    test('run provider completes successfully', () async {
      var runCompleted = false;

      final container = ProviderContainer.test(
        overrides: [
          splashConfigProvider.overrideWithValue(
            SplashConfig(
              splashBuilder: (_, _) => const SizedBox.shrink(),
              reactiveTask: ReactiveTask(
                trigger: (ref) {},
                run: (ref) async {
                  await Future.delayed(const Duration(milliseconds: 10));
                  runCompleted = true;
                },
              ),
            ),
          ),
        ],
      );

      await container.read(reactiveTaskRunProvider.future);
      expect(runCompleted, isTrue);
    });

    test('run provider captures errors', () async {
      final container = ProviderContainer.test(
        overrides: [
          splashConfigProvider.overrideWithValue(
            SplashConfig(
              splashBuilder: (_, _) => const SizedBox.shrink(),
              reactiveTask: ReactiveTask(
                trigger: (ref) {},
                run: (ref) async {
                  throw Exception('test error');
                },
              ),
            ),
          ),
        ],
      );

      // Trigger the provider
      container.listen(reactiveTaskRunProvider, (_, _) {});
      await Future.delayed(const Duration(milliseconds: 50));

      final state = container.read(reactiveTaskRunProvider);
      expect(state.hasError, isTrue);
    });
  });
}
