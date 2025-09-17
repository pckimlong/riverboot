part of 'src.dart';

/// The main class for initializing a Riverboot application.
/// Run this in the main function. Then add [SplashBuilder] to [MaterialApp] or [CupertinoApp] builder function.
class Riverboot {
  const Riverboot._();

  static Future<void> initialize({
    required Widget application,

    /// For more advanced use cases, you can provide a parent container.
    ProviderContainer? parent,

    /// Global retry function for all providers created in the container.
    Duration? Function(int, Object)? retry,

    /// This task run before running the app, this is useful for initializing some root things,
    /// just make sure the task in here is fast enough to not block the app startup and not most likely error prone
    /// since it won't be retried and if it fails the app won't start.
    Future<void> Function(ProviderContainer container)? preRunTask,

    SplashConfig? splashConfig,

    List<Override> overrides = const [],
    List<ProviderObserver>? observers,
    bool Function(Object, StackTrace)? onPlatformDispatchError,
    void Function(WidgetRef ref)? earlyEagerInitializer,
    void Function(Object error, StackTrace stack)? onError,

    /// Logging configuration for Riverboot operations
    RiverbootLoggingConfig loggingConfig = const RiverbootLoggingConfig(),
  }) async {
    final container = ProviderContainer(
      parent: parent,
      overrides: [
        if (splashConfig != null)
          _splashConfigProvider.overrideWithValue(splashConfig),
        _loggingConfigProvider.overrideWithValue(loggingConfig),
        ...overrides,
      ],
      observers: observers,
      retry: retry,
    );

    if (onPlatformDispatchError != null) {
      PlatformDispatcher.instance.onError = onPlatformDispatchError;
    }

    await runZonedGuarded(
      () async {
        WidgetsFlutterBinding.ensureInitialized();

        await _executePreRunTask(preRunTask, container, onError, loggingConfig);

        runApp(
          UncontrolledProviderScope(
            container: container,
            child: Consumer(
              builder: (context, ref, child) {
                // Early eager initialization to load the providers in the background without awaiting them. https://riverpod.dev/docs/how_to/eager_initialization
                try {
                  earlyEagerInitializer?.call(ref);
                } catch (e, stack) {
                  // ignore the error, just log it, this ensure app not crash on startup
                  onError?.call(e, stack);
                }

                return child!;
              },
              child: application,
            ),
          ),
        );
      },
      (error, stack) {
        if (onError != null) {
          onError(error, stack);
        } else {
          // If no error handler is provided, print the error to the console.
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stack,
              library: 'Riverboot',
              context: ErrorDescription('while running the application'),
            ),
          );
        }
      },
    );
  }

  static Future<void> _executePreRunTask(
    Future<void> Function(ProviderContainer container)? preRunTask,
    ProviderContainer container,
    void Function(Object error, StackTrace stack)? onError,
    RiverbootLoggingConfig loggingConfig,
  ) async {
    if (preRunTask == null) return;

    final stopwatch = Stopwatch();
    
    try {
      if (loggingConfig.logTaskStart) {
        loggingConfig._log('Starting preRunTask execution');
      }
      
      if (loggingConfig.logTaskTiming) {
        stopwatch.start();
      }

      await preRunTask(container);

      if (loggingConfig.logTaskTiming) {
        stopwatch.stop();
        loggingConfig._log('preRunTask completed in ${stopwatch.elapsedMilliseconds}ms');
      } else if (loggingConfig.logTaskCompletion) {
        loggingConfig._log('preRunTask completed successfully');
      }
    } catch (e, stack) {
      if (loggingConfig.logTaskTiming && stopwatch.isRunning) {
        stopwatch.stop();
        loggingConfig._log('preRunTask failed after ${stopwatch.elapsedMilliseconds}ms');
      }

      if (onError != null) {
        onError.call(e, stack);
      } else {
        // Enhanced error logging with more context
        if (loggingConfig.logTaskErrors) {
          loggingConfig._log(
            'Error in preRunTask: ${e.runtimeType}: $e',
            error: e,
            stackTrace: stack,
          );
        } else {
          // Fallback to basic logging
          log('Error in preRunTask', name: 'Riverboot', error: e, stackTrace: stack);
        }
      }
      rethrow;
    }
  }
}
