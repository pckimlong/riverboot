import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverboot/riverboot.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Logging functionality', () {
    test('SplashConfig supports logging configuration', () {
      final logMessages = <String>[];
      
      final config = SplashConfig(
        splashBuilder: (_, __) => const SizedBox.shrink(),
        enableLogging: true,
        logger: (level, message, {error, stackTrace}) {
          logMessages.add('$level: $message');
        },
      );

      expect(config.enableLogging, isTrue);
      expect(config.logger, isNotNull);
    });

    test('one-time tasks log execution events', () async {
      final logMessages = <String>[];
      var taskExecuted = false;

      final container = ProviderContainer.test(
        overrides: [
          splashConfigProvider.overrideWithValue(
            SplashConfig(
              splashBuilder: (_, __) => const SizedBox.shrink(),
              enableLogging: true,
              logger: (level, message, {error, stackTrace}) {
                logMessages.add('$level: $message');
              },
              oneTimeTasks: [
                (ref) async {
                  await Future.delayed(const Duration(milliseconds: 10));
                  taskExecuted = true;
                },
              ],
            ),
          ),
        ],
      );

      await container.read(oneTimeSplashTasksProvider.future);

      expect(taskExecuted, isTrue);
      expect(logMessages, isNotEmpty);
      expect(logMessages.any((msg) => msg.contains('Starting 1 one-time tasks')), isTrue);
      expect(logMessages.any((msg) => msg.contains('Starting one-time task #0')), isTrue);
      expect(logMessages.any((msg) => msg.contains('One-time task #0 completed')), isTrue);
      expect(logMessages.any((msg) => msg.contains('All one-time tasks completed successfully')), isTrue);
    });

    test('reactive tasks log execution events', () async {
      final logMessages = <String>[];
      final stateProvider = StateProvider<int>((ref) => 42);
      var executeCallCount = 0;

      final container = ProviderContainer.test(
        overrides: [
          splashConfigProvider.overrideWithValue(
            SplashConfig(
              splashBuilder: (_, __) => const SizedBox.shrink(),
              enableLogging: true,
              logger: (level, message, {error, stackTrace}) {
                logMessages.add('$level: $message');
              },
              reactiveTasks: [
                task<int>(
                  watch: (ref) async => ref.watch(stateProvider),
                  execute: (ref, value) async {
                    executeCallCount++;
                  },
                  taskName: 'TestTask',
                ),
              ],
            ),
          ),
        ],
      );

      await container.read(reactiveSplashTasksExecuteProvider(0).future);

      expect(executeCallCount, equals(1));
      expect(logMessages, isNotEmpty);
      expect(logMessages.any((msg) => msg.contains('Starting watch phase for TestTask')), isTrue);
      expect(logMessages.any((msg) => msg.contains('TestTask watch completed')), isTrue);
      expect(logMessages.any((msg) => msg.contains('Starting execute phase for TestTask')), isTrue);
      expect(logMessages.any((msg) => msg.contains('TestTask execute completed')), isTrue);
    });

    test('task-level logging configuration overrides config-level', () async {
      final configLogMessages = <String>[];
      final taskLogMessages = <String>[];
      final stateProvider = StateProvider<int>((ref) => 42);

      final container = ProviderContainer.test(
        overrides: [
          splashConfigProvider.overrideWithValue(
            SplashConfig(
              splashBuilder: (_, __) => const SizedBox.shrink(),
              enableLogging: true,
              logger: (level, message, {error, stackTrace}) {
                configLogMessages.add('CONFIG: $message');
              },
              reactiveTasks: [
                task<int>(
                  watch: (ref) async => ref.watch(stateProvider),
                  execute: (ref, value) async {},
                  enableLogging: true,
                  logger: (level, message, {error, stackTrace}) {
                    taskLogMessages.add('TASK: $message');
                  },
                  taskName: 'CustomLoggerTask',
                ),
              ],
            ),
          ),
        ],
      );

      await container.read(reactiveSplashTasksExecuteProvider(0).future);

      expect(configLogMessages, isEmpty);
      expect(taskLogMessages, isNotEmpty);
      expect(taskLogMessages.any((msg) => msg.contains('CustomLoggerTask')), isTrue);
    });

    test('silentTask disables logging', () async {
      final logMessages = <String>[];
      final stateProvider = StateProvider<int>((ref) => 42);

      final container = ProviderContainer.test(
        overrides: [
          splashConfigProvider.overrideWithValue(
            SplashConfig(
              splashBuilder: (_, __) => const SizedBox.shrink(),
              enableLogging: true,
              logger: (level, message, {error, stackTrace}) {
                logMessages.add('$level: $message');
              },
              reactiveTasks: [
                silentTask<int>(
                  watch: (ref) async => ref.watch(stateProvider),
                  execute: (ref, value) async {},
                  taskName: 'SilentTask',
                ),
              ],
            ),
          ),
        ],
      );

      await container.read(reactiveSplashTasksExecuteProvider(0).future);

      expect(logMessages, isEmpty);
    });

    test('loggedTask enables logging even when config disables it', () async {
      final logMessages = <String>[];
      final stateProvider = StateProvider<int>((ref) => 42);

      final container = ProviderContainer.test(
        overrides: [
          splashConfigProvider.overrideWithValue(
            SplashConfig(
              splashBuilder: (_, __) => const SizedBox.shrink(),
              enableLogging: false,
              reactiveTasks: [
                loggedTask<int>(
                  watch: (ref) async => ref.watch(stateProvider),
                  execute: (ref, value) async {},
                  taskName: 'ForcedLoggedTask',
                  logger: (level, message, {error, stackTrace}) {
                    logMessages.add('$level: $message');
                  },
                ),
              ],
            ),
          ),
        ],
      );

      await container.read(reactiveSplashTasksExecuteProvider(0).future);

      expect(logMessages, isNotEmpty);
      expect(logMessages.any((msg) => msg.contains('ForcedLoggedTask')), isTrue);
    });

    test('error logging includes stack traces', () async {
      final logMessages = <Map<String, dynamic>>[];
      final stateProvider = StateProvider<int>((ref) => 42);

      final container = ProviderContainer.test(
        overrides: [
          splashConfigProvider.overrideWithValue(
            SplashConfig(
              splashBuilder: (_, __) => const SizedBox.shrink(),
              enableLogging: true,
              logger: (level, message, {error, stackTrace}) {
                logMessages.add({
                  'level': level,
                  'message': message,
                  'error': error,
                  'stackTrace': stackTrace,
                });
              },
              reactiveTasks: [
                task<int>(
                  watch: (ref) async => ref.watch(stateProvider),
                  execute: (ref, value) async {
                    throw Exception('Test error');
                  },
                  taskName: 'ErrorTask',
                ),
              ],
            ),
          ),
        ],
      );

      try {
        await container.read(reactiveSplashTasksExecuteProvider(0).future);
        fail('Expected exception to be thrown');
      } catch (e) {
        // Expected
      }

      final errorLogs = logMessages.where((log) => log['level'] == 'ERROR').toList();
      expect(errorLogs, isNotEmpty);
      expect(errorLogs.first['error'], isA<Exception>());
      expect(errorLogs.first['stackTrace'], isA<StackTrace>());
      expect(errorLogs.first['message'], contains('ErrorTask execute failed'));
    });
  });
}