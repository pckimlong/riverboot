import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverboot/riverboot.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Easy Inventory bootstrap graph settles without retained dependency loops',
    () async {
      final authStateProvider = NotifierProvider<_AuthState, bool>(
        _AuthState.new,
      );
      final currentOrgIdProvider = NotifierProvider<_CurrentOrgId, String?>(
        _CurrentOrgId.new,
      );

      var orgListRuns = 0;
      var currentOrgRuns = 0;
      var permissionsRuns = 0;
      var preferencesRuns = 0;
      var locationRuns = 0;

      final orgListProvider = FutureProvider.autoDispose<List<String>>((
        ref,
      ) async {
        orgListRuns++;
        return ref.watch(authStateProvider) ? ['org-a', 'org-b'] : [];
      });
      final currentOrgProvider = FutureProvider.autoDispose<String?>((
        ref,
      ) async {
        currentOrgRuns++;
        return ref.watch(currentOrgIdProvider);
      });
      final permissionsProvider = Provider.autoDispose<Set<String>>((ref) {
        permissionsRuns++;
        final org = ref.watch(currentOrgProvider).value;
        return org == null ? const {} : {'read:$org'};
      });
      final preferencesProvider = FutureProvider.autoDispose<String?>((
        ref,
      ) async {
        preferencesRuns++;
        return ref.watch(currentOrgIdProvider);
      });
      final locationListProvider = FutureProvider.autoDispose<List<String>>((
        ref,
      ) async {
        locationRuns++;
        final org = ref.watch(currentOrgIdProvider);
        return org == null ? [] : ['$org-location'];
      });

      var taskRuns = 0;
      final config = SplashConfig(
        splashBuilder: (_, _) => const SizedBox.shrink(),
        tasks: [
          (ref) async {
            taskRuns++;
            final isAuthenticated = ref.watchForSplash(authStateProvider);
            final selectedOrgId = ref.watchForSplash(currentOrgIdProvider);
            if (!isAuthenticated) return;

            // Mirrors Easy Inventory's listenNothing/read-future split. These
            // providers stay active but do not become task dependencies.
            final orgs = await ref.wait(orgListProvider.future);
            if (!ref.mounted || orgs.isEmpty) return;

            if (selectedOrgId == null) {
              ref.read(currentOrgIdProvider.notifier).select(orgs.first);
              if (!ref.mounted) return;
            }

            await ref.wait(currentOrgProvider.future);
            if (!ref.mounted) return;
            ref.retain(permissionsProvider);
            await ref.wait(preferencesProvider.future);
            if (!ref.mounted) return;
            await ref.wait(locationListProvider.future);
          },
        ],
      );
      final container = ProviderContainer.test(
        overrides: [splashConfigProvider.overrideWithValue(config)],
      );
      final subscription = container.listen(splashTasksProvider, (_, _) {});

      await container.read(splashTasksProvider.future);
      await _pumpGraph(container);

      // Selecting the initial org is an intentional reactive boundary, so the
      // task runs once more. The dependent preload graph must then settle.
      expect(container.read(currentOrgIdProvider), 'org-a');
      expect(taskRuns, 2);
      expect(orgListRuns, greaterThanOrEqualTo(1));
      expect(currentOrgRuns, greaterThanOrEqualTo(1));
      expect(permissionsRuns, greaterThanOrEqualTo(1));
      expect(preferencesRuns, greaterThanOrEqualTo(1));
      expect(locationRuns, greaterThanOrEqualTo(1));

      final runsAfterBootstrap = taskRuns;
      final currentOrgRunsBeforeRefresh = currentOrgRuns;
      final permissionsRunsBeforeRefresh = permissionsRuns;

      // A retained hydration provider may refresh its downstream providers,
      // but it must not rerun the bootstrap task or form a refresh cycle.
      container.invalidate(currentOrgProvider);
      await _pumpGraph(container);

      expect(currentOrgRuns, greaterThan(currentOrgRunsBeforeRefresh));
      expect(permissionsRuns, greaterThan(permissionsRunsBeforeRefresh));
      expect(taskRuns, runsAfterBootstrap);

      // Changing the explicit org boundary reruns exactly once, even though
      // preferences, locations, current-org details, and permissions refresh.
      container.read(currentOrgIdProvider.notifier).select('org-b');
      await _pumpGraph(container);

      expect(taskRuns, runsAfterBootstrap + 1);
      expect(container.read(permissionsProvider), contains('read:org-b'));
      expect(await container.read(locationListProvider.future), [
        'org-b-location',
      ]);

      subscription.close();
    },
  );
}

Future<void> _pumpGraph(ProviderContainer container) async {
  for (var i = 0; i < 10; i++) {
    await container.pump();
  }
  await container.read(splashTasksProvider.future);
}

class _AuthState extends Notifier<bool> {
  @override
  bool build() => true;
}

class _CurrentOrgId extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? id) => state = id;
}
