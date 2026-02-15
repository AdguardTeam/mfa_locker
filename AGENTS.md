# AGENTS.md

This file provides LLM agents and human contributors with project context,
structure, build commands, contribution rules, and code guidelines.

## Project Overview

MFA Locker is a secure encrypted key-value storage library for Dart/Flutter with multi-factor authentication support (password + biometrics). The library provides AES-GCM encryption, PBKDF2 key derivation, HMAC integrity verification, and biometric authentication via TPM/Secure Enclave.

**Two-project structure:** The root is the `locker` library (Dart package). The `example/` directory is a separate Flutter app (`mfa_demo`) that depends on the library via path. Each has its own `pubspec.yaml`, `analysis_options.yaml`, and dependencies.

Target platforms: iOS, macOS, Android, Windows.

## Technical Context

| Field | Value |
|-------|-------|
| **Language** | Dart >=3.5.0 (root library), >=3.9.0 (example app) |
| **Flutter** | >=3.35.0, FVM locked at 3.35.1 (`.ci-flutter-version`) |
| **Architecture** | UI (Widgets) -> BLoC (ActionBloc) -> Repository -> MFALocker Library |
| **State Management** | `flutter_bloc` 8.1.6, `action_bloc` (local package), `freezed` 3.2.0 |
| **Testing** | `mocktail` 1.0.3 (NOT mockito), `flutter_test`, `test` 1.26.2 |
| **Code Generation** | `build_runner` 2.7.0, `freezed` 3.2.0, `freezed_annotation` 3.1.0 |
| **Linting** | `lints` 3.0.0 (root), `flutter_lints` 6.0.0 + DCM (example) |
| **Logging** | `adguard_logger` (git dependency) |
| **DI** | Manual constructor injection + factory classes + InheritedWidget (DependencyScope) |
| **Platforms** | iOS, macOS, Android, Windows |
| **Project Type** | Dart library (`locker`) + Flutter demo app (`mfa_demo`) with two `pubspec.yaml` |
| **Flavors** | dev, stage, prod (via `--dart-define-from-file=config/{flavor}.env`) |
| **Formatter** | `page_width: 120`, `trailing_commas: preserve` |
| **Crypto** | `cryptography` 2.7.0 (AES-GCM, PBKDF2, HMAC) |
| **Reactive** | `rxdart` 0.28.0 |
| **Concurrency** | `synchronized` 3.4.0 |

## Project Structure

```
mfa_locker/                     # Root: locker library (Dart package)
├── lib/                        # Core library (package: locker)
│   ├── locker/                 # MFALocker class and Locker interface
│   ├── security/               # Cipher functions, biometric config, exceptions
│   ├── storage/                # Encrypted storage implementation, exceptions
│   ├── erasable/               # Secure memory management (ErasableByteArray)
│   ├── utils/                  # Utilities (crypto, extensions, sync)
│   └── debug/                  # Debug utilities
├── packages/                   # Root-level platform plugins
│   ├── biometric_cipher/       # Platform channel plugin for TPM/Secure Enclave biometrics
│   │                           # (iOS, macOS, Android, Windows native code)
│   └── secure_mnemonic/        # Mnemonic key storage plugin
├── test/                       # Unit tests (mocktail for mocking)
│   ├── locker/                 # MFALocker tests
│   ├── mocks/                  # Mock classes (MockEncryptedStorage, etc.)
│   ├── storage/                # Storage tests
│   └── utils/                  # Utility tests
├── example/                    # Demo Flutter app (mfa_demo) — separate pubspec
│   ├── lib/
│   │   ├── main.dart
│   │   ├── core/               # Shared utilities
│   │   │   ├── constants/      # App constants
│   │   │   ├── data/storages/  # Settings persistence
│   │   │   ├── extensions/     # Context extensions
│   │   │   └── utils/          # Utility functions
│   │   ├── di/                 # Dependency injection (DependencyScope, factories)
│   │   └── features/
│   │       ├── locker/         # Main locker feature
│   │       │   ├── bloc/       # LockerBloc, events, state, actions
│   │       │   ├── data/       # Models, repositories
│   │       │   └── views/      # Auth screens, storage screens, widgets
│   │       └── settings/       # Settings feature (bloc, models, views)
│   ├── packages/
│   │   ├── action_bloc/        # Custom ActionBloc pattern (BLoC + side effects)
│   │   └── package_info_plus/  # Local fork of package_info_plus
│   └── Makefile                # Build commands (root Makefile proxies here)
├── docs/                       # Project documentation
│   ├── vision.md               # Architecture principles, anti-patterns
│   ├── conventions.md          # Coding standards and development practices
│   ├── guidelines.md           # AI-assisted development rules
│   ├── workflow.md             # Iteration-based development workflow
│   ├── MFA_Locker.md           # Technical encryption architecture
│   └── code-style-guide.md    # Code style reference
├── config/                     # Environment files (dev.env, prod.env, stage.env)
├── Makefile                    # Proxy — forwards all targets to example/Makefile
├── pubspec.yaml                # Root library dependencies
├── analysis_options.yaml       # Root linter config (lints package)
└── .ci-flutter-version         # FVM Flutter version lock (3.35.1)
```

