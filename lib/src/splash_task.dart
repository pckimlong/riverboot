part of 'src.dart';

/// Helper function to log messages based on configuration
void _logTaskEvent(
  SplashConfig? config,
  String level, 
  String message, {
  Object? error,
  StackTrace? stackTrace,
  ReactiveSplashTask? task,
}) {
  // Check if logging is enabled at config level
  final configLoggingEnabled = config?.enableLogging ?? true;
  
  // Check if logging is enabled at task level (overrides config)
  final taskLoggingEnabled = task?.enableLogging ?? configLoggingEnabled;
  
  if (!taskLoggingEnabled) return;

  // Use task-specific logger if available, otherwise use config logger, otherwise use default
  final logger = task?.logger ?? config?.logger;
  
  if (logger != null) {
    logger(level, message, error: error, stackTrace: stackTrace);
  } else {
    // Default logging using dart:developer
    log(message, level: 0, name: 'Riverboot', error: error, stackTrace: stackTrace);
  }
}

final _splashConfigProvider = Provider<SplashConfig?>(
  (ref) => throw UnimplementedError(),
);

final _oneTimeSplashTasksProvider = FutureProvider<bool>((ref) async {
  final config = ref.watch(_splashConfigProvider);
  if (config == null) return true;

  final stopwatch = Stopwatch()..start();
  final tasks = config.oneTimeTasks;

  _logTaskEvent(config, 'INFO', 'Starting ${tasks.length} one-time tasks (parallel: ${config.runOneTimeTaskInParallel})');

  if (tasks.isNotEmpty) {
    try {
      if (config.runOneTimeTaskInParallel) {
        _logTaskEvent(config, 'INFO', 'Executing one-time tasks in parallel');
        await Future.wait([
          for (int i = 0; i < tasks.length; i++)
            _executeOneTimeTask(tasks[i], i, config, ref)
        ]);
      } else {
        _logTaskEvent(config, 'INFO', 'Executing one-time tasks sequentially');
        for (int i = 0; i < tasks.length; i++) {
          await _executeOneTimeTask(tasks[i], i, config, ref);
        }
      }
      _logTaskEvent(config, 'INFO', 'All one-time tasks completed successfully');
    } catch (e, stackTrace) {
      _logTaskEvent(config, 'ERROR', 'One-time task execution failed', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  stopwatch.stop();
  final elapsed = stopwatch.elapsed;
  _logTaskEvent(config, 'INFO', 'One-time tasks completed in ${elapsed.inMilliseconds}ms');
  
  final remaining = config.minimumDuration - elapsed;
  if (remaining > Duration.zero) {
    _logTaskEvent(config, 'INFO', 'Waiting additional ${remaining.inMilliseconds}ms for minimum duration');
    await Future.delayed(remaining);
  }

  return true;
});

/// Helper to execute and log individual one-time tasks
Future<void> _executeOneTimeTask(
  Future<void> Function(Ref ref) task,
  int index,
  SplashConfig config,
  Ref ref,
) async {
  final stopwatch = Stopwatch()..start();
  _logTaskEvent(config, 'INFO', 'Starting one-time task #$index');
  
  try {
    await task(ref);
    stopwatch.stop();
    _logTaskEvent(config, 'INFO', 'One-time task #$index completed in ${stopwatch.elapsedMilliseconds}ms');
  } catch (e, stackTrace) {
    stopwatch.stop();
    _logTaskEvent(config, 'ERROR', 'One-time task #$index failed after ${stopwatch.elapsedMilliseconds}ms', error: e, stackTrace: stackTrace);
    rethrow;
  }
}

final _reactiveSplashTasksProvider = FutureProvider.autoDispose
    .family<dynamic, int>((
      ref,
      index,
    ) async {
      final config = ref.watch(_splashConfigProvider);
      final tasks = config?.reactiveTasks;
      if (config == null || tasks == null || index >= tasks.length) return;

      final task = tasks[index];
      final taskName = task.taskName ?? 'ReactiveTask#$index';
      
      _logTaskEvent(config, 'INFO', 'Starting watch phase for $taskName', task: task);
      final stopwatch = Stopwatch()..start();
      
      try {
        final result = await task.watch(ref);
        stopwatch.stop();
        _logTaskEvent(config, 'INFO', '$taskName watch completed in ${stopwatch.elapsedMilliseconds}ms', task: task);
        return result;
      } catch (e, stackTrace) {
        stopwatch.stop();
        _logTaskEvent(config, 'ERROR', '$taskName watch failed after ${stopwatch.elapsedMilliseconds}ms', error: e, stackTrace: stackTrace, task: task);
        rethrow;
      }
    });

final _reactiveSplashTasksExecuteProvider = FutureProvider.autoDispose
    .family<void, int>((
      ref,
      index,
    ) async {
      final config = ref.watch(_splashConfigProvider);
      final tasks = config?.reactiveTasks;
      if (config == null || tasks == null || index >= tasks.length) return;

      final task = tasks[index];
      final taskName = task.taskName ?? 'ReactiveTask#$index';
      
      final data = await ref.watch(_reactiveSplashTasksProvider(index).future);
      
      _logTaskEvent(config, 'INFO', 'Starting execute phase for $taskName', task: task);
      final stopwatch = Stopwatch()..start();
      
      try {
        await task.execute(ref, data);
        stopwatch.stop();
        _logTaskEvent(config, 'INFO', '$taskName execute completed in ${stopwatch.elapsedMilliseconds}ms', task: task);
      } catch (e, stackTrace) {
        stopwatch.stop();
        _logTaskEvent(config, 'ERROR', '$taskName execute failed after ${stopwatch.elapsedMilliseconds}ms', error: e, stackTrace: stackTrace, task: task);
        rethrow;
      }
    });

@visibleForTesting
Provider<SplashConfig?> get splashConfigProvider => _splashConfigProvider;

@visibleForTesting
FutureProvider<bool> get oneTimeSplashTasksProvider =>
    _oneTimeSplashTasksProvider;

@visibleForTesting
FutureProvider<dynamic> Function(int) get reactiveSplashTasksProvider =>
    (index) => _reactiveSplashTasksProvider(index);

@visibleForTesting
FutureProvider<void> Function(int) get reactiveSplashTasksExecuteProvider =>
    (index) => _reactiveSplashTasksExecuteProvider(index);

class SplashTaskError implements Exception {
  final Object error;
  final StackTrace stack;

  SplashTaskError({required this.error, required this.stack});

  @override
  String toString() {
    final buffer = StringBuffer('SplashTaskError');
    // Only include error, and avoid exposing sensitive info
    buffer.write(': ');
    // Only print the type and message, not the full object if possible
    buffer.write(error.runtimeType);
    if (error is Exception || error is Error) {
      buffer.write(': ${error.toString()}');
    }
    // Only include stack trace, and only the first few lines
    final stackStr = stack.toString().split('\n').take(5).join('\n');
    buffer.write('\nStack trace (first 5 lines):\n$stackStr');
    return buffer.toString();
  }
}

class SplashConfig {
  /// The splash screen widget builder. For injecting splash widget
  final Widget Function(SplashTaskError? error, VoidCallback? retry)
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

  /// Enable logging for task execution. Default is `true`.
  /// When enabled, logs task start, completion, and error events.
  final bool enableLogging;

  /// Custom logger function. If not provided, uses dart:developer log.
  /// Receives level, message, and optional error/stackTrace parameters.
  final void Function(String level, String message, {Object? error, StackTrace? stackTrace})? logger;

  SplashConfig({
    required this.splashBuilder,
    List<Future<void> Function(Ref ref)> oneTimeTasks = const [],
    List<ReactiveSplashTask> reactiveTasks = const [],
    this.minimumDuration = Duration.zero,
    this.runOneTimeTaskInParallel = true,
    this.enableLogging = true,
    this.logger,
  }) : oneTimeTasks = List.unmodifiable(oneTimeTasks),
       reactiveTasks = List.unmodifiable(reactiveTasks);
}

abstract class ReactiveSplashTask<T> {
  /// The data to watch, when this data changes, [execute] will be called
  /// The reason this exist is to prevent provider in execute function to trigger splash screen show when it change
  Future<T> watch(Ref ref);

  /// Run when the watched data changes
  Future<void> execute(Ref ref, T watchedData);

  /// Enable logging for this specific task. If null, uses SplashConfig.enableLogging.
  bool? get enableLogging => null;

  /// Custom logger for this specific task. If null, uses SplashConfig.logger.
  void Function(String level, String message, {Object? error, StackTrace? stackTrace})? get logger => null;

  /// Optional name for this task used in logging. If null, uses task type name.
  String? get taskName => null;
}

class _ClosureReactiveTask<T> extends ReactiveSplashTask<T> {
  final Future<T> Function(Ref ref) _watch;
  final Future<void> Function(Ref ref, T watchedData) _execute;
  final bool? _enableLogging;
  final void Function(String level, String message, {Object? error, StackTrace? stackTrace})? _logger;
  final String? _taskName;

  _ClosureReactiveTask(
    this._watch, 
    this._execute, {
    bool? enableLogging,
    void Function(String level, String message, {Object? error, StackTrace? stackTrace})? logger,
    String? taskName,
  }) : _enableLogging = enableLogging,
       _logger = logger,
       _taskName = taskName;

  @override
  Future<T> watch(Ref ref) => _watch(ref);

  @override
  Future<void> execute(Ref ref, T watchedData) => _execute(ref, watchedData);

  @override
  bool? get enableLogging => _enableLogging;

  @override
  void Function(String level, String message, {Object? error, StackTrace? stackTrace})? get logger => _logger;

  @override
  String? get taskName => _taskName;
}

ReactiveSplashTask<T> task<T>({
  required Future<T> Function(Ref ref) watch,
  required Future<void> Function(Ref ref, T watchedData) execute,
  bool? enableLogging,
  void Function(String level, String message, {Object? error, StackTrace? stackTrace})? logger,
  String? taskName,
}) {
  return _ClosureReactiveTask(
    watch, 
    execute, 
    enableLogging: enableLogging,
    logger: logger,
    taskName: taskName,
  );
}

/// Creates a reactive task with enhanced logging enabled by default
ReactiveSplashTask<T> loggedTask<T>({
  required Future<T> Function(Ref ref) watch,
  required Future<void> Function(Ref ref, T watchedData) execute,
  String? taskName,
  void Function(String level, String message, {Object? error, StackTrace? stackTrace})? logger,
}) {
  return task(
    watch: watch,
    execute: execute,
    enableLogging: true,
    taskName: taskName,
    logger: logger,
  );
}

/// Creates a reactive task with logging disabled
ReactiveSplashTask<T> silentTask<T>({
  required Future<T> Function(Ref ref) watch,
  required Future<void> Function(Ref ref, T watchedData) execute,
  String? taskName,
}) {
  return task(
    watch: watch,
    execute: execute,
    enableLogging: false,
    taskName: taskName,
  );
}
