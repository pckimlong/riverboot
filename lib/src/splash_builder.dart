part of 'src.dart';

class SplashBuilder extends ConsumerStatefulWidget {
  const SplashBuilder({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _SplashBuilderState();
}

class _SplashBuilderState extends ConsumerState<SplashBuilder> {
  final Set<int> _changedWatchValues = {};

  final Map<int, bool> _activeWatchValues = {};

  final Map<int, bool> _activeExecuteTasks = {};

  final List<ProviderSubscription<dynamic>> _subscriptions = [];

  bool get isReactiveTasksLoading {
    return _changedWatchValues.isNotEmpty ||
        _activeWatchValues.values.any((isLoading) => isLoading) ||
        _activeExecuteTasks.values.any((isLoading) => isLoading);
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

    final reactiveTasks = config.reactiveTasks;

    _initializeTaskStates(reactiveTasks.length);

    for (int taskIndex = 0; taskIndex < reactiveTasks.length; taskIndex++) {
      _setupWatchProviderListener(taskIndex);
      _setupExecuteProviderListener(taskIndex);
    }
  }

  void _initializeTaskStates(int taskCount) {
    for (int i = 0; i < taskCount; i++) {
      _changedWatchValues.add(i);
      _activeWatchValues[i] = true;
      _activeExecuteTasks[i] = true;
    }
  }

  void _setupWatchProviderListener(int taskIndex) {
    final subscription = ref.listenManual(
      _reactiveSplashTasksProvider(taskIndex),
      (previous, next) {
        setState(() {
          if (previous?.value != next.value) {
            _changedWatchValues.add(taskIndex);
          }

          _activeWatchValues[taskIndex] = !next.hasValue;
        });
      },
    );
    _subscriptions.add(subscription);
  }

  void _setupExecuteProviderListener(int taskIndex) {
    final subscription = ref.listenManual(
      _reactiveSplashTasksExecuteProvider(taskIndex),
      (previous, next) {
        setState(() {
          if (next.isLoading || next.hasError) {
            _activeExecuteTasks[taskIndex] = true;
          } else if (next.hasValue) {
            _activeExecuteTasks[taskIndex] = false;
            _changedWatchValues.remove(taskIndex);
          }
        });
      },
    );
    _subscriptions.add(subscription);
  }

  void _disposeListeners() {
    for (final subscription in _subscriptions) {
      subscription.close();
    }
    _subscriptions.clear();
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

      _hasAnyError(ref, config, oneTimeSplashTask)
          ? _createRetryCallback(oneTimeSplashTask)
          : null,
    );
  }

  VoidCallback _createRetryCallback(AsyncValue<bool> oneTimeSplashTask) {
    return () {
      for (final taskIndex in _activeExecuteTasks.keys) {
        ref.invalidate(_reactiveSplashTasksProvider(taskIndex));
        ref.invalidate(_reactiveSplashTasksExecuteProvider(taskIndex));
      }

      if (oneTimeSplashTask.hasError) {
        ref.invalidate(_oneTimeSplashTasksProvider);
      }

      setState(() {
        _activeExecuteTasks.clear();
        _activeWatchValues.clear();
        _changedWatchValues.clear();
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _setupListeners();
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