## Build & Test Commands

This project uses FVM (Flutter Version Management). Flutter `3.35.1` is locked in `.ci-flutter-version`. A root `Makefile` proxies all targets to `example/Makefile`, so `make` commands work from either root or `example/`. Set `USE_FVM=false` to use system Flutter instead of FVM.

### Setup

| Command | Purpose |
|---------|---------|
| `fvm install && fvm use` | Install and activate Flutter version |
| `make init` | Full init: clean + code generation (from example/) |
| `make in` | Quick init: dependencies + code generation (no clean) |
| `make clean` | Clean build artifacts |
| `make clean-build-env` | Clean build environment and regenerate |

### Code Generation

| Command | Purpose |
|---------|---------|
| `make gen` | Run build_runner (generates `.freezed.dart` files) |
| `make g` | Alias for `make gen` |
| `make codegen` | Alias for `make gen` |

### Testing

| Command | Purpose |
|---------|---------|
| `fvm flutter test` | Run all library tests |
| `fvm flutter test test/locker/mfa_locker_test.dart` | Run specific test file |
| `fvm flutter test --name "should unlock"` | Run tests matching a name pattern |

When Dart MCP tools are available, **always prefer MCP test tools** over shell commands.

### Code Quality

| Command | Purpose |
|---------|---------|
| `make analyze` | Flutter analyzer with `--fatal-warnings --fatal-infos` |
| `make dcm-analyze` | Dart Code Metrics analysis (file naming, member ordering, BLoC rules) |
| `fvm dart format . --line-length 120` | Format code (120 char line width) |

### Building

| Command | Purpose |
|---------|---------|
| `make apk FLAVOR=dev` | Build APK (flavors: dev, prod, stage) |
| `make release-android FLAVOR=prod` | Release APK/AAB |
| `make ci-build-ios ENV_FILE=config/dev.env` | Build iOS app |
| `make ci-build-macos ENV_FILE=config/dev.env` | Build macOS app |
| `make ci-build-windows FLAVOR=dev` | Build Windows app |
| `make ci-build-msix FLAVOR=dev` | Build Windows MSIX package |

### MCP Tools

Prefer MCP tools over shell commands when available. Tool names vary by agent platform:

| Operation | Purpose | Shell Equivalent |
|-----------|---------|------------------|
| Pub get | Resolve dependencies | `flutter pub get` |
| Pub add | Add a package | `flutter pub add <pkg>` |
| Dart fix | Apply automated fixes | `dart fix --apply` |
| Dart format | Format code | `dart format .` |
| Analyze | Analyze project for errors | `flutter analyze` |
| Run tests | Run unit tests | `flutter test` |
| Pub search | Search pub.dev packages | Manual search |

### When Shell Is Acceptable

- FVM commands: `fvm install`, `fvm use`
- Build commands: `make init`, `make gen`, `make apk`
- Git operations
- Build runner: `flutter pub run build_runner build --delete-conflicting-outputs`

## Contribution Instructions

### Before Making Changes

1. Run `make in` if dependencies or generated code may be stale.
2. Read relevant docs in `docs/` (vision.md, conventions.md).
3. Follow the architecture and patterns described below.

### After Making Changes

1. Run `make analyze` — zero warnings/infos required.
2. Format changed files: `fvm dart format . --line-length 120`.
3. Run relevant tests.
4. If you added/changed Freezed models, run `make gen`.

### Dependencies

- Use **exact versions without caret** (e.g., `rxdart: 0.28.0` not `rxdart: ^0.28.0`).
- Sort alphabetically (Flutter SDK dependencies first).

### File Organization Rules

These are enforced by DCM (Dart Code Metrics) in the example app's `analysis_options.yaml` via rules like `prefer-match-file-name` and `match-class-name-pattern`.

