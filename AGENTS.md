# AGENTS.md

This file provides LLM agents and human contributors with project context,
structure, build commands, contribution rules, and code guidelines.

## Project Overview

`locker` is a Dart/Flutter library providing AES-GCM encrypted key-value storage
with multi-factor authentication (password + biometrics via TPM/Secure Enclave).
It targets iOS, macOS, Android, and Windows.

The repo contains:
- **`lib/`** — the `locker` library itself (core encryption, storage, authentication)
- **`packages/biometric_cipher/`** — native Flutter plugin wrapping TPM/Secure Enclave
- **`example/`** — `mfa_demo` Flutter app demonstrating the library
- **`test/`** — unit tests with `mocktail` mocks

## Technical Context

| Field | Value |
|-------|-------|
| **Language** | Dart 3.5+ / Flutter 3.35.1 |
| **State Management** | `flutter_bloc` 8.1.6 + custom `action_bloc` (local package) with `freezed` for immutable states/events |
| **Architecture** | Library: Locker → Security → Storage → Crypto. Example app: UI → BLoC → Repository → MFALocker |
| **Encryption** | AES-256-GCM (authenticated encryption) via `cryptography` 2.7.0 |
| **Key Derivation** | Argon2id (OWASP recommended: 19 MiB memory, 1 parallelism, 2 iterations) |
| **Integrity** | HMAC-SHA256 over entire storage structure with constant-time comparison |
| **Storage** | JSON file-backed with atomic writes (temp file + rename), `chmod 600` on macOS |
| **Biometrics** | `biometric_cipher` (local plugin) — TPM/Secure Enclave key generation, encryption, validation |
| **Testing** | `flutter_test`, `mocktail` 1.0.3, Arrange-Act-Assert pattern |
| **Code Generation** | `build_runner`, `freezed` (example app only) |
| **Linting** | `lints` 3.0.0 + 90+ rules, `strict-casts: true`, `strict-raw-types: true` |
| **Target Platforms** | iOS, Android, macOS, Windows |
| **DI** | Manual constructor-based injection with factory classes (example app) |
| **Project Type** | Flutter library with local plugin package and example app |

## Project Structure

