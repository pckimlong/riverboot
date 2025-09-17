import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverboot/riverboot.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RiverbootLoggingConfig', () {
    test('default config has minimal logging enabled', () {
      const config = RiverbootLoggingConfig();
      expect(config.logTaskStart, false);
      expect(config.logTaskCompletion, false);
      expect(config.logTaskErrors, true);
      expect(config.logTaskTiming, false);
      expect(config.customLogger, null);
    });

    test('enhanced config has all logging enabled', () {
      const config = RiverbootLoggingConfig.enhanced;
      expect(config.logTaskStart, true);
      expect(config.logTaskCompletion, true);
      expect(config.logTaskErrors, true);
      expect(config.logTaskTiming, true);
    });

    test('none config has no logging enabled', () {
      const config = RiverbootLoggingConfig.none;
      expect(config.logTaskStart, false);
      expect(config.logTaskCompletion, false);
      expect(config.logTaskErrors, false);
      expect(config.logTaskTiming, false);
    });

    test('custom logger is called when provided', () {
      final logMessages = <String>[];
      final config = RiverbootLoggingConfig(
        customLogger: (message, {error, stackTrace}) {
          logMessages.add(message);
        },
      );

      config._log('Test message');
      expect(logMessages, contains('Test message'));
    });
  });

  group('SplashConfig with logging', () {
    test('can specify task logging config', () {
      final config = SplashConfig(
        splashBuilder: (_, __) => const SizedBox.shrink(),
        taskLoggingConfig: RiverbootLoggingConfig.enhanced,
      );

      expect(config.taskLoggingConfig, RiverbootLoggingConfig.enhanced);
    });

    test('task logging config is optional', () {
      final config = SplashConfig(
        splashBuilder: (_, __) => const SizedBox.shrink(),
      );

      expect(config.taskLoggingConfig, null);
    });
  });

  group('Logging in task execution', () {
    test('logs one-time task execution with enhanced config', () async {
      final logMessages = <String>[];
      final loggingConfig = RiverbootLoggingConfig(
        logTaskStart: true,
        logTaskCompletion: true,
        logTaskTiming: true,
        customLogger: (message, {error, stackTrace}) {
          logMessages.add(message);
        },
      );

      final container = ProviderContainer.test(
        overrides: [
          splashConfigProvider.overrideWithValue(
            SplashConfig(
              splashBuilder: (_, __) => const SizedBox.shrink(),
              oneTimeTasks: [
                (ref) async {
                  await Future.delayed(const Duration(milliseconds: 10));
                },
              ],
            ),
          ),
          loggingConfigProvider.overrideWithValue(loggingConfig),
        ],
      );

      await container.read(oneTimeSplashTasksProvider.future);

      expect(logMessages.any((msg) => msg.contains('Starting 1 one-time task')), true);
      expect(logMessages.any((msg) => msg.contains('Starting one-time task 0')), true);
      expect(logMessages.any((msg) => msg.contains('One-time task 0 completed')), true);
      expect(logMessages.any((msg) => msg.contains('All one-time tasks completed')), true);
      expect(logMessages.any((msg) => msg.contains('tasks phase completed')), true);
    });

    test('logs task errors with enhanced config', () async {
      final logMessages = <String>[];
      final loggingConfig = RiverbootLoggingConfig(
        logTaskErrors: true,
        customLogger: (message, {error, stackTrace}) {
          logMessages.add(message);
        },
      );

      final container = ProviderContainer.test(
        overrides: [
          splashConfigProvider.overrideWithValue(
            SplashConfig(
              splashBuilder: (_, __) => const SizedBox.shrink(),
              oneTimeTasks: [
                (ref) async {
                  throw Exception('Test error');
                },
              ],
            ),
          ),
          loggingConfigProvider.overrideWithValue(loggingConfig),
        ],
      );

      try {
        await container.read(oneTimeSplashTasksProvider.future);
        fail('Expected exception');
      } catch (e) {
        expect(logMessages.any((msg) => msg.contains('One-time task 0 failed')), true);
        expect(logMessages.any((msg) => msg.contains('Test error')), true);
      }
    });

    test('reactive tasks use proper logging config', () async {
      final logMessages = <String>[];
      final loggingConfig = RiverbootLoggingConfig(
        logTaskStart: true,
        logTaskCompletion: true,
        customLogger: (message, {error, stackTrace}) {
          logMessages.add(message);
        },
      );

      final container = ProviderContainer.test(
        overrides: [
          splashConfigProvider.overrideWithValue(
            SplashConfig(
              splashBuilder: (_, __) => const SizedBox.shrink(),
              reactiveTasks: [
                task<int>(
                  watch: (ref) async => 42,
                  execute: (ref, value) async {
                    // Do something with value
                  },
                ),
              ],
            ),
          ),
          loggingConfigProvider.overrideWithValue(loggingConfig),
        ],
      );

      await container.read(reactiveSplashTasksProvider(0).future);
      await container.read(reactiveSplashTasksExecuteProvider(0).future);

      expect(logMessages.any((msg) => msg.contains('Starting reactive task 0 watch')), true);
      expect(logMessages.any((msg) => msg.contains('reactive task 0 watch phase completed')), true);
      expect(logMessages.any((msg) => msg.contains('Starting reactive task 0 execute')), true);
      expect(logMessages.any((msg) => msg.contains('reactive task 0 execute phase completed')), true);
    });

    test('splash config logging overrides global logging', () async {
      final globalLogs = <String>[];
      final taskLogs = <String>[];
      
      final globalLoggingConfig = RiverbootLoggingConfig(
        logTaskStart: false,
        customLogger: (message, {error, stackTrace}) {
          globalLogs.add(message);
        },
      );

      final taskLoggingConfig = RiverbootLoggingConfig(
        logTaskStart: true,
        customLogger: (message, {error, stackTrace}) {
          taskLogs.add(message);
        },
      );

      final container = ProviderContainer.test(
        overrides: [
          splashConfigProvider.overrideWithValue(
            SplashConfig(
              splashBuilder: (_, __) => const SizedBox.shrink(),
              oneTimeTasks: [
                (ref) async {},
              ],
              taskLoggingConfig: taskLoggingConfig,
            ),
          ),
          loggingConfigProvider.overrideWithValue(globalLoggingConfig),
        ],
      );

      await container.read(oneTimeSplashTasksProvider.future);

      // Task-specific logs should be used, not global logs
      expect(globalLogs, isEmpty);
      expect(taskLogs.any((msg) => msg.contains('Starting 1 one-time task')), true);
    });
  });
}