- **One primary type per file** — file name must match the primary class/extension name.
- **Extensions in separate files** — named after the extension (e.g., `LockerBlocBiometricStream` -> `locker_bloc_biometric_stream.dart`).
- **Sealed classes separate from widgets** — extract to dedicated files (e.g., `biometric_auth_result.dart`).
- **Never ignore linter rules** — fix the underlying issue instead of adding `// ignore` comments.
- **Part files** — allowed for test helpers only (e.g., `mfa_locker_test_helpers.dart` is `part` of the test file).

## Code Guidelines

### Core Principles

- **KISS** — Simplest solution that works. No abstractions "for the future".
- **No overengineering** — Extend existing patterns, don't create new abstractions.
- **Composition over inheritance** — Build complex functionality from simple parts.
- **Immutability** — Prefer immutable data structures; use `freezed` for models and states.
- **SOLID principles** — Apply throughout the codebase.
- **Single responsibility** — Each component does one thing well.
- **Clarity over cleverness** — Readable code beats clever code.

For complete architectural principles, see `docs/vision.md`.

### Architecture

```
UI Layer (Widgets) -> BLoC Layer (ActionBloc) -> Repository Layer -> MFALocker Library
```

#### Layer Responsibilities

- **UI**: Collect input, display states, dispatch events to BLoC. Does NOT create cipher functions, call MFALocker directly, or handle library exceptions.
- **BLoC**: Handle events, emit states, dispatch actions (side effects), call repository. Does NOT create cipher functions or call MFALocker directly.
- **Repository**: Create cipher functions (`PasswordCipherFunc`/`BioCipherFunc`), call MFALocker, handle exceptions. Does NOT emit UI actions or manage UI state.
- **Library (`lib/`)**: Core encryption, storage, and security operations. Provided by the `locker` package.

#### Key Patterns

- **ActionBloc**: BLoC + explicit side effects (Actions). Events trigger state changes and optional actions.
- **Freezed**: All models use Freezed for immutability. Run `make gen` after model changes.
- **Single source of truth**: BLoC holds UI state, MFALocker holds data state.

#### Dependency Injection

Manual constructor-based DI with factory classes:

- **DependencyScope**: Root scope with InheritedWidget
- **Feature-specific factories**: Each feature has its own factory interfaces + implementations
- **Context extensions**: Access factories via `BuildContext` extensions

```dart
// 1. Scope widget with InheritedWidget
class SomeScope extends StatefulWidget {
  final Widget child;
  final SomeScopeBlocFactory? someScopeBlocFactory;

  const SomeScope({super.key, required this.child, this.someScopeBlocFactory});

  static SomeScopeBlocFactory getBlocFactory(BuildContext context) =>
      _stateOf(context)._someScopeBlocFactory;
}

// 2. BlocFactory interface + implementation
abstract interface class SomeScopeBlocFactory {
  SomeBloc someBloc();
}

// 3. Extension for context access
extension SomeScopeExtension on BuildContext {
  SomeScopeBlocFactory get someScopeBlocFactory => SomeScope.getBlocFactory(this);
}
```

### Exception Hierarchy

The library uses typed exceptions — don't wrap them in custom exceptions, let them propagate:

- **`StorageException`** with `StorageExceptionType`: `notInitialized`, `alreadyInitialized`, `invalidStorage`, `entryNotFound`, `other`
- **`BiometricException`** with `BiometricExceptionType`: `cancel`, `failure`, `keyNotFound`, `keyAlreadyExists`, `notAvailable`, `notConfigured`
- **`DecryptFailedException`** — thrown when password/cipher is incorrect

```dart
// CORRECT — handle specific exceptions, let others propagate
try {
  await bioCipherFunc.encrypt(data);
} on BiometricException catch (e) {
  if (e.type == BiometricExceptionType.cancel) {
    // Handle cancellation specifically
  }
  rethrow; // Let BLoC handle other biometric errors
}

// WRONG — don't wrap library exceptions
try {
  await bioCipherFunc.encrypt(data);
} catch (e) {
  throw CustomBiometricException(e); // Don't do this
}
```

### BLoC Conventions

- **Events**: Named as past actions (e.g., `UnlockRequested`, `EntryAdded`, `BiometricEnabledEvent`)
- **Actions**: Descriptive side effects (e.g., `ShowErrorAction`, `BiometricAuthenticationCancelledAction`)
- **State**: Use enums instead of multiple boolean fields (e.g., `LoadingStatus` enum)
- **No cubits** — BLoC only (`avoid-cubits` rule enforced by DCM)
- **ActionBloc** for one-time events (navigation, dialogs, snackbars) via `package:action_bloc`

#### BLoC State Rule (CRITICAL)

