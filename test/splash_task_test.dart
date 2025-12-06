import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverboot/riverboot.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SplashConfig', () {
    test('creates immutable oneTimeTasks list', () {
      final mutableList = <Future<void> Function(Ref)>[(ref) async {}];
      final config = SplashConfig(
        splashBuilder: (_, __) => const SizedBox.shrink(),
        oneTimeTasks: mutableList,
      );

      expect(() => config.oneTimeTasks.add((ref) async {}), throwsUnsupportedError);
    });

    test('creates immutable reactiveTasks list', () {
      final mutableList = <ReactiveSplashTask>[
        task<int>(watch: (ref) async => 0, execute: (ref, _) async {}),
      ];
      final config = SplashConfig(
        splashBuilder: (_, __) => const SizedBox.shrink(),
        reactiveTasks: mutableList,
      );

      expect(
        () => config.reactiveTasks.add(
          task<int>(watch: (ref) async => 1, execute: (ref, _) async {}),
        ),
        throwsUnsupportedError,
      );
    });

    test('uses default values correctly', () {
      final config = SplashConfig(
        splashBuilder: (_, __) => const SizedBox.shrink(),
      );

      expect(config.oneTimeTasks, isEmpty);
      expect(config.reactiveTasks, isEmpty);
      expect(config.minimumDuration, Duration.zero);
      expect(config.runOneTimeTaskInParallel, isTrue);
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

  group('oneTimeSplashTasksProvider', () {
    test('respects minimumDuration', () async {
      final minimumDuration = const Duration(milliseconds: 150);

      final container = ProviderContainer.test(
        overrides: [
          splashConfigProvider.overrideWithValue(
            SplashConfig(
              splashBuilder: (_, __) => const SizedBox.shrink(),
              minimumDuration: minimumDuration,
              oneTimeTasks: [(ref) async {}],
            ),
          ),
        ],
      );

      final stopwatch = Stopwatch()..start();
      await container.read(oneTimeSplashTasksProvider.future);
      stopwatch.stop();

      expect(stopwatch.elapsed, greaterThanOrEqualTo(minimumDuration));
    });

    test('returns immediately with no tasks and no minimumDuration', () async {
      final container = ProviderContainer.test(
        overrides: [
          splashConfigProvider.overrideWithValue(
            SplashConfig(
              splashBuilder: (_, __) => const SizedBox.shrink(),
            ),
          ),
        ],
      );

      final stopwatch = Stopwatch()..start();
      await container.read(oneTimeSplashTasksProvider.future);
      stopwatch.stop();

      expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 50)));
    });

    test('runs tasks in parallel when runOneTimeTaskInParallel is true', () async {
      final executionOrder = <int>[];
      final completer1 = Completer<void>();
      final completer2 = Completer<void>();

      final container = ProviderContainer.test(
        overrides: [
          splashConfigProvider.overrideWithValue(
            SplashConfig(
              splashBuilder: (_, __) => const SizedBox.shrink(),
              runOneTimeTaskInParallel: true,
              oneTimeTasks: [
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

      final future = container.read(oneTimeSplashTasksProvider.future);

      // Allow tasks to start
      await Future.delayed(const Duration(milliseconds: 10));

      // Both tasks should have started (parallel execution)
      expect(executionOrder, containsAll([1, 2]));

      completer1.complete();
      completer2.complete();
      await future;

      expect(executionOrder, [1, 2, 3, 4]);
    });

    test('runs tasks sequentially when runOneTimeTaskInParallel is false', () async {
      final executionOrder = <int>[];

      final container = ProviderContainer.test(
        overrides: [
          splashConfigProvider.overrideWithValue(
            SplashConfig(
              splashBuilder: (_, __) => const SizedBox.shrink(),
              runOneTimeTaskInParallel: false,
              oneTimeTasks: [
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

      await container.read(oneTimeSplashTasksProvider.future);

      // Sequential: task 1 completes before task 2 starts
      expect(executionOrder, [1, 2, 3, 4]);
    });

    test('captures errors from one-time tasks in AsyncValue', () async {
      final container = ProviderContainer.test(
        overrides: [
          splashConfigProvider.overrideWithValue(
            SplashConfig(
              splashBuilder: (_, __) => const SizedBox.shrink(),
              oneTimeTasks: [
                (ref) async => throw Exception('task failed'),
              ],
            ),
          ),
        ],
      );

      // Trigger the provider and wait for it to complete
      container.listen(oneTimeSplashTasksProvider, (_, __) {});
      await Future.delayed(const Duration(milliseconds: 50));

      final state = container.read(oneTimeSplashTasksProvider);
      expect(state.hasError, isTrue);
      expect(state.error, isA<Exception>());
    });

    test('returns true when config is null', () async {
      final container = ProviderContainer.test(
        overrides: [
          splashConfigProvider.overrideWithValue(null),
        ],
      );

      final result = await container.read(oneTimeSplashTasksProvider.future);
      expect(result, isTrue);
    });
  });

  group('reactiveSplashTasksProvider', () {
    test('can be invalidated without mutating configuration', () async {
      final calls = <int>[];
      final stateProvider = StateProvider<int>((ref) => 0);

      final container = ProviderContainer.test(
        overrides: [
          splashConfigProvider.overrideWithValue(
            SplashConfig(
              splashBuilder: (_, __) => const SizedBox.shrink(),
              reactiveTasks: [
                task<int>(
                  watch: (ref) async => ref.watch(stateProvider),
                  execute: (ref, value) async {
                    calls.add(value);
                  },
                ),
              ],
            ),
          ),
        ],
      );

      await container.read(reactiveSplashTasksExecuteProvider(0).future);
      expect(calls, [0]);

      container.read(stateProvider.notifier).state = 1;
      container.invalidate(reactiveSplashTasksExecuteProvider(0));
      await container.read(reactiveSplashTasksExecuteProvider(0).future);

      expect(calls, [0, 1]);
    });

    test('returns null for out-of-bounds index', () async {
      final container = ProviderContainer.test(
        overrides: [
          splashConfigProvider.overrideWithValue(
            SplashConfig(
              splashBuilder: (_, __) => const SizedBox.shrink(),
              reactiveTasks: [
                task<int>(watch: (ref) async => 0, execute: (ref, _) async {}),
              ],
            ),
          ),
        ],
      );

      final result = await container.read(reactiveSplashTasksProvider(99).future);
      expect(result, isNull);
    });

    test('returns null when config is null', () async {
      final container = ProviderContainer.test(
        overrides: [
          splashConfigProvider.overrideWithValue(null),
        ],
      );

      final result = await container.read(reactiveSplashTasksProvider(0).future);
      expect(result, isNull);
    });

    test('passes watched data to execute function', () async {
      String? receivedData;

      final container = ProviderContainer.test(
        overrides: [
          splashConfigProvider.overrideWithValue(
            SplashConfig(
              splashBuilder: (_, __) => const SizedBox.shrink(),
              reactiveTasks: [
                task<String>(
                  watch: (ref) async => 'watched-value',
                  execute: (ref, data) async {
                    receivedData = data;
                  },
                ),
              ],
            ),
          ),
        ],
      );

      await container.read(reactiveSplashTasksExecuteProvider(0).future);
      expect(receivedData, 'watched-value');
    });

    test('handles multiple reactive tasks independently', () async {
      final task1Calls = <int>[];
      final task2Calls = <String>[];

      final container = ProviderContainer.test(
        overrides: [
          splashConfigProvider.overrideWithValue(
            SplashConfig(
              splashBuilder: (_, __) => const SizedBox.shrink(),
              reactiveTasks: [
                task<int>(
                  watch: (ref) async => 42,
                  execute: (ref, value) async => task1Calls.add(value),
                ),
                task<String>(
                  watch: (ref) async => 'hello',
                  execute: (ref, value) async => task2Calls.add(value),
                ),
              ],
            ),
          ),
        ],
      );

      await Future.wait([
        container.read(reactiveSplashTasksExecuteProvider(0).future),
        container.read(reactiveSplashTasksExecuteProvider(1).future),
      ]);

      expect(task1Calls, [42]);
      expect(task2Calls, ['hello']);
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
                splashBuilder: (_, __) => const Text('Splash'),
                oneTimeTasks: [(ref) => completer.future],
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
      await tester.pump();

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
                oneTimeTasks: [
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

    testWidgets('shows splash during reactive task loading', (tester) async {
      final completer = Completer<void>();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            splashConfigProvider.overrideWithValue(
              SplashConfig(
                splashBuilder: (_, __) => const Text('Splash'),
                reactiveTasks: [
                  task<int>(
                    watch: (ref) async => 1,
                    execute: (ref, _) => completer.future,
                  ),
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
      expect(find.text('Splash'), findsOneWidget);

      completer.complete();
      await tester.pump();
      await tester.pump();

      expect(find.text('Content'), findsOneWidget);
    });

    testWidgets(
      'splash shows when execute dependency changes without watch value change',
      (tester) async {
        final watchTriggerProvider = StateProvider<int>((ref) => 0);
        final executeDependencyProvider = StateProvider<int>((ref) => 0);

        final watchValues = <int>[];
        final executeDependencyValues = <int>[];
        final executeCompleters = <Completer<void>>[];

        late ProviderContainer container;

        final config = SplashConfig(
          splashBuilder: (_, __) => const Text('Splash'),
          reactiveTasks: [
            task<int>(
              watch: (ref) async {
                final value = ref.watch(watchTriggerProvider);
                watchValues.add(value);
                return value;
              },
              execute: (ref, watchedValue) async {
                final dependency = ref.watch(executeDependencyProvider);
                executeDependencyValues.add(dependency);

                final completer = Completer<void>();
                executeCompleters.add(completer);
                await completer.future;
              },
            ),
          ],
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              splashConfigProvider.overrideWithValue(config),
            ],
            child: MaterialApp(
              home: Builder(
                builder: (context) {
                  container = ProviderScope.containerOf(context, listen: false);
                  return const SplashBuilder(child: Text('Content'));
                },
              ),
            ),
          ),
        );

        await tester.pump();

        expect(find.text('Splash'), findsOneWidget);
        expect(executeCompleters, isNotEmpty);
        executeCompleters.removeAt(0).complete();

        await tester.pump();
        await tester.pump();

        expect(find.text('Content'), findsOneWidget);
        expect(find.text('Splash'), findsNothing);

        container.read(executeDependencyProvider.notifier).state = 1;

        await tester.pump();

        expect(executeCompleters, isNotEmpty);
        expect(find.text('Splash'), findsOneWidget);

        executeCompleters.removeAt(0).complete();

        await tester.pump();
        await tester.pump();

        expect(find.text('Content'), findsOneWidget);
        expect(find.text('Splash'), findsNothing);

        expect(watchValues.toSet(), {0});
        expect(executeDependencyValues, [0, 1]);
      },
    );

    testWidgets('handles multiple reactive tasks', (tester) async {
      final completer1 = Completer<void>();
      final completer2 = Completer<void>();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            splashConfigProvider.overrideWithValue(
              SplashConfig(
                splashBuilder: (_, __) => const Text('Splash'),
                reactiveTasks: [
                  task<int>(
                    watch: (ref) async => 1,
                    execute: (ref, _) => completer1.future,
                  ),
                  task<int>(
                    watch: (ref) async => 2,
                    execute: (ref, _) => completer2.future,
                  ),
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
      expect(find.text('Splash'), findsOneWidget);

      // Complete first task - should still show splash
      completer1.complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('Splash'), findsOneWidget);

      // Complete second task - should show content
      completer2.complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('Content'), findsOneWidget);
    });

    testWidgets('shows error from reactive task watch', (tester) async {
      SplashTaskError? capturedError;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            splashConfigProvider.overrideWithValue(
              SplashConfig(
                splashBuilder: (error, retry) {
                  capturedError = error;
                  return Text(error != null ? 'Error' : 'Loading');
                },
                reactiveTasks: [
                  task<int>(
                    watch: (ref) async => throw Exception('watch failed'),
                    execute: (ref, _) async {},
                  ),
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
      expect(find.text('Error'), findsOneWidget);
    });

    testWidgets('shows error from reactive task execute', (tester) async {
      SplashTaskError? capturedError;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            splashConfigProvider.overrideWithValue(
              SplashConfig(
                splashBuilder: (error, retry) {
                  capturedError = error;
                  return Text(error != null ? 'Error' : 'Loading');
                },
                reactiveTasks: [
                  task<int>(
                    watch: (ref) async => 1,
                    execute: (ref, _) async => throw Exception('execute failed'),
                  ),
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
      expect(find.text('Error'), findsOneWidget);
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
                oneTimeTasks: [
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

    testWidgets('works with no reactive tasks', (tester) async {
      final completer = Completer<void>();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            splashConfigProvider.overrideWithValue(
              SplashConfig(
                splashBuilder: (_, __) => const Text('Splash'),
                oneTimeTasks: [(ref) => completer.future],
                reactiveTasks: [],
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

      completer.complete();
      await tester.pump();
      await tester.pump();

      expect(find.text('Content'), findsOneWidget);
    });
  });

  group('task() helper', () {
    test('creates ReactiveSplashTask with correct watch and execute', () async {
      var watchCalled = false;
      var executeCalled = false;
      String? executedWith;

      final reactiveTask = task<String>(
        watch: (ref) async {
          watchCalled = true;
          return 'test-data';
        },
        execute: (ref, data) async {
          executeCalled = true;
          executedWith = data;
        },
      );

      final container = ProviderContainer.test(
        overrides: [
          splashConfigProvider.overrideWithValue(
            SplashConfig(
              splashBuilder: (_, __) => const SizedBox.shrink(),
              reactiveTasks: [reactiveTask],
            ),
          ),
        ],
      );

      await container.read(reactiveSplashTasksExecuteProvider(0).future);

      expect(watchCalled, isTrue);
      expect(executeCalled, isTrue);
      expect(executedWith, 'test-data');
    });
  });
}
