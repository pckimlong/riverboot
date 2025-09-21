part of 'src.dart';

final _splashConfigProvider = Provider<SplashConfig?>((ref) => throw UnimplementedError());

final _oneTimeSplashTasksProvider = FutureProvider<bool>((ref) async {
  final config = ref.watch(_splashConfigProvider);
  if (config == null) return true;

  final stopwatch = Stopwatch()..start();
  final tasks = config.oneTimeTasks;

  if (tasks.isNotEmpty) {
    if (config.runOneTimeTaskInParallel) {
      await Future.wait([for (final task in tasks) task(ref)]);
    } else {
      for (final task in tasks) {
        await task(ref);
      }
    }
  }

  stopwatch.stop();
  final remaining = config.minimumDuration - stopwatch.elapsed;
  if (remaining > Duration.zero) {
    await Future.delayed(remaining);
  }

  return true;
});

final _reactiveSplashTasksProvider = FutureProvider.autoDispose.family<dynamic, int>((
  ref,
  index,
) async {
  final config = ref.watch(_splashConfigProvider);
  final tasks = config?.reactiveTasks;
  if (config == null || tasks == null || index >= tasks.length) return;

  final task = tasks[index];
  return await task.watch(ref);
});

final _reactiveSplashTasksExecuteProvider = FutureProvider.autoDispose.family<void, int>((
  ref,
  index,
) async {
  final config = ref.watch(_splashConfigProvider);
  final tasks = config?.reactiveTasks;
  if (config == null || tasks == null || index >= tasks.length) return;

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
  final Widget Function(SplashTaskError? error, VoidCallback? retry) splashBuilder;

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