**Never store mutable state in private BLoC variables.** All state must live in the State class.

```dart
// WRONG
class SomeBloc extends Bloc<SomeEvent, SomeState> {
  bool _isLoading = false;  // Don't store state here
}

// CORRECT
emit(state.copyWith(isLoading: true));
```

**Exception:** `StreamSubscription` fields are allowed (infrastructure, not state).

#### Freezed State Pattern

Use a **single class with an enum** for status, not multiple factory constructors:

```dart
@freezed
abstract class SomeState with _$SomeState {
  const factory SomeState({
    @Default([]) List<Data> data,
    @Default(SomeStatus.initial) SomeStatus status,
  }) = _SomeState;

  const SomeState._();

  bool get isLoading => status == SomeStatus.loading;
  bool get hasError => status == SomeStatus.error;
}

enum SomeStatus { initial, loading, loaded, error }
```

#### BLoC Structure Order

1. Final fields (dependencies) initialized in constructor
2. Constructor with event handler registration
3. Private fields (subscriptions, timers, etc.)
4. Event handlers (private methods)

#### BLoC File Naming (enforced by DCM `match-class-name-pattern`)

- `*_bloc.dart` — class name must end with `Bloc`
- `*_event.dart` — class name must end with `Event`
- `*_state.dart` — class name must end with `State`

### Repository Pattern

```dart
// 1. Interface — abstract interface class, no prefix
abstract interface class LockerRepository {
  /// Documentation for method.
  Future<Map<EntryId, EntryMeta>> unlock(String password);
  Future<Map<EntryId, EntryMeta>> unlockWithBiometric();
}

// 2. Implementation — Impl suffix
class LockerRepositoryImpl implements LockerRepository {
  final MFALocker _locker;

  LockerRepositoryImpl({required MFALocker locker}) : _locker = locker;

  @override
  Future<Map<EntryId, EntryMeta>> unlock(String password) async {
    final salt = await _locker.salt;
    final cipherFunc = PasswordCipherFunc(password: password, salt: salt!);
    await _locker.loadAllMeta(cipherFunc);
    return _locker.allMeta;
  }
}
```

Key points:
- `abstract interface class` for interfaces (no prefix like `I`)
- `Impl` suffix for implementations
- Named required constructor parameters
- Private fields with underscore prefix
- Repository creates cipher functions — BLoC passes raw passwords/no params

### Code Style

For complete coding standards, see `docs/conventions.md`.

#### Mandatory Syntax

- **Line length**: 120 characters (configured in `analysis_options.yaml`)
- **Trailing commas** on multi-line calls
- **Curly braces** for all control flow — note: root library has `curly_braces_in_flow_control_structures: false` while example app has `true`
- **Arrow syntax** for one-liners
- **for-in** over indexed loops
- **const** where possible
- **Single quotes** for strings (`prefer_single_quotes` enabled)
- **Check `context.mounted`** before navigation/dialogs after async operations

#### Class Member Order

1. Static constants (public, then private)
2. Constructor fields (public, then private)
3. Constructor
4. Other private fields
5. Public methods
6. Private methods

#### Widget Lifecycle Order

`initState` -> `didChangeDependencies` -> `didUpdateWidget` -> `build` -> `dispose` -> public methods -> private methods

### Naming Conventions

| Entity | Convention | Example |
|--------|-----------|---------|
| Interfaces | No prefix | `LockerRepository` |
| Implementations | `Impl` suffix | `LockerRepositoryImpl` |
| Events | Past tense | `UnlockRequested`, `EntryAdded` |
| Actions | Descriptive | `ShowErrorAction` |
| Private fields/methods | `_` prefix | `_password`, `_handleError()` |
| TODO comments | `// TODO(firstLetter.lastName):` | `// TODO(j.doe): Fix this` |
| BLoC files | `*_bloc.dart`, `*_event.dart`, `*_state.dart` | `locker_bloc.dart` |

### Null Safety

