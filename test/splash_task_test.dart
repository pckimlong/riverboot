import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverboot/riverboot.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('one-time tasks respect minimumDuration', () async {
    final minimumDuration = const Duration(milliseconds: 150);

    final container = ProviderContainer.test(
      overrides: [
        splashConfigProvider.overrideWithValue(
          SplashConfig(
            splashBuilder: (_, __) => const SizedBox.shrink(),
            minimumDuration: minimumDuration,
            oneTimeTasks: [
              (ref) async {},
            ],
          ),
        ),
      ],
    );

    final stopwatch = Stopwatch()..start();
    await container.read(oneTimeSplashTasksProvider.future);
    stopwatch.stop();

    expect(stopwatch.elapsed, greaterThanOrEqualTo(minimumDuration));
  });

  test(
    'reactive tasks can be invalidated without mutating configuration',
    () async {
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
    },
  );

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
}
