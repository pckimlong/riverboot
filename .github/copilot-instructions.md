# Riverboot Flutter Package

Riverboot is a Flutter package that bootstraps Flutter/Riverpod applications by orchestrating splash screens and initialization tasks. This is a LIBRARY PACKAGE, not an application. Always reference these instructions first and fallback to search or bash commands only when you encounter unexpected information that does not match the info here.

## Working Effectively

Install Flutter and bootstrap the repository:
- Install Flutter stable channel (version 3.27+ recommended): Use GitHub Actions setup `uses: subosito/flutter-action@v2` or manually install
- `flutter doctor` -- verify installation, takes 10-30 seconds. NEVER CANCEL. Set timeout to 60+ seconds.
- `flutter pub get` -- downloads dependencies (flutter_riverpod ^3.0.0), takes 10-45 seconds. NEVER CANCEL. Set timeout to 120+ seconds.
- `flutter analyze` -- runs static analysis with flutter_lints, takes 5-20 seconds. NEVER CANCEL. Set timeout to 60+ seconds.
- `flutter test` -- runs test suite (2 tests in splash_task_test.dart), takes 10-90 seconds. NEVER CANCEL. Set timeout to 180+ seconds.

## Dependencies and Environment
- **Flutter SDK**: >=1.17.0 (recommend 3.27+ stable)
- **Dart SDK**: ^3.9.2 (automatically included with Flutter)
- **Main dependency**: flutter_riverpod ^3.0.0 for state management
- **Dev dependencies**: flutter_test (SDK), flutter_lints ^5.0.0 for code quality
- **Platform support**: All platforms (iOS, Android, Web, Desktop) - this is a pure Dart/Flutter package

## Build Commands and Timing
Standard Flutter package commands (ALWAYS use long timeouts):
- `flutter pub get` -- install dependencies, 10-45 seconds on first run
- `dart format .` -- format code to project style, 1-5 seconds
- `flutter analyze` -- static analysis with linting, 5-20 seconds
- `flutter test` -- run test suite (currently 2 tests), 10-90 seconds  
- `flutter test --coverage` -- run tests with coverage, 15-120 seconds
- `flutter pub deps` -- show dependency tree, 1-10 seconds
- `flutter pub publish --dry-run` -- validate package for publishing, 5-30 seconds

## Example Application
ALWAYS test functionality using the example application:
- `cd example`
- `flutter pub get` -- downloads example dependencies, takes 10-45 seconds. NEVER CANCEL. Set timeout to 120+ seconds.
- `flutter run -d chrome` -- builds and runs example web app, takes 45-180 seconds for first build. NEVER CANCEL. Set timeout to 300+ seconds for initial builds.
- `flutter run -d linux` -- builds and runs example desktop app (if on Linux), takes 60-240 seconds. NEVER CANCEL. Set timeout to 360+ seconds.

## Critical Validation Scenarios
ALWAYS manually validate functionality after any changes:
1. **Basic Splash Flow**: Launch example app, verify splash screen shows "Booting application..." with loading spinner
2. **Successful Boot**: Confirm transition to main screen showing "Hello, Riverboot User!" after ~1-2 seconds
3. **Error Handling**: Modify _authenticatedProvider in example/lib/main.dart to throw an error, verify error display and retry button works
4. **Reactive Tasks**: Check that profile loading happens after authentication completes
5. **Minimum Duration**: Verify splash stays visible for at least the configured minimum duration (1 second in example)

NEVER skip these validation steps - they ensure core functionality works correctly.

## Code Structure and Key Files
The package has a focused, clean architecture:
- `lib/riverboot.dart` - **Main export file** (only 2 lines, exports src/src.dart)
- `lib/src/src.dart` - **Internal exports/imports** (uses part/part of pattern)
- `lib/src/bootstrap.dart` - **Core Riverboot class** with initialize() method and container setup
- `lib/src/splash_builder.dart` - **SplashBuilder widget** with reactive task orchestration  
- `lib/src/splash_task.dart` - **Task management**: SplashConfig, ReactiveSplashTask, providers
- `test/splash_task_test.dart` - **Test suite** for timing and task behavior validation
- `example/lib/main.dart` - **Complete example app** demonstrating all features
- `.github/workflows/ci.yml` - **CI pipeline** (pub get → format check → analyze → test)
- `tool/bump_version.py` - **Release automation** for semantic versioning

## Core Classes and API
**Riverboot.initialize()** - Main entry point with parameters:
- `application`: Flutter app widget (MaterialApp/CupertinoApp) 
- `splashConfig`: SplashConfig with tasks and UI builder
- `overrides`: Riverpod provider overrides
- `onError`: Error handler callback

**SplashConfig** - Configuration object with:
- `splashBuilder`: Widget builder function (error, retry) → Widget
- `oneTimeTasks`: List of startup tasks (sequential or parallel)
- `reactiveTasks`: List of reactive tasks triggered by provider changes
- `minimumDuration`: Minimum time to show splash (default Duration.zero)

**SplashBuilder** - Widget that orchestrates splash/content switching based on task states

## Building and Testing
Standard Flutter package workflow:
- `flutter pub get` -- install dependencies (required after any pubspec.yaml changes)
- `dart format .` -- format code according to analysis_options.yaml style rules
- `flutter analyze` -- static analysis (must pass for CI, uses flutter_lints)
- `flutter test` -- run test suite (splash_task_test.dart with timing and reactive task tests)
- `flutter test --coverage` -- generate coverage report (coverage/lcov.info)

