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

    final isComplete = oneTimeComplete && reactiveComplete;

    // Check for errors - prioritize one-time task errors
    final error = oneTimeTask.hasError
        ? SplashTaskError(error: oneTimeTask.error!, stack: oneTimeTask.stackTrace!)
        : reactiveTaskRun.hasError
        ? SplashTaskError(error: reactiveTaskRun.error!, stack: reactiveTaskRun.stackTrace!)
        : null;

    if (error != null) {
      return config.splashBuilder(error, () {
        ref.invalidate(_splashTasksProvider);
        ref.invalidate(_reactiveTaskRunProvider);
      });
    }

    return _SplashTransition(
      isComplete: isComplete,
      config: config,
      splashBuilder: (context) => config.splashBuilder(null, null),
      child: child,
    );
  }
}

/// Handles the splash-to-child transition animation.
///
/// ## Why this exists (Jank Prevention)
///
/// The naive approach of switching widgets causes UI jank (dropped frames):
/// ```dart
/// // BAD: Causes jank - entire child tree builds in one frame
/// return isComplete ? child : splash;
/// ```
///
/// When [isComplete] becomes true, Flutter must build the entire child widget
/// tree in a single frame, causing visible stuttering.
///
/// ## How this solves it
///
/// 1. **Child builds while splash is visible**: When tasks complete, we add
///    the child to a Stack underneath the splash. The splash hides any jank
///    from the child's initial build.
///
/// 2. **Deferred animation start**: We use [addPostFrameCallback] to wait
///    one frame after the child builds before starting the fade animation.
///    This gives the child time to "settle" (complete layout, paint, etc.).
///
/// 3. **Splash fades out on top**: The splash smoothly fades away, revealing
///    the already-rendered child underneath.
///
/// ## Trade-offs
///
/// - Uses a Stack during transition (slight overhead)
/// - Child is only built when [isComplete] is true, so dependencies are
///   guaranteed to be ready (this is the whole point of SplashBuilder)
///
/// ## Future improvements to consider
///
/// - Investigate if [Offstage] or [Visibility] could pre-build child earlier
///   without accessing unready dependencies
/// - Consider using [RepaintBoundary] to isolate child rendering
/// - Profile with Flutter DevTools to measure actual frame times
class _SplashTransition extends StatefulWidget {
  const _SplashTransition({
    required this.isComplete,
    required this.config,
    required this.splashBuilder,
    required this.child,
  });

  final bool isComplete;
  final SplashConfig config;
  final WidgetBuilder splashBuilder;
  final Widget child;

  @override
  State<_SplashTransition> createState() => _SplashTransitionState();
}

class _SplashTransitionState extends State<_SplashTransition> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  bool _showChild = false;
  bool _showSplash = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: widget.config.fadeDuration, vsync: this);
    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _controller.addStatusListener(_onAnimationEnd);

    if (widget.isComplete) {
      _showChild = true;
      _showSplash = false;
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_onAnimationEnd);
    _controller.dispose();
    super.dispose();
  }

  void _onAnimationEnd(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) {
      setState(() => _showSplash = false);
    }
  }

  @override
  void didUpdateWidget(_SplashTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.duration = widget.config.fadeDuration;

    // Incomplete -> Complete: start fade out
    if (widget.isComplete && !oldWidget.isComplete) {
      _showChild = true;
      _showSplash = true;
      _controller.value = 0.0;

      if (!widget.config.fadeTransition) {
        _controller.value = 1.0;
        _showSplash = false;
      } else {
        // Wait for child to build, then start animation
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _controller.forward();
        });
      }
    }
    // Complete -> Incomplete: reset
    else if (!widget.isComplete && oldWidget.isComplete) {
      _controller.reset();
      _showChild = false;
      _showSplash = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 1. Still loading - show splash only
    if (!widget.isComplete) {
      return widget.splashBuilder(context);
    }

    // 2. Fully transitioned - show child only
    if (!_showSplash) {
      return widget.child;
    }

    // 3. Transitioning - Buffer Phase & Animation
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_showChild)
          // OPTIMIZATION 1: RepaintBoundary
          // Caches the heavy app layout so the fade animation is silky smooth
          RepaintBoundary(
            child: widget.child,
          ),

        // OPTIMIZATION 2: IgnorePointer
        // Prevents the user from interacting with the 'fading' splash
        // (or accidentally tapping the app through the ghost of the splash)
        IgnorePointer(
          // Ignoring=true allows taps to pass through to the app (if that's what you want)
          // Ignoring=false blocks taps (if you want to freeze input during fade)
          // Usually, during fade out, we want to BLOCK input until fully revealed:
          ignoring: false, // Splash catches taps until it is removed
          child: FadeTransition(
            opacity: ReverseAnimation(_fadeAnimation),
            child: widget.splashBuilder(context),
          ),
        ),
      ],
    );
  }
}
