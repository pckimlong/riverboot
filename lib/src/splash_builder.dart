part of 'src.dart';

class SplashBuilder extends ConsumerStatefulWidget {
  const SplashBuilder({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _SplashBuilderState();
}

class _SplashBuilderState extends ConsumerState<SplashBuilder> {
  // Use fixed-size lists for O(1) access instead of maps
  late List<bool> _changedWatchValues;
  late List<bool> _activeWatchValues;
  late List<bool> _activeExecuteTasks;

  final List<ProviderSubscription<dynamic>> _subscriptions = [];

  // Cache loading state to avoid repeated iteration
  int _activeWatchCount = 0;
  int _activeExecuteCount = 0;
  int _changedWatchCount = 0;

  bool get isReactiveTasksLoading {
    return _changedWatchCount > 0 || _activeWatchCount > 0 || _activeExecuteCount > 0;
  }

  @override
  void initState() {
    super.initState();
    _setupListeners();
  }

  @override
  void dispose() {
    _disposeListeners();
    super.dispose();
  }

  void _setupListeners() {
    _disposeListeners();
    final config = ref.read(_splashConfigProvider);
    if (config == null) return;

    final taskCount = config.reactiveTasks.length;
    if (taskCount == 0) return;

    _initializeTaskStates(taskCount);

    for (int taskIndex = 0; taskIndex < taskCount; taskIndex++) {
      _setupWatchProviderListener(taskIndex);
      _setupExecuteProviderListener(taskIndex);
    }
  }

  void _initializeTaskStates(int taskCount) {
    // Pre-allocate fixed-size lists
    _changedWatchValues = List<bool>.filled(taskCount, true);
    _activeWatchValues = List<bool>.filled(taskCount, true);
    _activeExecuteTasks = List<bool>.filled(taskCount, true);

    // Initialize counters
    _changedWatchCount = taskCount;
    _activeWatchCount = taskCount;
    _activeExecuteCount = taskCount;
  }

  void _setupWatchProviderListener(int taskIndex) {
    final subscription = ref.listenManual(
      _reactiveSplashTasksProvider(taskIndex),
      (previous, next) {
        final wasChanged = _changedWatchValues[taskIndex];
        final wasActive = _activeWatchValues[taskIndex];
        final shouldMarkChanged = previous?.value != next.value;
        final isNowActive = !next.hasValue;

        // Only call setState if state actually changed
        if ((shouldMarkChanged && !wasChanged) || wasActive != isNowActive) {
          setState(() {
            if (shouldMarkChanged && !wasChanged) {
              _changedWatchValues[taskIndex] = true;
              _changedWatchCount++;
            }
            if (wasActive != isNowActive) {
              _activeWatchValues[taskIndex] = isNowActive;
              _activeWatchCount += isNowActive ? 1 : -1;
            }
          });
        }
      },
    );
    _subscriptions.add(subscription);
  }

  void _setupExecuteProviderListener(int taskIndex) {
    final subscription = ref.listenManual(
      _reactiveSplashTasksExecuteProvider(taskIndex),
      (previous, next) {
        final wasActive = _activeExecuteTasks[taskIndex];
        final wasChanged = _changedWatchValues[taskIndex];
        final shouldBeActive = next.isLoading || next.hasError;
        final shouldClearChanged = next.hasValue && wasChanged;

        // Only call setState if state actually changed
        if (wasActive != shouldBeActive || shouldClearChanged) {
          setState(() {
            if (wasActive != shouldBeActive) {
              _activeExecuteTasks[taskIndex] = shouldBeActive;
              _activeExecuteCount += shouldBeActive ? 1 : -1;
            }
            if (shouldClearChanged) {
              _changedWatchValues[taskIndex] = false;
              _changedWatchCount--;
            }
          });
        }
      },
    );
    _subscriptions.add(subscription);
  }

  void _disposeListeners() {
    for (final subscription in _subscriptions) {
      subscription.close();
    }
    _subscriptions.clear();
    _activeWatchCount = 0;
    _activeExecuteCount = 0;
    _changedWatchCount = 0;
  }

  bool _shouldShowSplash(
    SplashConfig config,
    AsyncValue<bool> oneTimeSplashTask,
  ) {
    if (!oneTimeSplashTask.hasValue) {
      return true;
    }

    if (isReactiveTasksLoading) {
      return true;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(_splashConfigProvider);
    if (config == null) {
      return widget.child;
    }

    final oneTimeSplashTask = ref.watch(_oneTimeSplashTasksProvider);

    final shouldShowSplash = _shouldShowSplash(config, oneTimeSplashTask);

    if (!shouldShowSplash) {
      return widget.child;
    }

    return config.splashBuilder(
      _getFirstError(ref, config, oneTimeSplashTask),

      _hasAnyError(ref, config, oneTimeSplashTask) ? _createRetryCallback(oneTimeSplashTask) : null,
    );
  }

  VoidCallback _createRetryCallback(AsyncValue<bool> oneTimeSplashTask) {
    return () {
      final config = ref.read(_splashConfigProvider);
      final taskCount = config?.reactiveTasks.length ?? 0;

      for (int taskIndex = 0; taskIndex < taskCount; taskIndex++) {
        ref.invalidate(_reactiveSplashTasksProvider(taskIndex));
        ref.invalidate(_reactiveSplashTasksExecuteProvider(taskIndex));
      }

      if (oneTimeSplashTask.hasError) {
        ref.invalidate(_oneTimeSplashTasksProvider);
      }

      // Reset counters - no need to clear lists as they'll be reinitialized
      _activeWatchCount = 0;
      _activeExecuteCount = 0;
      _changedWatchCount = 0;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _setupListeners();
        // Trigger rebuild after listeners are set up
        if (mounted) setState(() {});
      });
    };
  }

  SplashTaskError? _getFirstError(
    WidgetRef ref,
    SplashConfig config,
    AsyncValue<bool> oneTimeTask,
  ) {
    if (oneTimeTask.hasError) {
      return SplashTaskError(
        error: oneTimeTask.error!,
        stack: oneTimeTask.stackTrace!,
      );
    }

    final tasks = config.reactiveTasks;
    for (int i = 0; i < tasks.length; i++) {
      final watchState = ref.read(_reactiveSplashTasksProvider(i));
      if (watchState.hasError) {
        return SplashTaskError(
          error: watchState.error!,
          stack: watchState.stackTrace!,
        );
      }

      final executeState = ref.read(_reactiveSplashTasksExecuteProvider(i));
      if (executeState.hasError) {
        return SplashTaskError(
          error: executeState.error!,
          stack: executeState.stackTrace!,
        );
      }
    }

    return null;
  }

  bool _hasAnyError(
    WidgetRef ref,
    SplashConfig config,
    AsyncValue<bool> oneTimeTask,
  ) {
    if (oneTimeTask.hasError) {
      return true;
    }

    final tasks = config.reactiveTasks;
    for (int i = 0; i < tasks.length; i++) {
      final watchState = ref.read(_reactiveSplashTasksProvider(i));
      if (watchState.hasError) {
        return true;
      }

      final executeState = ref.read(_reactiveSplashTasksExecuteProvider(i));
      if (executeState.hasError) {
        return true;
      }
    }

    return false;
  }
}