```
mfa_locker/
├── lib/
│   ├── locker/
│   │   ├── locker.dart              # Locker abstract interface (public API)
│   │   ├── mfa_locker.dart          # MFALocker — main implementation
│   │   └── models/
│   │       └── biometric_state.dart # BiometricState enum (9 states: includes keyInvalidated)
│   ├── security/
│   │   ├── security_provider.dart          # SecurityProvider — password/biometric auth factory
│   │   ├── biometric_cipher_provider.dart  # BiometricCipherProvider — TPM/Secure Enclave ops (includes isKeyValid)
│   │   └── models/
│   │       ├── cipher_func.dart            # Abstract CipherFunc (encrypt/decrypt + Erasable)
│   │       ├── password_cipher_func.dart   # Argon2id-derived AES-GCM cipher
│   │       ├── bio_cipher_func.dart        # TPM-backed biometric cipher (includes key validity checking)
│   │       ├── biometric_config.dart       # Platform-specific biometric prompt config
│   │       ├── key_validity_status.dart    # KeyValidityStatus enum (valid, invalid, unknown)
│   │       └── exceptions/
│   │           └── biometric_exception.dart # BiometricException + BiometricExceptionType (7 types, includes keyInvalidated)
│   ├── storage/
│   │   ├── encrypted_storage.dart       # EncryptedStorage interface
│   │   ├── encrypted_storage_impl.dart  # JSON file-backed implementation with atomic writes
│   │   ├── hmac_storage_mixin.dart      # HMAC-SHA256 integrity verification
│   │   └── models/
│   │       ├── data/
│   │       │   ├── origin.dart       # Origin enum (pwd, bio)
│   │       │   ├── key_wrap.dart     # Encrypted master key for one auth method
│   │       │   ├── wrapped_key.dart  # Container for multiple KeyWrap instances
│   │       │   ├── storage_data.dart # Top-level persisted structure (entries, keys, HMAC)
│   │       │   └── storage_entry.dart # Single encrypted entry (id, meta, value)
│   │       ├── domain/
│   │       │   ├── entry_id.dart          # Extension type wrapping String (UUID)
│   │       │   ├── entry_meta.dart        # ErasableByteArray subclass for metadata
│   │       │   ├── entry_value.dart       # ErasableByteArray subclass for values
│   │       │   ├── entry_input.dart       # Base input class (Erasable)
│   │       │   ├── entry_add_input.dart   # Input for creating entries
│   │       │   └── entry_update_input.dart # Input for updating entries
│   │       └── exceptions/
│   │           ├── storage_exception.dart        # Typed storage errors (6 types)
│   │           └── decrypt_failed_exception.dart # AES-GCM auth tag failure
│   ├── erasable/
│   │   ├── erasable.dart              # Erasable interface (isErased, erase)
│   │   └── erasable_byte_array.dart   # Zeroes memory on erase(), throws on post-erase access
│   └── utils/
│       ├── cryptography_utils.dart    # AES-GCM encrypt/decrypt, Argon2id, HMAC-SHA256, key gen
│       ├── sync.dart                  # Reentrant lock wrapper (Sync)
│       └── list_extensions.dart       # toUint8List() extension
├── packages/
│   └── biometric_cipher/             # Native Flutter plugin
│       ├── lib/                      # Platform interface + method channel
│       ├── android/                  # Kotlin: AuthenticationRepository, SecureService
│       ├── ios/                      # Shared Darwin source (Secure Enclave)
│       ├── macos/                    # Shared Darwin source (Secure Enclave)
│       └── windows/                  # C++: Windows Hello + TPM
├── example/
│   ├── lib/
│   │   ├── features/
│   │   │   ├── locker/              # Core vault feature (unlock, entries CRUD, biometric)
│   │   │   ├── settings/            # Settings feature (auto-lock timeout)
│   │   │   └── tpm_test/            # TPM/biometric testing feature
│   │   ├── core/                    # Shared widgets, constants, extensions
│   │   └── di/                      # DependencyScope, RepositoryFactory, BlocFactory
│   ├── packages/
│   │   ├── action_bloc/             # Custom flutter_bloc extension adding side-effect Actions
│   │   └── package_info_plus/       # Platform integration
│   └── Makefile                     # Build targets for example app
├── test/
│   ├── locker/                      # MFALocker tests
│   ├── security/                    # CipherFunc tests
│   ├── storage/                     # EncryptedStorage tests
│   ├── utils/                       # Utility tests
│   └── mocks/                       # Mock classes (mocktail)
├── pubspec.yaml
├── analysis_options.yaml
├── Makefile                         # Proxy to example/Makefile
└── .ci-flutter-version              # Pinned Flutter version: 3.35.1
```

## Build And Test Commands

Flutter version is pinned via `.ci-flutter-version` → **3.35.1**. Use `fvm` to match.

### Library (root)

| Command | Purpose |
|---------|---------|
| `fvm flutter pub get` | Install dependencies |
| `fvm flutter test` | Run all tests |
| `fvm flutter test test/locker/mfa_locker_test.dart` | Run single test file |
| `fvm flutter test --name "test name pattern"` | Run tests by name |
| `fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` | Analyze (zero warnings required) |
| `fvm dart format . --line-length 120` | Format all files |

### Example App (`cd example` first)

| Command | Purpose |
|---------|---------|
| `make in` | pub get + build_runner (quick start) |
| `make g` | Code generation only (build_runner) |
| `make analyze` | Lint with fatal warnings/infos |
| `make clean` | flutter clean + reset analyze stamp |
| `make apk` | Release APK (android-arm64) |
| `make release-android` | Full Android release pipeline |
| `make ci-build-macos` | macOS build (CI) |
| `make ci-build-ios` | iOS build (CI) |
| `make ci-build-windows` | Windows build (CI) |

