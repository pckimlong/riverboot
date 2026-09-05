import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverboot/riverboot.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SplashConfig', () {
    test('creates an immutable tasks list with expected defaults', () {
      final mutableTasks = <SplashTask>[(ref) async {}];
      final config = SplashConfig(
        splashBuilder: (_, _) => const SizedBox.shrink(),
        tasks: mutableTasks,
      );

      mutableTasks.clear();

      expect(config.tasks, hasLength(1));
      expect(() => config.tasks.add((ref) async {}), throwsUnsupportedError);
      expect(config.runTasksInParallel, isTrue);
      expect(config.minimumDuration, Duration.zero);
      expect(config.fadeTransition, isTrue);
    });
  });

  group('SplashTaskError', () {
    test('includes the error and limits the stack trace', () {
      final stack = StackTrace.fromString(
        List.generate(10, (index) => 'line $index').join('\n'),
      );
      final error = SplashTaskError(
        error: StateError('failed'),
        stack: stack,
      );

      final message = error.toString();

      expect(message, contains('StateError'));
      expect(message, contains('failed'));
      expect(message, contains('line 4'));
      expect(message, isNot(contains('line 5')));
      expect(error.toString(), same(message));
    });
  });

  group('splashTasksProvider', () {
    test('completes immediately for null config', () async {
      final container = ProviderContainer.test(
        overrides: [splashConfigProvider.overrideWithValue(null)],
      );

      await container.read(splashTasksProvider.future);
      expect(container.read(splashTasksProvider).hasValue, isTrue);
    });

    test('runs tasks in parallel', () async {
      final first = Completer<void>();
      final second = Completer<void>();
      final started = <int>[];
      final config = SplashConfig(
        splashBuilder: (_, _) => const SizedBox.shrink(),
        tasks: [
          (ref) async {
            started.add(1);
            await first.future;
          },
          (ref) async {
            started.add(2);
            await second.future;
          },
        ],
      );
      final container = ProviderContainer.test(
        overrides: [splashConfigProvider.overrideWithValue(config)],
      );

      final result = container.read(splashTasksProvider.future);
      await Future<void>.delayed(Duration.zero);
      expect(started, [1, 2]);

      first.complete();
      second.complete();
      await result;
    });

    test('runs tasks sequentially', () async {
      final first = Completer<void>();
      final started = <int>[];
      final config = SplashConfig(
        splashBuilder: (_, _) => const SizedBox.shrink(),
        runTasksInParallel: false,
        tasks: [
          (ref) async {
            started.add(1);
            await first.future;
          },
          (ref) async => started.add(2),
        ],
      );
      final container = ProviderContainer.test(
        overrides: [splashConfigProvider.overrideWithValue(config)],
      );

      final result = container.read(splashTasksProvider.future);
      await Future<void>.delayed(Duration.zero);
      expect(started, [1]);

      first.complete();
      await result;
      expect(started, [1, 2]);
    });

    test('respects minimum duration', () async {
      const minimumDuration = Duration(milliseconds: 80);
      final config = SplashConfig(
        splashBuilder: (_, _) => const SizedBox.shrink(),
        minimumDuration: minimumDuration,
      );
      final container = ProviderContainer.test(
        overrides: [splashConfigProvider.overrideWithValue(config)],
      );
      final stopwatch = Stopwatch()..start();

      await container.read(splashTasksProvider.future);

      expect(stopwatch.elapsed, greaterThanOrEqualTo(minimumDuration));
    });
  });

  group('SplashBuilder', () {
    testWidgets('shows splash until tasks complete', (tester) async {
      final task = Completer<void>();
      final config = SplashConfig(
        fadeTransition: false,
        splashBuilder: (_, _) => const Text('Splash'),
        tasks: [(ref) => task.future],
      );

      await tester.pumpWidget(_testApp(config));
      await tester.pump();

      expect(find.text('Splash'), findsOneWidget);
      expect(find.text('Content'), findsNothing);

      task.complete();
      await tester.pumpAndSettle();

      expect(find.text('Content'), findsOneWidget);
      expect(find.text('Splash'), findsNothing);
    });

    testWidgets('shows errors and retries failed tasks', (tester) async {
      var attempts = 0;
      final config = SplashConfig(
        fadeTransition: false,
        splashBuilder: (error, retry) => error == null
            ? const Text('Splash')
            : ElevatedButton(onPressed: retry, child: const Text('Retry')),
        tasks: [
          (ref) async {
            attempts++;
            if (attempts == 1) throw StateError('failed');
          },
        ],
      );

      await tester.pumpWidget(_testApp(config));
      await tester.pump();
      await tester.pump();

      expect(attempts, 1);
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(attempts, 2);
      expect(find.text('Content'), findsOneWidget);
    });
  });
}

Widget _testApp(SplashConfig config) {
  return ProviderScope(
    overrides: [splashConfigProvider.overrideWithValue(config)],
    child: const MaterialApp(
      home: SplashBuilder(child: Text('Content')),
    ),
  );
}
