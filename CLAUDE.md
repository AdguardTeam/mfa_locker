# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MFA Locker is a secure encrypted key-value storage library for Dart/Flutter with multi-factor authentication support (password + biometrics). The library provides AES-GCM encryption, PBKDF2 key derivation, HMAC integrity verification, and biometric authentication via TPM/Secure Enclave.

**Two-project structure:** The root is the `locker` library (Dart package). The `example/` directory is a separate Flutter app (`mfa_demo`) that depends on the library via path. Each has its own `pubspec.yaml`, `analysis_options.yaml`, and dependencies.

## Build & Development Commands

This project uses FVM (Flutter Version Management). The locked version is in `.ci-flutter-version`.

```bash
# Setup FVM
fvm install && fvm use

# Initialize project (clean + code generation, from example/)
cd example && make init

# Quick init without clean (faster)
cd example && make in

# Code generation only (Freezed models, from example/)
cd example && make gen

# Run all tests (library)
fvm flutter test

# Run a single test file
fvm flutter test test/locker/mfa_locker_test.dart

# Run tests matching a name pattern
fvm flutter test --name "should unlock"

# Analyze code
fvm flutter analyze --fatal-warnings --fatal-infos

# Format code (120 char line width, configured in analysis_options.yaml)
fvm dart format . --line-length 120

# Build APK (from example/, flavors: dev, prod, stage)
cd example && make apk FLAVOR=dev

# CI builds (from example/)
make ci-build-ios ENV_FILE=config/dev.env
make ci-build-macos ENV_FILE=config/dev.env
make ci-build-windows FLAVOR=dev
make ci-build-msix FLAVOR=dev
```

## MCP Tools (Preferred)

**Use MCP tools instead of shell commands for Dart/Flutter operations when available.**

| Operation | MCP Tool | Shell Equivalent |
|-----------|----------|------------------|
| Get deps | `mcp__dart__pub(command: "get")` | `flutter pub get` |
| Add package | `mcp__dart__pub(command: "add", packageName: "pkg")` | `flutter pub add pkg` |
| Fix | `mcp__dart__dart_fix()` | `dart fix --apply` |
| Format | `mcp__dart__dart_format()` | `dart format .` |
| Analyze | `mcp__dart__analyze_files()` | `flutter analyze` |
| Run tests | `mcp__dart__run_tests()` | `flutter test` |
| Search pub.dev | `mcp__dart__pub_dev_search(query: "...")` | Manual search |

**When shell is acceptable:**
- FVM commands: `fvm install`, `fvm use`
- Build commands: `make init`, `make gen`, `make apk`
- Git operations
- Build runner: `flutter pub run build_runner build`

## Architecture

```
UI Layer (Widgets) → BLoC Layer (ActionBloc) → Repository Layer → MFALocker Library
```

### Layer Responsibilities

- **UI**: Collect input, display states, dispatch events to BLoC
- **BLoC**: Handle events, emit states, dispatch actions (side effects), call repository
- **Repository**: Create cipher functions (PasswordCipherFunc/BioCipherFunc), call MFALocker, handle exceptions
- **Library (lib/)**: Core encryption, storage, and security operations

### Key Patterns

- **ActionBloc**: BLoC + explicit side effects (Actions). Events trigger state changes and optional actions.
- **Freezed**: All models use Freezed for immutability. Run `make gen` after model changes.
- **Single source of truth**: BLoC holds UI state, MFALocker holds data state.

## Project Structure

```
lib/                    # Core library (package: locker)
├── locker/            # MFALocker class and Locker interface
├── security/          # Cipher functions, biometric config, exceptions
├── storage/           # Encrypted storage implementation, exceptions
├── erasable/          # Secure memory management (ErasableByteArray)
└── utils/             # Utilities (crypto, extensions, sync)
packages/
└── secure_mnemonic/   # Platform channel plugin for biometric key management
                       # (iOS, macOS, Android, Windows native code)
example/               # Demo Flutter app (mfa_demo) — separate pubspec
├── lib/features/      # Feature modules (locker, settings)
├── lib/di/            # Dependency injection
└── Makefile           # Build commands
test/                  # Unit tests (mocktail for mocking)
```

## Exception Hierarchy

The library uses typed exceptions — don't wrap them in custom exceptions, let them propagate:

- **`StorageException`** with `StorageExceptionType`: `notInitialized`, `alreadyInitialized`, `invalidStorage`, `entryNotFound`, `other`
- **`BiometricException`** with `BiometricExceptionType`: `cancel`, `failure`, `keyNotFound`, `keyAlreadyExists`, `notAvailable`, `notConfigured`
- **`DecryptFailedException`** — thrown when password/cipher is incorrect

## Test Patterns

Tests use **mocktail** for mocking and follow Arrange/Act/Assert structure:

