part of 'src.dart';

/// A widget that shows a splash screen while tasks are loading.
///
/// Place this in your [MaterialApp] or [CupertinoApp] builder function.
class SplashBuilder extends ConsumerWidget {
  const SplashBuilder({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(_splashConfigProvider);
    if (config == null) {
      return child;
    }

    final oneTimeTask = ref.watch(_splashTasksProvider);

    // Listen to trigger - when it changes, invalidate run provider (sets isRefreshing)
    ref.listen(_reactiveTaskTriggerProvider, (_, _) {
      ref.invalidate(_reactiveTaskRunProvider);
    });

    final reactiveTaskRun = ref.watch(_reactiveTaskRunProvider);

    // One-time tasks: once completed, never show splash again (unless manual retry)
    final oneTimeComplete = oneTimeTask.hasValue && !oneTimeTask.isRefreshing;

    // Reactive task: show splash only on isRefreshing (trigger changed or manual retry)
    // isReloading (run's own dependencies) won't show splash
    final reactiveComplete = reactiveTaskRun.hasValue && !reactiveTaskRun.isRefreshing;

    if (oneTimeComplete && reactiveComplete) {
      return child;
    }

    // Check for errors - prioritize one-time task errors
    final error = oneTimeTask.hasError
        ? SplashTaskError(error: oneTimeTask.error!, stack: oneTimeTask.stackTrace!)
        : reactiveTaskRun.hasError
        ? SplashTaskError(error: reactiveTaskRun.error!, stack: reactiveTaskRun.stackTrace!)
        : null;

    if (error != null) {
      return config.splashBuilder(
        error,
        () {
          ref.invalidate(_splashTasksProvider);
          ref.invalidate(_reactiveTaskRunProvider);
        },
      );
    }

    // Loading state
    return config.splashBuilder(null, null);
  }
}
