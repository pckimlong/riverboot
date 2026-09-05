import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverboot/riverboot.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Riverboot.initialize', () {
    testWidgets('initializes app with no splash config shows child directly', (
      tester,
    ) async {
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
                fadeTransition: false,
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
              if (retry != null)
                ElevatedButton(onPressed: retry, child: const Text('Retry')),
            ],
          );
        },
        tasks: [(ref) async {}],
        minimumDuration: const Duration(seconds: 2),
        runTasksInParallel: false,
      );

      expect(config.tasks, hasLength(1));
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
                    await Future.delayed(
                      Duration(milliseconds: (i + 1) * 5),
                    ); // Variable delays
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
                (ref) async =>
                    await Future.delayed(taskDuration), // Task takes longer
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
      final c1 = Completer<void>();
      final c2 = Completer<void>();
      final c3 = Completer<void>();

      final container = ProviderContainer.test(
        overrides: [
          splashConfigProvider.overrideWithValue(
            SplashConfig(
              splashBuilder: (_, _) => const SizedBox.shrink(),
              runTasksInParallel: true,
              tasks: [
                (ref) async {
                  await c1.future;
                  completionOrder.add(1);
                },
                (ref) async {
                  await c2.future;
                  completionOrder.add(2);
                },
                (ref) async {
                  await c3.future;
                  completionOrder.add(3);
                },
              ],
            ),
          ),
        ],
      );

      final future = container.read(splashTasksProvider.future);

      // Complete in specific order: 2, 3, 1
      await Future.delayed(Duration.zero); // Allow tasks to start
      c2.complete();
      await Future.delayed(Duration.zero);
      c3.complete();
      await Future.delayed(Duration.zero);
      c1.complete();

      await future;

      // All tasks completed
      expect(completionOrder.length, 3);
      // Order should match completion order
      expect(completionOrder, [2, 3, 1]);
    });
  });
}

// Helper class for testing custom error objects
class _CustomError {
  final int code;
  _CustomError(this.code);
}
