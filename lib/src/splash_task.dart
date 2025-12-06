part of 'src.dart';

final _splashConfigProvider = Provider<SplashConfig?>(
  (ref) => throw UnimplementedError(),
);

/// One-time tasks - run once at app start
final _splashTasksProvider = FutureProvider<void>((ref) async {
  final config = ref.watch(_splashConfigProvider);
  if (config == null) return;

  final tasks = config.tasks;
  final minimumDuration = config.minimumDuration;
  final hasMinDuration = minimumDuration > Duration.zero;

  // Early return if no tasks and no minimum duration
  if (tasks.isEmpty && !hasMinDuration) return;

  final stopwatch = hasMinDuration ? (Stopwatch()..start()) : null;

  if (tasks.isNotEmpty) {
    if (config.runTasksInParallel) {
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
});

/// Watches the trigger - creates reactive dependency
final _reactiveTaskTriggerProvider = Provider<void>((ref) {
  final config = ref.watch(_splashConfigProvider);
  if (config == null) return;

  final reactiveTask = config.reactiveTask;
  if (reactiveTask == null) return;

  // Call trigger to establish watches
  reactiveTask.trigger(ref);
});

/// Executes the run function - invalidated by SplashBuilder when trigger changes
final _reactiveTaskRunProvider = FutureProvider<void>((ref) async {
  final config = ref.watch(_splashConfigProvider);
  if (config == null) return;

  final reactiveTask = config.reactiveTask;
  if (reactiveTask == null) return;

  // Execute run
  await reactiveTask.run(ref);
});

@visibleForTesting
Provider<SplashConfig?> get splashConfigProvider => _splashConfigProvider;

@visibleForTesting
FutureProvider<void> get splashTasksProvider => _splashTasksProvider;

@visibleForTesting
FutureProvider<void> get reactiveTaskRunProvider => _reactiveTaskRunProvider;

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

/// A reactive task that re-runs when watched providers change.
///
/// Use [trigger] to define what providers to watch. When any of them change,
/// [run] is executed and splash screen is shown during execution.
///
/// ```dart
/// ReactiveTask(
///   trigger: (ref) => ref.watch(authProvider),
///   run: (read) async {
///     final isAuth = await read(authProvider.future);
///     if (isAuth) {
///       await read(profileProvider.future);
///     }
///   },
/// )
/// ```
class ReactiveTask {
  /// Defines what triggers re-execution. Use [ref.watch] here.
  ///
  /// When any watched provider changes, [run] will be called again.
  final void Function(Ref ref) trigger;

  /// The work to execute.
  ///
  /// This runs:
  /// 1. On initial app start (along with one-time tasks)
  /// 2. Whenever [trigger]'s watched providers change
  ///
  /// Splash screen is shown only when [trigger] changes, not when
  /// providers watched inside [run] change.
  final Future<void> Function(Ref ref) run;

  const ReactiveTask({
    required this.trigger,
    required this.run,
  });
}

class SplashConfig {
  /// The splash screen widget builder. For injecting splash widget
  final Widget Function(SplashTaskError? error, VoidCallback? retry) splashBuilder;

  /// One-time tasks to run during splash.
  ///
  /// These run once at app start and never again (unless retry is triggered).
  ///
  /// ```dart
  /// tasks: [
  ///   (ref) async {
  ///     await initializeServices();
  ///     await loadConfig();
  ///   },
  /// ]
  /// ```
  ///
  /// ## Retry Support
  ///
  /// Use [ref.onDispose] to register cleanup for retry:
  ///
  /// ```dart
  /// tasks: [
  ///   (ref) async {
  ///     ref.onDispose(() => ref.invalidate(configProvider));
  ///     await ref.read(configProvider.future);
  ///   },
  /// ]
  /// ```
  final List<Future<void> Function(Ref ref)> tasks;

  /// Optional reactive task that re-runs when watched providers change.
  ///
  /// Use this for user session data that needs to reload on auth changes:
  ///
  /// ```dart
  /// reactiveTask: ReactiveTask(
  ///   trigger: (ref) => ref.watch(authProvider),  // What triggers re-run
  ///   run: (read) async {                          // Work to execute
  ///     final isAuth = await read(authProvider.future);
  ///     if (isAuth) {
  ///       await read(profileProvider.future);
  ///     }
  ///   },
  /// ),
  /// ```
  ///
  /// The [run] function only receives [read] - no [watch] - to prevent
  /// accidentally creating unwanted reactive dependencies.
  final ReactiveTask? reactiveTask;

  /// Whether to run the one-time tasks in parallel or sequentially. Default is `true`.
  final bool runTasksInParallel;

  /// The minimum duration to show the splash screen. Default is `Duration.zero`.
  final Duration minimumDuration;

  SplashConfig({
    required this.splashBuilder,
    List<Future<void> Function(Ref ref)> tasks = const [],
    this.reactiveTask,
    this.minimumDuration = Duration.zero,
    this.runTasksInParallel = true,
  }) : tasks = List.unmodifiable(tasks);
}