### Biometric Cipher Plugin (`cd packages/biometric_cipher` first)

| Command | Purpose |
|---------|---------|
| `fvm flutter test` | Run plugin tests |
| `fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` | Analyze plugin |

### Dart MCP Tools (Agent Use)

**Prefer MCP tools over shell commands for Dart/Flutter operations.**

| Tool | Purpose |
|------|---------|
| `mcp__dart__analyze_files` | Analyze entire project |
| `mcp__dart__dart_format` | Format files (always use `paths` parameter) |
| `mcp__dart__dart_fix` | Run `dart fix --apply` |
| `mcp__dart__run_tests` | Run tests |
| `mcp__dart__pub` | Pub commands (add, get, remove, upgrade) |
| `mcp__dart__hot_reload` | Hot reload running app |

Shell commands (`cp`, `mv`, `git`, `build_runner`) are fine.

## Contribution Instructions

### Before Making Changes

1. Run `fvm flutter pub get` if dependencies may be stale.
2. Understand the architecture layers described below.
3. Follow all code conventions and patterns.

### After Making Changes

1. Run `fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` or use `mcp__dart__analyze_files` — zero warnings/infos required.
2. Format changed files with `mcp__dart__dart_format` (with `paths` parameter) or `fvm dart format <files> --line-length 120`.
3. Run relevant tests via `mcp__dart__run_tests` or `fvm flutter test`.
4. If you changed freezed models in the example app, run `cd example && make g`.

### Dependencies

- Use **exact versions without caret** (e.g., `http: 1.5.0` not `http: ^1.5.0`).
- Sort dependencies alphabetically (SDK dependencies first).

## Code Guidelines

### Core Principles

- **KISS** — Simplest solution that works. No abstractions "for the future".
- **Single responsibility** — One thing per component.
- **Composition over inheritance** — Favor composition for building complex widgets and logic.
- **Immutability** — Prefer immutable data structures; use `freezed` for models and states.
- **No overengineering** — Extend existing patterns before creating new ones.

### Architecture

#### Library Layer (`lib/`)

Layered architecture: **Locker (API) → Security (auth) → Storage (persistence) → Crypto (primitives)**

**Key design decisions:**

- **Master key wrapping**: A random master key encrypts all entries. The master key itself is encrypted ("wrapped") per authentication method (password or biometric), stored as `WrappedKey` with multiple `KeyWrap` entries identified by `Origin` (`pwd` or `bio`).
- **`CipherFunc`**: Abstraction over an authentication method. `PasswordCipherFunc` derives a key via Argon2id on every encrypt/decrypt call (intentional — minimizes derived key lifetime in memory). `BioCipherFunc` delegates to the TPM/Secure Enclave and performs key validity checks before decrypt operations via `_checkKeyValidity`, translating TPM key-invalidated errors to `BiometricExceptionType.keyInvalidated`.
- **`ErasableByteArray`**: Overwrites bytes to zero on `erase()`. All sensitive data implements `Erasable`. Every `MFALocker` operation calls `erase()` on its arguments in `finally` via `_executeWithCleanup`.
- **`Sync`**: Reentrant `synchronized` lock guards all `MFALocker` and `EncryptedStorageImpl` state mutations.
- **Metadata cache**: After unlock, `EntryMeta` objects are cached in `_metaCache`. Values (`EntryValue`) are never cached — fetched and erased on demand.
- **Storage format**: JSON file containing `salt`, `lockTimeout`, `masterKey` (wrapped key list), `entries` (array of encrypted meta+value), `hmacKey`, `hmacSignature`.
- **Atomic writes**: Storage writes to a temp file first, then atomically renames to target path. macOS restricts file permissions via `chmod 600`.
- **Screen-lock auto-lock**: `biometric_cipher` exposes a `screenLockStream` that emits when the OS locks the screen (Android keyguard, iOS/macOS lock notifications, Windows `WTSRegisterSessionNotification`). The stream emits **lock events only** (never unlock). `MFALocker` subscribes and locks itself in response.

