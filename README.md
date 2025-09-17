# Riverboot

Riverboot bootstraps Flutter/Riverpod applications by orchestrating the work that
must happen before your UI goes live. Configure a splash experience once, plug
in one-time/ reactive tasks, and Riverboot will keep the screen up until the
app is ready or an error occurs.

## Highlights
- **Turn-key splash orchestration** – centralise initialization logic, display
  progress, and surface errors with a single builder.
- **One-time tasks with parallel execution** – run setup steps either
  sequentially or concurrently with a single flag.
- **Reactive tasks** – respond to authentication changes (or any provider
  update) by queueing follow-up work while the splash remains visible.
- **Minimum splash duration** – keep animations on screen for a set amount of
  time even when work completes instantly.

## Getting Started
Create your `main.dart` and hand Riverboot the application widget together with
its splash configuration:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverboot/riverboot.dart';

final authenticatedProvider = FutureProvider<bool>((ref) async {
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
      oneTimeTasks: [
        (ref) async {
          // Seed caches, warm services, etc.
          await Future.delayed(const Duration(milliseconds: 300));
        },
      ],
      reactiveTasks: [
        task<bool>(
          watch: (ref) => ref.watch(authenticatedProvider.future),
          execute: (ref, authenticated) async {
            if (authenticated) {
              await ref.read(profileProvider.future);
            }
          },
        ),
      ],
    ),
  );
}
```

Add `SplashBuilder` to your `MaterialApp` (or `CupertinoApp`) `builder` so the
splash UI can take over while tasks are in-flight.

## Enhanced Logging

Riverboot includes comprehensive logging capabilities to help debug initialization issues and track task performance:

```dart
// Enable enhanced logging for all operations
Riverboot.initialize(
  application: MyApp(),
  loggingConfig: RiverbootLoggingConfig.enhanced,
  // ...
);

// Custom logging configuration
Riverboot.initialize(
  application: MyApp(),
  loggingConfig: RiverbootLoggingConfig(
    logTaskStart: true,
    logTaskErrors: true,
    logTaskTiming: true,
    customLogger: (message, {error, stackTrace}) {
      // Your custom logging implementation
      myLogger.info(message);
    },
  ),
  // ...
);

// Per-splash task logging
SplashConfig(
  splashBuilder: (error, retry) => MySplashScreen(),
  taskLoggingConfig: RiverbootLoggingConfig.enhanced,
  oneTimeTasks: [...],
  reactiveTasks: [...],
)
```

Available logging options:
- `logTaskStart` - Log when tasks begin execution
- `logTaskCompletion` - Log when tasks complete successfully
- `logTaskErrors` - Log task failures with stack traces
- `logTaskTiming` - Log execution times for performance monitoring
- `customLogger` - Provide your own logging function

## Reactive Tasks
Reactive tasks are executed in parallel. Every task lives in its own provider,
so when multiple `watch` futures resolve simultaneously, their corresponding
`execute` callbacks run concurrently without blocking each other.

Use them to express chains such as “once the authentication state resolves,
fetch the user profile.” Riverboot keeps the splash visible until all reactive
callbacks finish, and retries can re-trigger those providers on demand.

## Example Application
A full example lives in `example/lib/main.dart`. Run it with:

```bash
flutter run example
```

## Contributing
Issues and pull requests are welcome! Please open an issue if you run into a
problem or have ideas for new capabilities.
