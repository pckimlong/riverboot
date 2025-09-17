part of 'src.dart';

final _splashConfigProvider = Provider<SplashConfig?>(
  (ref) => throw UnimplementedError(),
);

final _loggingConfigProvider = Provider<RiverbootLoggingConfig>(
  (ref) => throw UnimplementedError(),
);

final _oneTimeSplashTasksProvider = FutureProvider<bool>((ref) async {
  final config = ref.watch(_splashConfigProvider);
  final globalLoggingConfig = ref.watch(_loggingConfigProvider);
  if (config == null) return true;

  // Use task-specific logging config if provided, otherwise use global config
  final loggingConfig = config.taskLoggingConfig ?? globalLoggingConfig;

  final stopwatch = Stopwatch()..start();
  final tasks = config.oneTimeTasks;

  if (tasks.isNotEmpty) {
    if (loggingConfig.logTaskStart) {
      loggingConfig._log('Starting ${tasks.length} one-time task(s) (parallel: ${config.runOneTimeTaskInParallel})');
    }

    if (config.runOneTimeTaskInParallel) {
      try {
        await Future.wait([
          for (int i = 0; i < tasks.length; i++)
            _executeOneTimeTask(tasks[i], i, ref, loggingConfig)
        ]);
      } catch (e, stack) {
        if (loggingConfig.logTaskErrors) {
          loggingConfig._log('One or more one-time tasks failed', error: e, stackTrace: stack);
        }
        rethrow;
      }
    } else {
      for (int i = 0; i < tasks.length; i++) {
        await _executeOneTimeTask(tasks[i], i, ref, loggingConfig);
      }
    }

    if (loggingConfig.logTaskCompletion) {
      loggingConfig._log('All one-time tasks completed successfully');
    }
  }

  stopwatch.stop();
  final remaining = config.minimumDuration - stopwatch.elapsed;
  if (remaining > Duration.zero) {
    if (loggingConfig.logTaskTiming) {
      loggingConfig._log('Waiting additional ${remaining.inMilliseconds}ms to meet minimum duration');
    }
    await Future.delayed(remaining);
  }

  if (loggingConfig.logTaskTiming) {
    loggingConfig._log('One-time tasks phase completed in ${stopwatch.elapsedMilliseconds}ms');
  }

  return true;
});

Future<void> _executeOneTimeTask(
  Future<void> Function(Ref ref) task,
  int taskIndex,
  Ref ref,
  RiverbootLoggingConfig loggingConfig,
) async {
  final stopwatch = Stopwatch();
  
  try {
    if (loggingConfig.logTaskStart) {
      loggingConfig._log('Starting one-time task $taskIndex');
    }
    
    if (loggingConfig.logTaskTiming) {
      stopwatch.start();
    }

    await task(ref);

    if (loggingConfig.logTaskTiming) {
      stopwatch.stop();
      loggingConfig._log('One-time task $taskIndex completed in ${stopwatch.elapsedMilliseconds}ms');
    } else if (loggingConfig.logTaskCompletion) {
      loggingConfig._log('One-time task $taskIndex completed');
    }
  } catch (e, stack) {
    if (loggingConfig.logTaskTiming && stopwatch.isRunning) {
      stopwatch.stop();
      loggingConfig._log('One-time task $taskIndex failed after ${stopwatch.elapsedMilliseconds}ms');
    }

    if (loggingConfig.logTaskErrors) {
      loggingConfig._log(
        'One-time task $taskIndex failed: ${e.runtimeType}: $e',
        error: e,
        stackTrace: stack,
      );
    }
    rethrow;
  }
}

final _reactiveSplashTasksProvider = FutureProvider.autoDispose
    .family<dynamic, int>((
      ref,
      index,
    ) async {
      final config = ref.watch(_splashConfigProvider);
      final globalLoggingConfig = ref.watch(_loggingConfigProvider);
      final tasks = config?.reactiveTasks;
      if (config == null || tasks == null || index >= tasks.length) return;

      // Use task-specific logging config if provided, otherwise use global config
      final loggingConfig = config.taskLoggingConfig ?? globalLoggingConfig;

      final task = tasks[index];
      final stopwatch = Stopwatch();

      try {
        if (loggingConfig.logTaskStart) {
          loggingConfig._log('Starting reactive task $index watch phase');
        }
        
        if (loggingConfig.logTaskTiming) {
          stopwatch.start();
        }

        final result = await task.watch(ref);

        if (loggingConfig.logTaskTiming) {
          stopwatch.stop();
          loggingConfig._log('Reactive task $index watch phase completed in ${stopwatch.elapsedMilliseconds}ms');
        } else if (loggingConfig.logTaskCompletion) {
          loggingConfig._log('Reactive task $index watch phase completed');
        }

        return result;
      } catch (e, stack) {
        if (loggingConfig.logTaskTiming && stopwatch.isRunning) {
          stopwatch.stop();
          loggingConfig._log('Reactive task $index watch phase failed after ${stopwatch.elapsedMilliseconds}ms');
        }

        if (loggingConfig.logTaskErrors) {
          loggingConfig._log(
            'Reactive task $index watch phase failed: ${e.runtimeType}: $e',
            error: e,
            stackTrace: stack,
          );
        }
        rethrow;
      }
    });