#### Example App Layer (`example/lib/`)

Architecture: **UI → BLoC → Repository → MFALocker**

State management uses `action_bloc` (local package in `example/packages/`) + Freezed:
- **Events** (past tense): `UnlockRequested`, `EntryAdded`
- **States**: immutable data via Freezed
- **Actions** (one-off side effects): `ShowErrorAction`, `NavigateAction`

The **Repository** layer creates `CipherFunc` objects and wraps all MFALocker exceptions. BLoCs receive plain types (e.g., `String password`) and never interact with `CipherFunc` directly.

### Naming Conventions

- **Interfaces**: no prefix (`LockerRepository`, `EncryptedStorage`)
- **Implementations**: `Impl` suffix (`EncryptedStorageImpl`, `LockerRepositoryImpl`)
- **Private**: underscore prefix (`_metaCache`, `_executeWithCleanup`)
- **Events**: past tense (`UnlockRequested`, `EntryAdded`, `BiometricSetupCompleted`)
- **Actions**: descriptive (`ShowErrorAction`, `BiometricAuthenticationCancelledAction`)
- **Files**: snake_case, must match primary type name
- **Extensions**: file name must match extension name (`LockerBlocBiometricStream` → `locker_bloc_biometric_stream.dart`)
- **TODOs**: `// TODO(f.lastname): Description`

### Code Style

- **Line length**: 120 characters (configured in `analysis_options.yaml`)
- **Trailing commas**: Required on all multi-line function calls/constructors (`require_trailing_commas: true`)
- **Curly braces**: Not required on control flow structures (`curly_braces_in_flow_control_structures: false`)
- **Single quotes**: Use `'` not `"` (`prefer_single_quotes` enforced)
- **Arrow syntax**: Use for simple one-line methods (`prefer_expression_function_bodies` enabled)
- **`const`**: Use `const` constructors everywhere possible (`prefer_const_constructors` enabled)
- **`super` parameters**: Use `use_super_parameters` (enabled)
- **Strict analysis**: `strict-casts: true`, `strict-raw-types: true`
- **Dead code**: Elevated to `error` level
- **Never ignore linter rules**: Fix the underlying issue instead

### Class Member Order

1. Static public and private methods/fields
2. Final fields (public and private) initialized in constructor
3. Constructors
4. Other private fields
5. Public methods
6. Private methods

### Widget Lifecycle Order (StatefulWidget, example app)

1. `initState` (always first)
2. `didUpdateWidget`, `didChangeDependencies`
3. `build`
4. `dispose` (always last)
5. Custom methods after lifecycle

### BLoC Conventions (example app)

- **Structure order**: Final fields → constructor with handler registration → private fields → event handlers
- **Events**: Named as past actions (`ThemeChanged`, `ButtonPressed`)
- **State**: Use enums instead of multiple boolean fields
- **ActionBloc**: For one-time events (navigation, dialogs, snackbars) via `package:action_bloc`
- **No cubits** — BLoC only

### One Type Per File

- Each file contains one primary type (class, enum, extension)
- Sealed classes/enums: extract to dedicated files
- Extensions on nullable types: use a single extension on `T?` — it works for both `T` and `T?`

### Null Safety

