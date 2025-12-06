# Riverboot

Riverboot bootstraps Flutter/Riverpod applications by orchestrating the work that
must happen before your UI goes live. Configure a splash experience once, plug
in tasks, and Riverboot will keep the screen up until the app is ready or an
error occurs.

## Highlights
- **Turn-key splash orchestration** – centralise initialization logic, display
  progress, and surface errors with a single builder.
- **One-time tasks** – run setup steps once at app start.
- **Reactive tasks** – re-run when watched providers change (e.g., auth state).
- **Parallel execution** – run tasks sequentially or concurrently.
- **Minimum splash duration** – keep animations on screen for a set amount of
  time even when work completes instantly.

## Getting Started
Create your `main.dart` and hand Riverboot the application widget together with
its splash configuration:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverboot/riverboot.dart';

final authProvider = FutureProvider<bool>((ref) async {
  await Future.delayed(const Duration(seconds: 1));
  return true;
});

final profileProvider = FutureProvider<String>((ref) async {
  await Future.delayed(const Duration(milliseconds: 500));
  return 'Riverboot User';
});

void main() {
  Riverboot.initialize(
    application: MaterialApp(
      builder: (context, child) => SplashBuilder(
        child: child ?? const SizedBox.shrink(),
      ),
      home: const HomePage(),
    ),
    splashConfig: SplashConfig(
      minimumDuration: const Duration(seconds: 1),
      splashBuilder: (error, retry) => _Splash(error: error, retry: retry),
      
      // One-time tasks - run once at app start
      tasks: [
        (ref) async {
          await initializeServices();
        },
      ],
      
      // Reactive task - re-runs when trigger changes
      reactiveTask: ReactiveTask(
        trigger: (ref) => ref.watch(authProvider),
        run: (ref) async {
          final authenticated = await ref.watch(authProvider.future);
          if (authenticated) {
            await ref.watch(profileProvider.future);
          }
        },
      ),
    ),
  );
}
```

Add `SplashBuilder` to your `MaterialApp` (or `CupertinoApp`) `builder` so the
splash UI can take over while tasks are in-flight.

## Tasks vs ReactiveTask

| | `tasks` | `reactiveTask` |
|---|---------|-----------------|
| **When** | Once at app start | When trigger changes |
| **Use for** | Init services, load config | User session data |
| **Shows splash** | Only on first run or manual retry | Every time trigger changes |

### ReactiveTask

When auth state changes (sign out → sign in), the reactive task re-runs and splash shows:

```dart
reactiveTask: ReactiveTask(
  // Only this triggers re-run and shows splash
  trigger: (ref) => ref.watch(authProvider),
  
  // Work to execute - full ref available
  run: (ref) async {
    final isAuth = await ref.watch(authProvider.future);
    if (isAuth) {
      // ref.watch keeps provider alive, but won't show splash when it changes
      await ref.watch(profileProvider.future);
    }
  },
),
```

**Key behavior:** Only `trigger` changes show splash. Using `ref.watch()` in `run` keeps providers alive and re-runs silently without splash.

## Retry Support

When a task fails, the splash screen shows an error with a retry button. Use
`ref.onDispose()` to register cleanup that invalidates providers on retry:

```dart
tasks: [
  (ref) async {
    // Register cleanup FIRST - before any async work
    ref.onDispose(() {
      ref.invalidate(myProvider);
    });

    // Then do the work
    await ref.read(myProvider.future);
  },
],
```

**Why this works:** When retry is triggered, the splash provider is invalidated,
which calls all registered `onDispose` callbacks.

## Example Application
A full example lives in `example/lib/main.dart`. Run it with:

```bash
flutter run example
```

## Contributing
Issues and pull requests are welcome! Please open an issue if you run into a
problem or have ideas for new capabilities.