```dart
test('should do something', () async {
  // Arrange
  when(() => mock.method()).thenAnswer((_) async => result);

  // Act
  await sut.operation();

  // Assert
  expect(sut.state, expected);
  verify(() => mock.method()).called(1);
});
```

- Test helpers use `part` files (e.g., `mfa_locker_test_helpers.dart` is `part` of the test file)
- Mocks are in `test/mocks/` directory, named `Mock` + class (e.g., `MockEncryptedStorage`)
- `registerFallbackValue()` in `setUpAll` for mocktail value matchers
- `tearDown` disposes the SUT (system under test)

## Code Style Rules

For complete coding standards and development practices, see [`docs/conventions.md`](docs/conventions.md).

### Mandatory Syntax
- **Trailing commas** on multi-line calls
- **Curly braces** for all control flow (no single-line `if (!mounted) return;`)
- **Arrow syntax** for one-liners
- **for-in** over indexed loops
- **const** where possible
- **Single quotes** for strings (`prefer_single_quotes` enabled)
- **Check `context.mounted`** before navigation/dialogs

### Naming Conventions
- Interfaces: no prefix (`LockerRepository`)
- Implementations: `Impl` suffix (`LockerRepositoryImpl`)
- Events: past tense (`UnlockRequested`, `EntryAdded`)
- Actions: descriptive (`ShowErrorAction`)
- Private fields/methods: `_` prefix
- TODO comments: `// TODO(firstLetter.lastName): Description`

### File Organization Rules
- **One primary type per file** — file name must match the primary class/extension name
- **Extensions in separate files** — named after the extension (e.g., `LockerBlocBiometricStream` → `locker_bloc_biometric_stream.dart`)
- **Sealed classes separate from widgets** — extract to dedicated files (e.g., `biometric_auth_result.dart`)
- **Never ignore linter rules** — fix the underlying issue instead of adding `// ignore` comments

### Class Member Order
1. Static constants (public, then private)
2. Constructor fields (public, then private)
3. Constructor
4. Other private fields
5. Public methods
6. Private methods

### Widget Lifecycle Order
`initState` → `didUpdateWidget` → `didChangeDependencies` → `build` → `dispose` → custom methods

### Dependencies
- Exact versions (no `^` caret)
- Alphabetical order (Flutter SDK first)

## Core Principles

From `docs/vision.md`:
- **KISS** — Simplest solution that works
- **No overengineering** — Extend existing patterns, don't create new abstractions
- **Single responsibility** — Each component does one thing
- **Clarity over cleverness** — Readable code wins

### Anti-patterns to Avoid
- Creating separate BLoCs for related features (extend existing BLoC instead)
- Wrapping library exceptions in custom exceptions (let them propagate)
- Storing state in multiple places (single source of truth)
- Creating abstract factories or strategy patterns for simple instantiation
- Skipping `context.mounted` checks before async UI operations
- Ignoring linter rules with `// ignore` comments (fix the issue instead)
- Creating duplicate extensions for nullable/non-nullable types (use nullable extension for both)

## Flutter Lifecycle & Timing Patterns

### Prefer System Events Over Timers

Always use deterministic Flutter system events instead of arbitrary delays or timers:

| Problem | Bad | Good |
|---------|-----|------|
| Wait for bottom sheet animation | `Future.delayed(Duration(milliseconds: 400))` | `ModalRoute.of(context).animation` status listener |
| Clear state after biometric dialog closes | `Timer(Duration(milliseconds: 500), clearFlag)` | `AppLifecycleState.resumed` event |
| Wait for widget to be ready | `Future.delayed(...)` | `WidgetsBinding.instance.addPostFrameCallback` |

### Biometric Operation State Machine

The app uses a state machine to prevent vault locking during biometric operations:

```dart
enum BiometricOperationState {
  idle,          // No operation, locking allowed
  inProgress,    // System biometric dialog may be showing, locking blocked
  awaitingResume // Operation done, waiting for app lifecycle resume
}
```

**Flow:**
1. Before biometric call → set `inProgress`
2. After biometric call (in `finally` block) → set `awaitingResume`
3. On `AppLifecycleState.resumed` → set `idle`

This handles the lifecycle changes caused by system biometric dialogs (resumed → inactive → resumed).

### Animation-Aware Bottom Sheets

Use `AnimationAwareBottomSheet` to detect when modal animations complete:

```dart
showModalBottomSheet(
  context: context,
  builder: (context) => AnimationAwareBottomSheet(
    onAnimationComplete: () {
      // Safe to trigger biometric or other actions here
      triggerBiometric();
    },
    child: MyContent(),
  ),
);
```

The widget listens to `ModalRoute.of(context).animation` and fires callback when `AnimationStatus.completed`.

### Full-Screen Transitions (macOS)

macOS full-screen transitions trigger rapid lifecycle changes. Use `FullscreenListener` with state machine:

```dart
enum FullscreenState { normal, transitioning }
```

This prevents spurious lock events during the transition. See `docs/flutter-lifecycle.md` for details.
