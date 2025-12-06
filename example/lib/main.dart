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
      oneTimeTasks: [
        (ref) async {
          await Future.delayed(const Duration(milliseconds: 300));
        },
      ],
      reactiveTasks: [
        task<bool>(
          watch: (ref) => ref.watch(_authenticatedProvider.future),
          execute: (ref, authenticated) async {
            if (authenticated) {
              await ref.read(_profileProvider.future);
            }
          },
        ),
      ],
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
