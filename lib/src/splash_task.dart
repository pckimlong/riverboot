part of 'src.dart';

final _splashConfigProvider = Provider<SplashConfig?>(
  (ref) => throw UnimplementedError(),
);

final _splashTaskCoordinatorProvider =
    NotifierProvider<_SplashTaskCoordinator, int>(_SplashTaskCoordinator.new);

final _splashTaskProvider = FutureProvider.family<void, _SplashTaskKey>(
  (ref, key) async {
    final coordinator = ref.read(_splashTaskCoordinatorProvider.notifier);
    coordinator.begin(key);

    final taskRef = _SplashTaskRef(ref, key);
    try {
      await key.config.tasks[key.index](taskRef);
      if (ref.mounted) {
        coordinator.succeed(key);
      }
    } on _ObsoleteSplashTask {
      // A replacement execution owns readiness and error reporting now.
      return;
    } catch (error, stack) {
      if (ref.mounted) {
        coordinator.fail(key);
      }
      Error.throwWithStackTrace(error, stack);
    }
  },
  // The aggregate provider owns Riverboot's retry/error lifecycle. Allowing
  // both layers to retry would keep the aggregate pending behind a child retry.
  retry: (_, _) => null,
);

/// Aggregates the isolated splash tasks.
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
        [
          for (var index = 0; index < tasks.length; index++)
            ref.watch(
              _splashTaskProvider(_SplashTaskKey(config, index)).future,
            ),
        ],
        eagerError: true,
      );
    } else {
      for (var index = 0; index < tasks.length; index++) {
        await ref.watch(
          _splashTaskProvider(_SplashTaskKey(config, index)).future,
        );
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

@visibleForTesting
Provider<SplashConfig?> get splashConfigProvider => _splashConfigProvider;

@visibleForTesting
FutureProvider<void> get splashTasksProvider => _splashTasksProvider;

@visibleForTesting
FutureProvider<void> splashTaskProvider(SplashConfig config, int index) =>
    _splashTaskProvider(_SplashTaskKey(config, index));

typedef SplashTask = Future<void> Function(SplashTaskRef ref);

/// Riverpod access scoped to a single splash task.
///
/// The methods make the task's splash and lifecycle policy explicit:
///
/// - [watch] reruns the owning task without showing splash after initial boot.
/// - [watchForSplash] reruns the owning task and shows splash.
/// - [wait] awaits and retains an async provider without rerunning the task.
/// - [retain] initializes and retains a provider without rerunning the task.
/// - [read] performs a one-shot read without retaining the provider.
abstract interface class SplashTaskRef {
  /// Whether the isolated task provider is still active.
  bool get mounted;

  /// Stops this execution if its task has been replaced or disposed.
  ///
  /// Call after external awaits before applying their results. This cannot
  /// cancel external work or undo side effects already in progress.
  /// Let Riverboot handle the internal cancellation signal.
  void ensureActive();

  /// Watches [provider] and silently reloads only this task when it changes.
  T watch<T>(ProviderListenable<T> provider);

  /// Watches [provider] and restores splash while this task reloads.
  T watchForSplash<T>(ProviderListenable<T> provider);

  /// Initializes and keeps [provider] alive without making it a dependency.
  T retain<T>(ProviderListenable<T> provider);

  /// Awaits and retains [provider] without making it a task dependency.
  ///
  /// Stops obsolete executions before and after awaiting. Failed refreshable
  /// expressions (such as `provider.future`) are refreshed on manual retry.
  /// For selected expressions, use [invalidateOnRetry] explicitly.
  Future<T> wait<T>(ProviderListenable<Future<T>> provider);

  /// Reads [provider] once without retaining it or making it a dependency.
  T read<T>(ProviderListenable<T> provider);

  /// Invalidates [provider].
  void invalidate(ProviderOrFamily provider);

  /// Invalidates [provider] before this failed task is manually retried.
  void invalidateOnRetry(ProviderOrFamily provider);

  /// Registers cleanup for this isolated task provider.
  void onDispose(void Function() callback);
}

final class _SplashTaskRef implements SplashTaskRef {
  _SplashTaskRef(this._ref, this._key);

  final Ref _ref;
  final _SplashTaskKey _key;

  @override
  bool get mounted => _ref.mounted;

  @override
  T watch<T>(ProviderListenable<T> provider) => _ref.watch(provider);

  @override
  T watchForSplash<T>(ProviderListenable<T> provider) {
    void reloadTask() {
      final coordinator = _ref.read(_splashTaskCoordinatorProvider.notifier);
      coordinator.block(_key);
      _ref.invalidateSelf(asReload: true);
    }

    final subscription = _ref.listen<T>(
      provider,
      (_, _) => reloadTask(),
      onError: (_, _) => reloadTask(),
    );
    return subscription.read();
  }

  @override
  T retain<T>(ProviderListenable<T> provider) {
    final subscription = _ref.listen<T>(provider, (_, _) {});
    return subscription.read();
  }

  @override
  Future<T> wait<T>(ProviderListenable<Future<T>> provider) async {
    ensureActive();
    try {
      final value = await retain(provider);
      ensureActive();
      return value;
    } catch (_) {
      ensureActive();
      if (provider is Refreshable<Future<T>>) {
        _ref
            .read(_splashTaskCoordinatorProvider.notifier)
            .registerFailedWait(_key, provider);
      }
      rethrow;
    }
  }

  @override
  void ensureActive() {
    if (!mounted) throw const _ObsoleteSplashTask();
  }

  @override
  T read<T>(ProviderListenable<T> provider) => _ref.read(provider);

  @override
  void invalidate(ProviderOrFamily provider) => _ref.invalidate(provider);

  @override
  void invalidateOnRetry(ProviderOrFamily provider) {
    _ref
        .read(_splashTaskCoordinatorProvider.notifier)
        .registerRetry(_key, provider);
  }

  @override
  void onDispose(void Function() callback) => _ref.onDispose(callback);
}

final class _ObsoleteSplashTask implements Exception {
  const _ObsoleteSplashTask();
}

class _SplashTaskKey {
  const _SplashTaskKey(this.config, this.index);

  final SplashConfig config;
  final int index;

  @override
  bool operator ==(Object other) {
    return other is _SplashTaskKey &&
        identical(other.config, config) &&
        other.index == index;
  }

  @override
  int get hashCode => Object.hash(identityHashCode(config), index);
}

class _SplashTaskCoordinator extends Notifier<int> {
  final Set<_SplashTaskKey> _blocking = {};
  final Set<_SplashTaskKey> _failed = {};
  final Map<_SplashTaskKey, Set<ProviderOrFamily>> _retryDependencies = {};
  final Map<_SplashTaskKey, Set<Refreshable<Future<Object?>>>> _failedWaits =
      {};
  bool _notificationScheduled = false;

  bool get hasBlockingTask => _blocking.isNotEmpty;

  @override
  int build() => 0;

  void begin(_SplashTaskKey key) {
    _failed.remove(key);
    _retryDependencies[key] = {};
    _failedWaits[key] = {};
  }

  void block(_SplashTaskKey key) {
    if (_blocking.add(key)) _notify();
  }

  void registerRetry(_SplashTaskKey key, ProviderOrFamily provider) {
    (_retryDependencies[key] ??= {}).add(provider);
  }

  void registerFailedWait(
    _SplashTaskKey key,
    Refreshable<Future<Object?>> provider,
  ) {
    (_failedWaits[key] ??= {}).add(provider);
  }

  void succeed(_SplashTaskKey key) {
    _failed.remove(key);
  }

  void fail(_SplashTaskKey key) {
    if (_failed.add(key)) _notify();
  }

  void clearBlockingTasks() {
    if (_blocking.isEmpty) return;
    _blocking.clear();
    _notify();
  }

  void retryFailedTasks() {
    final failed = _failed.toList(growable: false);
    for (final key in failed) {
      for (final provider
          in _retryDependencies[key] ?? const <ProviderOrFamily>{}) {
        ref.invalidate(provider);
      }
      for (final provider
          in _failedWaits[key] ?? const <Refreshable<Future<Object?>>>{}) {
        // Refresh starts the dependency immediately. Observe its error even if
        // the retried task exits before reaching this wait again.
        unawaited(
          ref
              .refresh(provider)
              .then<void>((_) {}, onError: (Object _, StackTrace _) {}),
        );
      }
      ref.invalidate(_splashTaskProvider(key));
    }
  }

  void _notify() {
    if (_notificationScheduled) return;
    _notificationScheduled = true;
    Future.microtask(() {
      _notificationScheduled = false;
      if (ref.mounted) state++;
    });
  }
}

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
  final Widget Function(SplashTaskError? error, VoidCallback? retry)
  splashBuilder;

  /// Isolated tasks that gate the initial splash.
  ///
  /// A task can use [SplashTaskRef.watch] for silent reloads,
  /// [SplashTaskRef.watchForSplash] for blocking reloads, and
  /// [SplashTaskRef.wait]/[SplashTaskRef.retain] to avoid a reactive edge.
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
  /// ## Retry support
  ///
  /// Failed `wait(provider.future)` dependencies refresh automatically.
  /// Register deeper dependencies explicitly when necessary:
  ///
  /// ```dart
  /// tasks: [
  ///   (ref) async {
  ///     ref.invalidateOnRetry(configProvider);
  ///     await ref.wait(configProvider.future);
  ///   },
  /// ]
  /// ```
  final List<SplashTask> tasks;

  /// Whether to run startup tasks in parallel or sequentially. Default is `true`.
  final bool runTasksInParallel;

  /// The minimum duration to show the splash screen. Default is `Duration.zero`.
  final Duration minimumDuration;

  /// Whether to use a fade transition when switching from splash to child widget.
  ///
  /// When `true` (default), the child widget fades in smoothly after splash tasks complete.
  /// Set to `false` for an instant switch.
  final bool fadeTransition;

  /// The duration of the fade transition. Default is `300ms`.
  ///
  /// Only used when [fadeTransition] is `true`.
  final Duration fadeDuration;

  SplashConfig({
    required this.splashBuilder,
    List<SplashTask> tasks = const [],
    this.minimumDuration = Duration.zero,
    this.runTasksInParallel = true,
    this.fadeTransition = true,
    this.fadeDuration = const Duration(milliseconds: 300),
  }) : tasks = List.unmodifiable(tasks);
}