- Avoid the `!` (null assertion) operator. Always perform null checks.
- Extract nullable values to local variables before null checks (enables Dart's null promotion).
- Use early return/continue with logging for unexpected null cases.

### Layer Patterns (example app)

- **Repository**: Create cipher functions, call MFALocker, handle exceptions
- **BLoC**: Emit loading state, call repository, emit result/action
- **UI**: Dispatch events, render states, handle actions
- Always check `context.mounted` before navigation or showing dialogs after `await`
- Use `async`/`await` for async operations

### Documentation

- `///` for doc comments on all public APIs
- First sentence: concise summary ending with a period
- Comment **why**, not **what**
- Reference constants with `[ClassName.constant]` syntax

## Testing

Tests live in `test/` alongside mocks in `test/mocks/`. Use `mocktail` for mocking.

### Patterns

- **Arrange-Act-Assert** pattern
- Prefer **fakes/stubs** over mocks; use `mocktail` when mocking is needed
- No code generation for mocks (manual `extends Mock`)
- Register fallback values for complex types in `setUpAll()`
- Tests grouped with `group()` function
- Assertions via `expect()`, `throwsA()`, `isA<>()`

### Mock Organization

All mock classes in `test/mocks/`:

| Mock | Target |
|------|--------|
| `MockBiometricCipher` | `BiometricCipher` |
| `MockBiometricCipherProvider` | `BiometricCipherProvider` |
| `MockPasswordCipherFunc` | `PasswordCipherFunc` |
| `MockBioCipherFunc` | `BioCipherFunc` |
| `MockEncryptedStorage` | `EncryptedStorage` |
| `MockFile` | `File` |

### Test Injection

The `EncryptedStorage` interface is designed for injection (`@visibleForTesting` constructor param in `MFALocker`), enabling unit tests with mock storage.

## Configuration

### Analyzer (`analysis_options.yaml`)

```yaml
analyzer:
  exclude:
    - "pubspec.yaml"
  language:
    strict-raw-types: true
    strict-casts: true
  errors:
    invalid_annotation_target: ignore
    dead_code: error
    invalid_assignment: error
    todo: ignore
    directives_ordering: info

formatter:
  page_width: 120
  trailing_commas: preserve
```

### Key Linter Rules

| Rule | Effect |
|------|--------|
| `require_trailing_commas` | Mandatory trailing commas on multi-line constructs |
| `prefer_const_constructors` | Use `const` everywhere possible |
| `prefer_expression_function_bodies` | Arrow syntax for one-liners |
| `prefer_single_quotes` | Single quotes required |
| `exhaustive_cases` | All enum/sealed cases must be handled |
| `cancel_subscriptions` | Stream subscriptions must be cancelled |
| `close_sinks` | Sink instances must be closed |
| `unawaited_futures` | Futures must be awaited or explicitly marked |
| `avoid_print` | No print statements |
| `always_declare_return_types` | Return types required on all functions |
| `use_super_parameters` | Use super parameters syntax |
| `avoid_relative_lib_imports` | Use package imports |

## Local Packages

| Package | Location | Purpose |
|---------|----------|---------|
| `biometric_cipher` | `packages/biometric_cipher/` | Native Flutter plugin wrapping TPM/Secure Enclave for biometric key operations (generate, encrypt, decrypt, validate, delete). Supports Android (Kotlin), iOS/macOS (Swift, Secure Enclave), Windows (C++, Windows Hello). |
| `action_bloc` | `example/packages/action_bloc/` | Custom `flutter_bloc` extension. `ActionBloc<E, S, A>` emits both state updates and one-off side-effect actions via separate streams. Provides `BlocActionConsumer`, `BlocActionListener`, `BlocActionStateConsumer` widgets. |
| `package_info_plus` | `example/packages/package_info_plus/` | Platform integration for app package info. |

### Key Dependencies (root library)

| Package | Version | Purpose |
|---------|---------|---------|
| `cryptography` | 2.7.0 | AES-GCM, Argon2id, HMAC-SHA256 |
| `rxdart` | 0.28.0 | BehaviorSubject for state streams |
| `synchronized` | 3.4.0 | Reentrant lock |
| `uuid` | 4.5.1 | UUID v4 generation |
| `adguard_logger` | v1.0.1 (git) | Logging |
| `biometric_cipher` | local path | Hardware-backed biometric operations |
| `collection` | 1.19.1 | Collection utilities |
| `meta` | 1.16.0 | Annotations (`@visibleForTesting`) |
| `path` | 1.9.1 | File path utilities |