- **Avoid the `!` (null assertion) operator.** Always perform null checks.
- Extract nullable values to local variables before null checks (enables Dart's null promotion).
- Use early return/continue with logging for unexpected null cases.

```dart
// CORRECT
final value = bounds.timestamps;
if (value == null) {
  logger.logWarning('Unexpected null, skipping');
  continue;
}
// value is now promoted to non-null
```

### Documentation Style

- `///` for doc comments on all public APIs
- First sentence: concise summary ending with a period
- Comment **why**, not **what**
- Reference constants with `[ClassName.constant]` syntax
- No trailing comments; avoid redundancy

### Widget Rules

- **Never use private `_build*` methods** to construct widget trees. Instead:
  - Inline in builder callbacks
  - Private widget classes (same file): `class _LoadingIndicator extends StatelessWidget`
  - Separate files in `widgets/` directory
- Event handler methods like `_onRetry`, `_onPressed` **are allowed**.
- Use `const` constructors wherever possible.
- StatefulWidget state fields **must be private**.

### Testing

Tests use **mocktail** (NOT mockito) for mocking and follow Arrange/Act/Assert structure:

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

Key patterns:
- Mocks are in `test/mocks/` directory, named `Mock` + class (e.g., `MockEncryptedStorage`)
- `registerFallbackValue()` in `setUpAll` for mocktail value matchers
- `tearDown` disposes the SUT (system under test)
- Test helpers use `part` files (e.g., `mfa_locker_test_helpers.dart` is `part` of the test file)

### Anti-Patterns to Avoid

- Creating separate BLoCs for related features (extend existing BLoC instead)
- Wrapping library exceptions in custom exceptions (let them propagate)
- Storing state in multiple places (single source of truth)
- Creating abstract factories or strategy patterns for simple instantiation
- Skipping `context.mounted` checks before async UI operations
- Ignoring linter rules with `// ignore` comments (fix the issue instead)
- Creating duplicate extensions for nullable/non-nullable types (use nullable extension for both)
- Using timers or `Future.delayed` instead of deterministic system events (see below)

### Flutter Lifecycle & Timing Patterns

#### Prefer System Events Over Timers

Always use deterministic Flutter system events instead of arbitrary delays or timers:

| Problem | Bad | Good |
|---------|-----|------|
| Wait for bottom sheet animation | `Future.delayed(Duration(milliseconds: 400))` | `ModalRoute.of(context).animation` status listener |
| Clear state after biometric dialog closes | `Timer(Duration(milliseconds: 500), clearFlag)` | `AppLifecycleState.resumed` event |
| Wait for widget to be ready | `Future.delayed(...)` | `WidgetsBinding.instance.addPostFrameCallback` |

#### Biometric Operation State Machine

The app uses a state machine to prevent vault locking during biometric operations:

```dart
enum BiometricOperationState {
  idle,          // No operation, locking allowed
  inProgress,    // System biometric dialog may be showing, locking blocked
  awaitingResume // Operation done, waiting for app lifecycle resume
}
```

**Flow:**
1. Before biometric call -> set `inProgress`
2. After biometric call (in `finally` block) -> set `awaitingResume`
3. On `AppLifecycleState.resumed` -> set `idle`

This handles the lifecycle changes caused by system biometric dialogs (resumed -> inactive -> resumed).

#### Animation-Aware Bottom Sheets

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

#### Full-Screen Transitions (macOS)

macOS full-screen transitions trigger rapid lifecycle changes. Use `FullscreenListener` with state machine:

```dart
enum FullscreenState { normal, transitioning }
```

This prevents spurious lock events during the transition.

## Configuration

- **Config files**: `config/{dev,prod,stage}.env` with environment-specific variables
- **Flavors**: dev, stage, prod (iOS, Android, macOS, Windows builds)
- **FVM**: Flutter 3.35.1 locked in `.ci-flutter-version`
- **Strict analysis**: `strict-casts: true`, `strict-raw-types: true`
- **Formatter**: `page_width: 120`, `trailing_commas: preserve`

## Local Packages

| Package | Location | Purpose |
|---------|----------|---------|
| `locker` | `/` (root) | Core encrypted key-value storage library |
| `biometric_cipher` | `packages/biometric_cipher/` | Platform channel plugin for TPM/Secure Enclave biometrics (iOS, macOS, Android, Windows) |
| `secure_mnemonic` | `packages/secure_mnemonic/` | Mnemonic key storage plugin |
| `action_bloc` | `example/packages/action_bloc/` | Custom ActionBloc pattern (BLoC + side effects) |
| `package_info_plus` | `example/packages/package_info_plus/` | Local fork of package_info_plus |

## Documentation References

- [`docs/vision.md`](docs/vision.md) — Architecture principles, anti-patterns, project vision
- [`docs/conventions.md`](docs/conventions.md) — Complete coding standards and development practices
- [`docs/guidelines.md`](docs/guidelines.md) — AI-assisted development rules
- [`docs/workflow.md`](docs/workflow.md) — Iteration-based development workflow
- [`docs/MFA_Locker.md`](docs/MFA_Locker.md) — Technical encryption architecture
- [`docs/code-style-guide.md`](docs/code-style-guide.md) — Code style reference