final _reactiveSplashTasksExecuteProvider = FutureProvider.autoDispose
    .family<void, int>((
      ref,
      index,
    ) async {
      final config = ref.watch(_splashConfigProvider);
      final globalLoggingConfig = ref.watch(_loggingConfigProvider);
      final tasks = config?.reactiveTasks;
      if (config == null || tasks == null || index >= tasks.length) return;

      // Use task-specific logging config if provided, otherwise use global config
      final loggingConfig = config.taskLoggingConfig ?? globalLoggingConfig;

      final data = await ref.watch(_reactiveSplashTasksProvider(index).future);
      final stopwatch = Stopwatch();

      try {
        if (loggingConfig.logTaskStart) {
          loggingConfig._log('Starting reactive task $index execute phase');
        }
        
        if (loggingConfig.logTaskTiming) {
          stopwatch.start();
        }

        await tasks[index].execute(ref, data);

        if (loggingConfig.logTaskTiming) {
          stopwatch.stop();
          loggingConfig._log('Reactive task $index execute phase completed in ${stopwatch.elapsedMilliseconds}ms');
        } else if (loggingConfig.logTaskCompletion) {
          loggingConfig._log('Reactive task $index execute phase completed');
        }
      } catch (e, stack) {
        if (loggingConfig.logTaskTiming && stopwatch.isRunning) {
          stopwatch.stop();
          loggingConfig._log('Reactive task $index execute phase failed after ${stopwatch.elapsedMilliseconds}ms');
        }

        if (loggingConfig.logTaskErrors) {
          loggingConfig._log(
            'Reactive task $index execute phase failed: ${e.runtimeType}: $e',
            error: e,
            stackTrace: stack,
          );
        }
        rethrow;
      }
    });

@visibleForTesting
Provider<SplashConfig?> get splashConfigProvider => _splashConfigProvider;

@visibleForTesting
Provider<RiverbootLoggingConfig> get loggingConfigProvider => _loggingConfigProvider;

@visibleForTesting
FutureProvider<bool> get oneTimeSplashTasksProvider =>
    _oneTimeSplashTasksProvider;

@visibleForTesting
FutureProvider<dynamic> Function(int) get reactiveSplashTasksProvider =>
    (index) => _reactiveSplashTasksProvider(index);

@visibleForTesting
FutureProvider<void> Function(int) get reactiveSplashTasksExecuteProvider =>
    (index) => _reactiveSplashTasksExecuteProvider(index);

class SplashConfig {
  /// The splash screen widget builder. For injecting splash widget
  final Widget Function(
    ({Object error, StackTrace stack})? error,
    VoidCallback? retry,
  )
  splashBuilder;

  final List<Future<void> Function(Ref ref)> oneTimeTasks;

  /// Whether to run the one-time tasks in parallel or sequentially. Default is `true`.
  /// If set to `true`, all tasks will be started at the same time, be cautious of using this
  /// if the tasks might be dependent on each other
  final bool runOneTimeTaskInParallel;

  /// The minimum duration to show the splash screen. Default is `Duration.zero`.
  final Duration minimumDuration;

  /// Reactive tasks are tasks that run when the watched data changes
  /// extend [ReactiveSplashTask] or use [task] function to create one
  /// Reactive tasks are run in parallel by default
  final List<ReactiveSplashTask> reactiveTasks;

  /// Optional logging configuration specific to splash tasks
  /// If not provided, uses the global logging configuration from Riverboot.initialize
  final RiverbootLoggingConfig? taskLoggingConfig;

  SplashConfig({
    required this.splashBuilder,
    List<Future<void> Function(Ref ref)> oneTimeTasks = const [],
    List<ReactiveSplashTask> reactiveTasks = const [],
    this.minimumDuration = Duration.zero,
    this.runOneTimeTaskInParallel = true,
    this.taskLoggingConfig,
  }) : oneTimeTasks = List.unmodifiable(oneTimeTasks),
       reactiveTasks = List.unmodifiable(reactiveTasks);
}

abstract class ReactiveSplashTask<T> {
  /// The data to watch, when this data changes, [execute] will be called
  /// The reason this exist is to prevent provider in execute function to trigger splash screen show when it change
  Future<T> watch(Ref ref);

  /// Run when the watched data changes
  Future<void> execute(Ref ref, T watchedData);
}

class _ClosureReactiveTask<T> extends ReactiveSplashTask<T> {
  final Future<T> Function(Ref ref) _watch;
  final Future<void> Function(Ref ref, T watchedData) _execute;
  _ClosureReactiveTask(this._watch, this._execute);

  @override
  Future<T> watch(Ref ref) => _watch(ref);

  @override
  Future<void> execute(Ref ref, T watchedData) => _execute(ref, watchedData);
}

ReactiveSplashTask<T> task<T>({
  required Future<T> Function(Ref ref) watch,
  required Future<void> Function(Ref ref, T watchedData) execute,
}) {
  return _ClosureReactiveTask(watch, execute);
}
