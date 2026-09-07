import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverboot/riverboot.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SplashTaskRef', () {
    testWidgets('watch reloads the owning task without showing splash', (
      tester,
    ) async {
      final dependency = NotifierProvider<_Counter, int>(_Counter.new);
      final secondRun = Completer<void>();
      var runs = 0;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            splashConfigProvider.overrideWithValue(
              SplashConfig(
                splashBuilder: (_, _) => const Text('Splash'),
                fadeTransition: false,
                tasks: [
                  (ref) async {
                    ref.watch(dependency);
                    runs++;
                    if (runs == 2) await secondRun.future;
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

      await tester.pumpAndSettle();
      expect(runs, 1);
      expect(find.text('Content'), findsOneWidget);

      final context = tester.element(find.text('Content'));
      ProviderScope.containerOf(context).read(dependency.notifier).increment();
      await tester.pump();

      expect(runs, 2);
      expect(find.text('Content'), findsOneWidget);
      expect(find.text('Splash'), findsNothing);

      secondRun.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('watchForSplash blocks while the owning task reloads', (
      tester,
    ) async {
      final dependency = NotifierProvider<_Counter, int>(_Counter.new);
      final secondRun = Completer<void>();
      var runs = 0;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            splashConfigProvider.overrideWithValue(
              SplashConfig(
                splashBuilder: (_, _) => const Text('Splash'),
                fadeTransition: false,
                tasks: [
                  (ref) async {
                    ref.watchForSplash(dependency);
                    runs++;
                    if (runs == 2) await secondRun.future;
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

      await tester.pumpAndSettle();
      expect(find.text('Content'), findsOneWidget);

      final context = tester.element(find.text('Content'));
      ProviderScope.containerOf(context).read(dependency.notifier).increment();
      await tester.pump();
      await tester.pump();

      expect(runs, 2);
      expect(find.text('Splash'), findsOneWidget);
      expect(find.text('Content'), findsNothing);

      secondRun.complete();
      await tester.pumpAndSettle();
      expect(find.text('Content'), findsOneWidget);
    });

    testWidgets('a normal watched reload error keeps content visible', (
      tester,
    ) async {
      final source = NotifierProvider<_Counter, int>(_Counter.new);
      var shouldFail = false;
      final dependency = FutureProvider<int>(
        (ref) async {
          ref.watch(source);
          if (shouldFail) throw Exception('runtime failure');
          return 42;
        },
        retry: (_, _) => null,
      );

      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [
            splashConfigProvider.overrideWithValue(
              SplashConfig(
                fadeTransition: false,
                splashBuilder: (error, retry) => error == null
                    ? const Text('Splash')
                    : ElevatedButton(
                        onPressed: retry,
                        child: const Text('Retry'),
                      ),
                tasks: [
                  (ref) async {
                    await ref.watch(dependency.future);
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

      await tester.pumpAndSettle();
      shouldFail = true;
      final context = tester.element(find.text('Content'));
      ProviderScope.containerOf(context).read(source.notifier).increment();
      await tester.pump();
      await tester.pump();

      expect(find.text('Content'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      expect(find.text('Splash'), findsNothing);
    });

    testWidgets('a watchForSplash reload error shows retry', (tester) async {
      final source = NotifierProvider<_Counter, int>(_Counter.new);
      var shouldFail = false;
      final dependency = FutureProvider<int>(
        (ref) async {
          ref.watch(source);
          if (shouldFail) throw Exception('blocking failure');
          return 42;
        },
        retry: (_, _) => null,
      );

      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [
            splashConfigProvider.overrideWithValue(
              SplashConfig(
                fadeTransition: false,
                splashBuilder: (error, retry) => error == null
                    ? const Text('Splash')
                    : ElevatedButton(
                        onPressed: retry,
                        child: const Text('Retry'),
                      ),
                tasks: [
                  (ref) async {
                    await ref.watchForSplash(dependency.future);
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

      await tester.pumpAndSettle();
      shouldFail = true;
      final context = tester.element(find.text('Content'));
      ProviderScope.containerOf(context).read(source.notifier).increment();
      await tester.pump();
      await tester.pump();

      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Content'), findsNothing);
    });

    test(
      'wait retains a provider without making it a task dependency',
      () async {
        final source = NotifierProvider<_Counter, int>(_Counter.new);
        var dependencyRuns = 0;
        var taskRuns = 0;
        final dependency = FutureProvider.autoDispose<int>((ref) async {
          dependencyRuns++;
          return ref.watch(source);
        });

        final container = ProviderContainer.test(
          overrides: [
            splashConfigProvider.overrideWithValue(
              SplashConfig(
                splashBuilder: (_, _) => const SizedBox.shrink(),
                tasks: [
                  (ref) async {
                    taskRuns++;
                    await ref.wait(dependency.future);
                  },
                ],
              ),
            ),
          ],
        );
        final subscription = container.listen(splashTasksProvider, (_, _) {});

        await container.read(splashTasksProvider.future);
        expect(taskRuns, 1);
        expect(dependencyRuns, 1);

        container.read(source.notifier).increment();
        await container.pump();
        await container.pump();

        expect(dependencyRuns, 2);
        expect(taskRuns, 1);
        subscription.close();
      },
    );

    test('retain initializes without awaiting or rerunning the task', () async {
      final source = NotifierProvider<_Counter, int>(_Counter.new);
      var dependencyRuns = 0;
      var taskRuns = 0;
      final dependency = Provider.autoDispose<int>((ref) {
        dependencyRuns++;
        return ref.watch(source);
      });

      final container = ProviderContainer.test(
        overrides: [
          splashConfigProvider.overrideWithValue(
            SplashConfig(
              splashBuilder: (_, _) => const SizedBox.shrink(),
              tasks: [
                (ref) async {
                  taskRuns++;
                  ref.retain(dependency);
                },
              ],
            ),
          ),
        ],
      );
      final subscription = container.listen(splashTasksProvider, (_, _) {});

      await container.read(splashTasksProvider.future);
      container.read(source.notifier).increment();
      await container.pump();

      expect(dependencyRuns, 2);
      expect(taskRuns, 1);
      subscription.close();
    });

    test('a watched dependency reruns only its owning task', () async {
      final dependency = NotifierProvider<_Counter, int>(_Counter.new);
      var watchedTaskRuns = 0;
      var unrelatedRuns = 0;

      final container = ProviderContainer.test(
        overrides: [
          splashConfigProvider.overrideWithValue(
            SplashConfig(
              splashBuilder: (_, _) => const SizedBox.shrink(),
              tasks: [
                (ref) async {
                  ref.watch(dependency);
                  watchedTaskRuns++;
                },
                (ref) async {
                  unrelatedRuns++;
                },
              ],
            ),
          ),
        ],
      );
      final subscription = container.listen(splashTasksProvider, (_, _) {});

      await container.read(splashTasksProvider.future);
      container.read(dependency.notifier).increment();
      await container.pump();
      await container.pump();

      expect(watchedTaskRuns, 2);
      expect(unrelatedRuns, 1);
      subscription.close();
    });

    for (final external in [false, true]) {
      for (final fails in [false, true]) {
        testWidgets(
          'obsolete ${external ? "external await" : "wait"} '
          '${fails ? "failure" : "success"} does not continue or show error',
          (tester) async {
            final source = NotifierProvider<_Counter, int>(_Counter.new);
            final pending = Completer<int>();
            final dependency = FutureProvider<int>(
              (ref) => pending.future,
              retry: (_, _) => null,
            );
            final applied = <int>[];
            final finished = <int>[];
            await tester.pumpWidget(
              ProviderScope(
                retry: (_, _) => null,
                overrides: [
                  splashConfigProvider.overrideWithValue(
                    SplashConfig(
                      fadeTransition: false,
                      splashBuilder: (error, _) =>
                          Text(error == null ? 'Splash' : 'Error'),
                      tasks: [
                        (ref) async {
                          final org = ref.watch(source);
                          try {
                            if (org == 0) {
                              if (external) {
                                try {
                                  await pending.future;
                                } finally {
                                  ref.ensureActive();
                                }
                              } else {
                                await ref.wait(dependency.future);
                              }
                            }
                            applied.add(org);
                          } finally {
                            finished.add(org);
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
            final container = ProviderScope.containerOf(
              tester.element(find.text('Splash')),
            );
            container.read(source.notifier).increment();
            await tester.pumpAndSettle();
            expect(applied, [1]);
            if (fails) {
              pending.completeError(StateError('obsolete failure'));
            } else {
              pending.complete(42);
            }
            await tester.pumpAndSettle();
            expect(applied, [1]);
            expect(finished, [1, 0]);
            expect(find.text('Content'), findsOneWidget);
            expect(find.text('Error'), findsNothing);
          },
        );
      }
    }

    for (final explicit in [false, true]) {
      testWidgets('retry refreshes failed waits (explicit: $explicit)', (
        tester,
      ) async {
        var successfulAttempts = 0;
        final successful = FutureProvider<int>(
          (ref) async => ++successfulAttempts,
        );
        var dependencyAttempts = 0;
        final dependency = FutureProvider<int>(
          (ref) async {
            dependencyAttempts++;
            if (dependencyAttempts == 1) throw Exception('first attempt');
            return 42;
          },
          retry: (_, _) => null,
        );

        await tester.pumpWidget(
          ProviderScope(
            retry: (_, _) => null,
            overrides: [
              splashConfigProvider.overrideWithValue(
                SplashConfig(
                  fadeTransition: false,
                  splashBuilder: (error, retry) => error == null
                      ? const Text('Splash')
                      : ElevatedButton(
                          onPressed: retry,
                          child: const Text('Retry'),
                        ),
                  tasks: [
                    (ref) async {
                      await ref.wait(successful.future);
                      if (explicit) ref.invalidateOnRetry(dependency);
                      await ref.wait(dependency.future);
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
        expect(find.text('Retry'), findsOneWidget);

        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();

        expect(successfulAttempts, 1);
        expect(dependencyAttempts, 2);
        expect(find.text('Content'), findsOneWidget);
      });
    }
  });
}

class _Counter extends Notifier<int> {
  @override
  int build() => 0;

  void increment() => state++;
}
