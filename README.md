# Riverboot

Riverboot bootstraps Flutter/Riverpod applications by orchestrating the work that
must happen before your UI goes live. Configure a splash experience once, plug
in tasks, and Riverboot will keep the screen up until the app is ready or an
error occurs.

## Highlights
- **Turn-key splash orchestration** – centralise initialization logic, display
  progress, and surface errors with a single builder.
- **Isolated startup tasks** – gate initial readiness and rerun only the task
  whose declared dependency changed.
- **Task-scoped provider policies** – choose whether a dependency reload is
  silent, blocking, or retained without rerunning its task.
- **Reactive task dependencies** – re-run when explicitly watched providers
  change, with per-dependency splash behavior.
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
      
      tasks: [
        (ref) async {
          await initializeServices();

          final authenticated = await ref.watchForSplash(authProvider.future);
          if (authenticated) {
            ref.invalidateOnRetry(profileProvider);
            await ref.wait(profileProvider.future);
          }
        },
      ],
    ),
  );
}
```

Add `SplashBuilder` to your `MaterialApp` (or `CupertinoApp`) `builder` so the
splash UI can take over while tasks are in-flight.

## Task-scoped provider policies

Every configured task has an isolated provider lifecycle and receives a
`SplashTaskRef`:

```dart
tasks: [
  (ref) async {
    // A later auth change reruns this task and restores splash.
    final authenticated = await ref.watchForSplash(authProvider.future);

    if (authenticated) {
      // Required initially and kept alive, but later profile refreshes do not
      // rerun this task or restore splash.
      ref.invalidateOnRetry(profileProvider);
      await ref.wait(profileProvider.future);

      // Start and retain background data without awaiting it.
      ref.retain(productListProvider);
    }
  },
],
```

| Method | Later provider change | Splash behavior |
|---|---|---|
| `watch` | Reruns only the owning task | Keeps app visible |
| `watchForSplash` | Reruns only the owning task | Restores splash |
| `wait` | Does not rerun the task | Awaits initial/current value only |
| `retain` | Does not rerun the task | Initializes and keeps provider alive |
| `read` | Does not rerun the task | One-shot read without retention |

Use `invalidateOnRetry(provider)` when a failed provider caches its error and
must be invalidated before the task is attempted again.

## Retry Support

When a task fails, the splash screen shows an error with a retry button.
Register providers whose cached state must be invalidated before retry:

```dart
tasks: [
  (ref) async {
    ref.invalidateOnRetry(myProvider);
    await ref.wait(myProvider.future);
  },
],
```

Riverboot invalidates only the failed task's registered dependencies before
executing that task again.

## Example Application
A full example lives in `example/lib/main.dart`. Run it with:

```bash
flutter run example
```

## Contributing
Issues and pull requests are welcome! Please open an issue if you run into a
problem or have ideas for new capabilities.
