import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverboot/riverboot.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Riverboot.initialize', () {
    testWidgets('initializes app with no splash config shows child directly', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            splashConfigProvider.overrideWithValue(null),
          ],
          child: const MaterialApp(
            home: SplashBuilder(
              child: Text('App Content'),
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.text('App Content'), findsOneWidget);
    });

    testWidgets('respects splash config during initialization', (tester) async {
      final completer = Completer<void>();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            splashConfigProvider.overrideWithValue(
              SplashConfig(
                splashBuilder: (_, _) => const Text('Splash Screen'),
                tasks: [(ref) => completer.future],
              ),
            ),
          ],
          child: const MaterialApp(
            home: SplashBuilder(child: Text('App Content')),
          ),
        ),
      );

      await tester.pump();
      expect(find.text('Splash Screen'), findsOneWidget);
      expect(find.text('App Content'), findsNothing);

      completer.complete();
      await tester.pump();
      await tester.pump();

      expect(find.text('App Content'), findsOneWidget);
      expect(find.text('Splash Screen'), findsNothing);
    });

    testWidgets('applies provider overrides correctly', (tester) async {
      final testProvider = Provider<String>((ref) => 'default');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            testProvider.overrideWithValue('overridden'),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, child) {
                return Text(ref.watch(testProvider));
              },
            ),
          ),
        ),
      );

      await tester.pump();
      expect(find.text('overridden'), findsOneWidget);
    });
  });

  group('SplashBuilder edge cases', () {
    testWidgets('prioritizes one-time task errors over reactive task errors', (tester) async {
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
                tasks: [
                  (ref) async => throw Exception('one-time error'),
                ],
                reactiveTask: ReactiveTask(
                  trigger: (ref) {},
                  run: (ref) async => throw Exception('reactive error'),
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
      expect(capturedError!.error.toString(), contains('one-time error'));
    });

    testWidgets('shows reactive task error when one-time tasks succeed', (tester) async {
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
                tasks: [
                  (ref) async {}, // Succeeds
                ],
                reactiveTask: ReactiveTask(
                  trigger: (ref) {},
                  run: (ref) async => throw Exception('reactive error'),
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
      expect(capturedError!.error.toString(), contains('reactive error'));
    });

    testWidgets('handles empty tasks with reactive task only', (tester) async {
      var reactiveRan = false;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            splashConfigProvider.overrideWithValue(
              SplashConfig(
                splashBuilder: (_, _) => const Text('Splash'),
                reactiveTask: ReactiveTask(
                  trigger: (ref) {},
                  run: (ref) async {
                    reactiveRan = true;
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

      expect(reactiveRan, isTrue);
      expect(find.text('Content'), findsOneWidget);
    });

    testWidgets('shows content when both tasks and reactive task succeed', (tester) async {
      var oneTimeRan = false;
      var reactiveRan = false;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            splashConfigProvider.overrideWithValue(
              SplashConfig(
                splashBuilder: (_, _) => const Text('Splash'),
                tasks: [
                  (ref) async {
                    oneTimeRan = true;
                  },
                ],
                reactiveTask: ReactiveTask(
                  trigger: (ref) {},
                  run: (ref) async {
                    reactiveRan = true;
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

      expect(oneTimeRan, isTrue);
      expect(reactiveRan, isTrue);
      expect(find.text('Content'), findsOneWidget);
    });

    testWidgets('retry invalidates both one-time and reactive tasks', (tester) async {
      var oneTimeAttempts = 0;
      var reactiveAttempts = 0;

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
                tasks: [
                  (ref) async {
                    oneTimeAttempts++;
                    if (oneTimeAttempts < 2) {
                      throw Exception('one-time fails');
                    }
                  },
                ],
                reactiveTask: ReactiveTask(
                  trigger: (ref) {},
                  run: (ref) async {
                    reactiveAttempts++;
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

      expect(oneTimeAttempts, 1);
      expect(find.text('Retry'), findsOneWidget);

      // Tap retry
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(oneTimeAttempts, 2);
      // Reactive task also re-runs after retry
      expect(reactiveAttempts, greaterThanOrEqualTo(2));
      expect(find.text('Content'), findsOneWidget);
    });
  });

  group('SplashConfig validation', () {
    test('accepts empty tasks list by default', () {
      final config = SplashConfig(
        splashBuilder: (_, _) => const SizedBox.shrink(),
      );

      expect(config.tasks, isEmpty);
    });

    test('tasks list is unmodifiable', () {
      final config = SplashConfig(
        splashBuilder: (_, _) => const SizedBox.shrink(),
        tasks: [(ref) async {}],
      );

      expect(() => config.tasks.add((ref) async {}), throwsUnsupportedError);
    });

    test('runTasksInParallel defaults to true', () {
      final config = SplashConfig(
        splashBuilder: (_, _) => const SizedBox.shrink(),
      );

      expect(config.runTasksInParallel, isTrue);
    });

    test('minimumDuration defaults to Duration.zero', () {
      final config = SplashConfig(
        splashBuilder: (_, _) => const SizedBox.shrink(),
      );

      expect(config.minimumDuration, Duration.zero);
    });

    test('accepts custom splash builder with all parameters', () {
      final config = SplashConfig(
        splashBuilder: (error, retry) {
          return Column(
            children: [
              if (error != null) Text('Error: ${error.error}'),
              if (retry != null) ElevatedButton(onPressed: retry, child: const Text('Retry')),
            ],
          );
        },
        tasks: [(ref) async {}],
        reactiveTask: ReactiveTask(
          trigger: (ref) {},
          run: (ref) async {},
        ),
        minimumDuration: const Duration(seconds: 2),
        runTasksInParallel: false,
      );

      expect(config.tasks, hasLength(1));
      expect(config.reactiveTask, isNotNull);
      expect(config.minimumDuration, const Duration(seconds: 2));
      expect(config.runTasksInParallel, isFalse);
    });
  });

  group('SplashTaskError additional tests', () {
    test('handles Error objects correctly', () {
      final error = SplashTaskError(
        error: StateError('state error'),
        stack: StackTrace.current,
      );

      final str = error.toString();
      expect(str, contains('StateError'));
      expect(str, contains('state error'));
    });

    test('handles custom objects', () {
      final error = SplashTaskError(
        error: _CustomError(42),
        stack: StackTrace.current,
      );

      final str = error.toString();
      expect(str, contains('_CustomError'));
    });

    test('error and stack are accessible', () {
      final originalError = Exception('test');
      final originalStack = StackTrace.current;

      final error = SplashTaskError(
        error: originalError,
        stack: originalStack,
      );

      expect(error.error, same(originalError));
      expect(error.stack, same(originalStack));
    });
  });

  group('ReactiveTask configuration', () {
    test('holds trigger and run functions', () {
      void triggerFn(Ref ref) {}
      Future<void> runFn(Ref ref) async {}

      final task = ReactiveTask(
        trigger: triggerFn,
        run: runFn,
      );

      expect(task.trigger, same(triggerFn));
      expect(task.run, same(runFn));
    });

    test('can be created with const constructor', () {
      // This should compile without issues
      const task = ReactiveTask(
        trigger: _staticTrigger,
        run: _staticRun,
      );

      expect(task.trigger, isNotNull);
      expect(task.run, isNotNull);
    });
  });

  group('Provider behavior under stress', () {
    test('handles rapid successive task completions', () async {
      var completedTasks = 0;

      final container = ProviderContainer.test(
        overrides: [
          splashConfigProvider.overrideWithValue(
            SplashConfig(
              splashBuilder: (_, _) => const SizedBox.shrink(),
              runTasksInParallel: true,
              tasks: [
                for (var i = 0; i < 10; i++)
                  (ref) async {
                    await Future.delayed(Duration(milliseconds: (i + 1) * 5)); // Variable delays
                    completedTasks++;
                  },
              ],
            ),
          ),
        ],
      );

      await container.read(splashTasksProvider.future);
      expect(completedTasks, 10);
    });

    test('handles long-running tasks with minimum duration', () async {
      final minimumDuration = const Duration(milliseconds: 100);
      final taskDuration = const Duration(milliseconds: 200);

      final container = ProviderContainer.test(
        overrides: [
          splashConfigProvider.overrideWithValue(
            SplashConfig(
              splashBuilder: (_, _) => const SizedBox.shrink(),
              minimumDuration: minimumDuration,
              tasks: [
                (ref) async => await Future.delayed(taskDuration), // Task takes longer
              ],
            ),
          ),
        ],
      );

      final stopwatch = Stopwatch()..start();
      await container.read(splashTasksProvider.future);
      stopwatch.stop();

      // Should take at least the task duration (longer than minimum)
      expect(stopwatch.elapsed, greaterThanOrEqualTo(taskDuration));
    });

    test('sequential tasks maintain order under delays', () async {
      final executionOrder = <int>[];

      final container = ProviderContainer.test(
        overrides: [
          splashConfigProvider.overrideWithValue(
            SplashConfig(
              splashBuilder: (_, _) => const SizedBox.shrink(),
              runTasksInParallel: false,
              tasks: [
                (ref) async {
                  await Future.delayed(const Duration(milliseconds: 30));
                  executionOrder.add(1);
                },
                (ref) async {
                  await Future.delayed(const Duration(milliseconds: 10));
                  executionOrder.add(2);
                },
                (ref) async {
                  await Future.delayed(const Duration(milliseconds: 20));
                  executionOrder.add(3);
                },
              ],
            ),
          ),
        ],
      );

      await container.read(splashTasksProvider.future);
      expect(executionOrder, [1, 2, 3]);
    });

    test('parallel tasks can complete in any order', () async {
      final completionOrder = <int>[];

      final container = ProviderContainer.test(
        overrides: [
          splashConfigProvider.overrideWithValue(
            SplashConfig(
              splashBuilder: (_, _) => const SizedBox.shrink(),
              runTasksInParallel: true,
              tasks: [
                (ref) async {
                  await Future.delayed(const Duration(milliseconds: 30));
                  completionOrder.add(1);
                },
                (ref) async {
                  await Future.delayed(const Duration(milliseconds: 10));
                  completionOrder.add(2);
                },
                (ref) async {
                  await Future.delayed(const Duration(milliseconds: 20));
                  completionOrder.add(3);
                },
              ],
            ),
          ),
        ],
      );

      await container.read(splashTasksProvider.future);

      // All tasks completed
      expect(completionOrder.length, 3);
      // Order should be based on timing: 2 (10ms), 3 (20ms), 1 (30ms)
      expect(completionOrder, [2, 3, 1]);
    });
  });
}

// Helper class for testing custom error objects
class _CustomError {
  final int code;
  _CustomError(this.code);
}

// Static functions for const constructor test
void _staticTrigger(Ref ref) {}
Future<void> _staticRun(Ref ref) async {}
