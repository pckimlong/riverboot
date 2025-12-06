import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverboot/riverboot.dart';

final _authenticatedProvider = FutureProvider<bool>((ref) async {
  await Future.delayed(const Duration(seconds: 1));
  return true;
});

final _profileProvider = FutureProvider<String>((ref) async {
  await Future.delayed(const Duration(milliseconds: 500));
  return 'Riverboot User';
});

void main() {
  Riverboot.initialize(
    application: const _RiverbootExampleApp(),
    retry: (int retryCount, Object error) => Duration(seconds: retryCount),
    splashConfig: SplashConfig(
      minimumDuration: const Duration(seconds: 1),
      splashBuilder: (error, retry) {
        return Scaffold(
          body: Center(
            child: error == null
                ? const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Booting application...'),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Failed to start:\n${error.error}'),
                      const SizedBox(height: 16),
                      ElevatedButton(onPressed: retry, child: const Text('Retry')),
                    ],
                  ),
          ),
        );
      },
      // One-time tasks - run once at app start
      tasks: [
        (ref) async {
          // Initialize services, load config, etc.
          await Future.delayed(const Duration(milliseconds: 300));
        },
      ],
      // Reactive task - re-runs when trigger changes, shows splash
      reactiveTask: ReactiveTask(
        // Only authProvider changes trigger re-run and show splash
        trigger: (ref) => ref.watch(_authenticatedProvider),
        // Work to execute - full ref available
        // Using ref.watch here won't show splash (only trigger changes do)
        run: (ref) async {
          final authenticated = await ref.watch(_authenticatedProvider.future);
          if (authenticated) {
            // This keeps profileProvider alive, but won't show splash when it changes
            await ref.watch(_profileProvider.future);
          }
        },
      ),
    ),
  );
}

class _RiverbootExampleApp extends StatelessWidget {
  const _RiverbootExampleApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Riverboot Example',
      theme: ThemeData(primarySwatch: Colors.indigo),
      builder: (context, child) => SplashBuilder(child: child ?? const SizedBox.shrink()),
      home: const _HomePage(),
    );
  }
}

class _HomePage extends ConsumerWidget {
  const _HomePage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(_profileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Riverboot')),
      body: Center(
        child: profile.when(
          data: (name) => Text('Hello, $name!'),
          loading: () => const CircularProgressIndicator(),
          error: (error, stack) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Could not load profile: $error'),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => ref.invalidate(_profileProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
