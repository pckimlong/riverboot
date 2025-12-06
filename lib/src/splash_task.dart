part of 'src.dart';

final _splashConfigProvider = Provider<SplashConfig?>(
  (ref) => throw UnimplementedError(),
);

final _oneTimeSplashTasksProvider = FutureProvider<bool>((ref) async {
  final config = ref.watch(_splashConfigProvider);
  if (config == null) return true;

  final tasks = config.oneTimeTasks;
  final minimumDuration = config.minimumDuration;
  final hasMinDuration = minimumDuration > Duration.zero;

  // Early return if no tasks and no minimum duration
  if (tasks.isEmpty && !hasMinDuration) return true;

  final stopwatch = hasMinDuration ? (Stopwatch()..start()) : null;

  if (tasks.isNotEmpty) {
    if (config.runOneTimeTaskInParallel) {
      // Use more efficient Future.wait with growable: false
      await Future.wait(
        [for (final task in tasks) task(ref)],
        eagerError: true,
      );
    } else {
      for (final task in tasks) {
        await task(ref);
      }
    }
  }

  if (stopwatch != null) {
    stopwatch.stop();
    final remaining = minimumDuration - stopwatch.elapsed;
    if (remaining > Duration.zero) {
      await Future.delayed(remaining);
    }
  }

  return true;
});

final _reactiveSplashTasksProvider = FutureProvider.autoDispose.family<dynamic, int>((
  ref,
  index,
) async {
  final config = ref.watch(_splashConfigProvider);
  if (config == null) return null;

  final tasks = config.reactiveTasks;
  if (index >= tasks.length) return null;

  return await tasks[index].watch(ref);
});

final _reactiveSplashTasksExecuteProvider = FutureProvider.autoDispose.family<void, int>((
  ref,
  index,
) async {
  final config = ref.watch(_splashConfigProvider);
  if (config == null) return;

  final tasks = config.reactiveTasks;
  if (index >= tasks.length) return;

  final data = await ref.watch(_reactiveSplashTasksProvider(index).future);
  await tasks[index].execute(ref, data);
});

@visibleForTesting
Provider<SplashConfig?> get splashConfigProvider => _splashConfigProvider;

@visibleForTesting
FutureProvider<bool> get oneTimeSplashTasksProvider => _oneTimeSplashTasksProvider;

@visibleForTesting
FutureProvider<dynamic> Function(int) get reactiveSplashTasksProvider =>
    (index) => _reactiveSplashTasksProvider(index);

@visibleForTesting
FutureProvider<void> Function(int) get reactiveSplashTasksExecuteProvider =>
    (index) => _reactiveSplashTasksExecuteProvider(index);

class SplashTaskError implements Exception {
  final Object error;
  final StackTrace stack;

  // Cache the string representation for repeated access
  String? _cachedString;

  SplashTaskError({required this.error, required this.stack});

  @override
  String toString() {
    // Return cached value if available
    if (_cachedString != null) return _cachedString!;

    final buffer = StringBuffer('SplashTaskError: ');
    buffer.write(error.runtimeType);

    if (error is Exception || error is Error) {
      buffer.write(': ');
      buffer.write(error.toString());
    }

    // Only include stack trace, limit to first 5 lines
    final stackLines = stack.toString().split('\n');
    final limitedStack = stackLines.length > 5
        ? stackLines.sublist(0, 5).join('\n')
        : stackLines.join('\n');
    buffer.write('\nStack trace (first 5 lines):\n');
    buffer.write(limitedStack);

    _cachedString = buffer.toString();
    return _cachedString!;
  }
}

class SplashConfig {
  /// The splash screen widget builder. For injecting splash widget
  final Widget Function(SplashTaskError? error, VoidCallback? retry) splashBuilder;

  /// One-time tasks to run during splash. Immutable after construction.
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

  SplashConfig({
    required this.splashBuilder,
    List<Future<void> Function(Ref ref)> oneTimeTasks = const [],
    List<ReactiveSplashTask> reactiveTasks = const [],
    this.minimumDuration = Duration.zero,
    this.runOneTimeTaskInParallel = true,
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