## Development Workflow
When making changes to the package:
1. **Setup**: `flutter pub get` (after pulling changes or modifying pubspec.yaml)
2. **Develop**: Make code changes in lib/src/ files (remember: they use part/part of)
3. **Test**: Update tests in test/ if adding new behavior or fixing bugs
4. **Validate**: Test changes using example app: `cd example && flutter run -d chrome`
5. **Quality**: Run `dart format .` and `flutter analyze` (must pass for CI)
6. **Test**: Run `flutter test` to ensure all tests pass
7. **Commit**: Commit changes (CI will run the same checks)

## Important Development Notes
- **Package type**: This is a LIBRARY package, not a Flutter application
- **Code organization**: Uses Dart's part/part of system - all src/ files are parts of src.dart
- **State management**: Heavy use of Riverpod providers (_splashConfigProvider, _oneTimeSplashTasksProvider, etc.)
- **Task types**: Supports both one-time (startup) and reactive (provider-watching) tasks  
- **Error handling**: Built-in retry functionality with user-defined error UI
- **Testing approach**: Focus on timing behavior and task orchestration
- **CI requirements**: Must pass format check, analyzer, and all tests

## CI/CD Pipeline
The GitHub Actions CI pipeline (.github/workflows/ci.yml) runs on PRs to dev/main:
1. **Checkout**: Repository checkout with actions/checkout@v4
2. **Flutter Setup**: Install Flutter stable with subosito/flutter-action@v2  
3. **Dependencies**: Run `flutter pub get` (10-45 seconds)
4. **Format Check**: Run `dart format --output=none --set-exit-if-changed .` (MUST pass)
5. **Analysis**: Run `flutter analyze` (must have zero issues)
6. **Testing**: Run `flutter test` (all tests must pass)

**Release Pipeline** (.github/workflows/release.yml) on main branch pushes:
- Runs full test suite first
- Uses tool/bump_version.py for semantic versioning
- Creates git tags and GitHub releases automatically
- Handles commit message parsing for version bumps (feat: minor, fix: patch, breaking: major)

ALWAYS run `dart format .` and `flutter analyze` locally before committing to ensure CI passes.

## Development Workflow
When making changes to the package:
1. **Setup**: `flutter pub get` (after pulling changes or modifying pubspec.yaml)
2. **Develop**: Make code changes in lib/src/ files (remember: they use part/part of)
3. **Test**: Update tests in test/ if adding new behavior or fixing bugs
4. **Validate**: Test changes using example app: `cd example && flutter run -d chrome`
5. **Quality**: Run `dart format .` and `flutter analyze` (must pass for CI)
6. **Test**: Run `flutter test` to ensure all tests pass
7. **Commit**: Commit changes (CI will run the same checks)

## Package Usage Pattern
Typical integration in a Flutter app main.dart:
```dart
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
      splashBuilder: (error, retry) => error == null 
        ? LoadingWidget() 
        : ErrorWidget(error: error, onRetry: retry),
      oneTimeTasks: [
        (ref) async { await initializeServices(); },
      ],
      reactiveTasks: [
        task<bool>(
          watch: (ref) => ref.watch(authProvider.future),
          execute: (ref, authenticated) async {
            if (authenticated) await ref.read(userProvider.future);
          },
        ),
      ],
    ),
  );
}
```

## Key Development Notes
- This is a PACKAGE, not an application - focus on library functionality
- Uses part/part of pattern - all src files are parts of src.dart
- Heavy use of Riverpod providers for state management
- Splash system supports both one-time and reactive tasks
- Error handling includes retry functionality
- Test coverage focuses on task orchestration and timing
- Example app in example/ directory demonstrates all features

## Timing Expectations and Critical Warnings
Based on typical Flutter package performance (ALWAYS use generous timeouts):
- `flutter pub get`: 10-45 seconds (first run), 3-15 seconds (subsequent)
- `flutter analyze`: 5-20 seconds (depends on analysis_options.yaml complexity)  
- `flutter test`: 10-90 seconds (includes test startup and 2 test cases)
- `flutter run` (example): 45-180 seconds first build, 5-30 seconds subsequent hot reloads
- `dart format .`: 1-5 seconds (fast, but include buffer for large codebases)

**NEVER CANCEL** any of these operations. Set timeouts generously:
- Use 120+ seconds for pub get, 60+ seconds for analyze, 180+ seconds for tests
- Use 300+ seconds for flutter run first builds, 60+ seconds for subsequent builds

## Common Issues and Solutions
- **`flutter analyze` fails**: Check dart format compliance first, then fix import issues
- **Tests fail**: Ensure Flutter test framework is properly installed and dependencies are current
- **Example won't run**: Verify Flutter supports your target platform (try chrome: `flutter run -d chrome`)
- **Pub get fails**: Check internet connectivity and pubspec.yaml syntax
- **Build fails**: Clear flutter cache: `flutter clean && flutter pub get`
- **Hot reload issues**: Restart app if hot reload becomes unreliable after many changes

## Release Process
The repository uses automated semantic versioning:
- Releases triggered automatically on main branch pushes (if commits are release-worthy)
- Version bumping handled by tool/bump_version.py based on conventional commits
- Commit message parsing: `feat:` (minor), `fix:` (patch), `BREAKING CHANGE:` (major)
- Creates git tags and GitHub releases automatically with changelog
- ALWAYS run full test suite before any commits to main branch

## Quick Reference Commands
```bash
# Setup and basic validation
flutter pub get && dart format . && flutter analyze && flutter test

# Run example app for testing
cd example && flutter pub get && flutter run -d chrome

# Check package is publishable  
flutter pub publish --dry-run

# Full CI simulation
dart format --output=none --set-exit-if-changed . && flutter analyze && flutter test
```