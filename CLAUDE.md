# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`locker` is a Dart/Flutter library providing AES-GCM encrypted key-value storage with multi-factor authentication (password + biometrics via TPM/Secure Enclave). It targets iOS, macOS, Android, and Windows.

The repo contains:
- **`lib/`** — the `locker` library itself
- **`packages/biometric_cipher/`** — native Flutter plugin wrapping TPM/Secure Enclave
- **`example/`** — `mfa_demo` Flutter app demonstrating the library

SDK requirements: Dart `^3.11.0`, Flutter `^3.41.4`. Pinned Flutter version (`.ci-flutter-version`): **3.41.4** — use `fvm` to match.

Key security features worth knowing up front:
- **AES-256-GCM** for all data at rest; **Argon2id** (19 MiB / 1p / 2 iters) for password-derived keys; **HMAC-SHA256** over the storage file for tamper detection.
- **Master key wrapping**: a random master key encrypts entries; the master key itself is wrapped per auth method (`Origin.pwd`, `Origin.bio`), so password and biometric unlocks decrypt the *same* entries.
- **Biometric key invalidation detection**: `BioCipherFunc._checkKeyValidity` runs a silent `isKeyValid` probe (no biometric prompt) and translates TPM key-invalidated errors to `BiometricExceptionType.keyInvalidated`. Callers are expected to `teardownBiometry` and re-setup when this fires.
- **Screen-lock auto-lock**: the `biometric_cipher` plugin exposes a `screenLockStream` that emits when the OS locks the screen (Android keyguard, iOS/macOS lock notifications, Windows `WTSRegisterSessionNotification`). The stream emits **lock events only** (never unlock) — `MFALocker` subscribes and locks itself in response.
- **Inactivity auto-lock**: `MFALocker` persists a per-vault `lockTimeout`; the example app's `TimerService` resets on user activity and locks when it expires. Independent of the screen-lock stream.
- **Atomic writes** via temp file + rename; `chmod 600` enforced on macOS.

**External contributions:** This is a source-available project; per `CONTRIBUTING.md`, external PRs are not accepted. Don't propose opening upstream PRs to public forks.

## Commands

### Library (root)

```bash
# Install dependencies
fvm flutter pub get

# Run tests
fvm flutter test

# Run a single test file
fvm flutter test test/locker/mfa_locker_test.dart

# Analyze
fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .

# Format (line length 120)
fvm dart format . --line-length 120
```

### Example App (`cd example` first, or use root Makefile which proxies all targets)

```bash
make in        # pub get + build_runner (quick start)
make g         # code generation only (build_runner)
make analyze   # lint with fatal warnings/infos
make clean     # flutter clean + reset analyze stamp
make apk       # release APK (android-arm64)
make release-android  # full Android release pipeline
make ci-build-macos   # macOS build (CI)
make ci-build-ios     # iOS build (CI)
make ci-build-windows # Windows build (CI)
```

### Biometric Cipher Plugin (`cd packages/biometric_cipher` first)

```bash
fvm flutter test                                   # run plugin tests
fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .
```

Native Swift tests live in `packages/biometric_cipher/example/shared_native_test/` and run via Xcode test targets (iOS/macOS), not via `fvm flutter test`:

```bash
# Native Swift tests (macOS)
xcodebuild test \
  -workspace packages/biometric_cipher/example/macos/Runner.xcworkspace \
  -scheme Runner \
  -destination 'platform=macOS'

# Native Swift tests (iOS Simulator)
xcodebuild test \
  -workspace packages/biometric_cipher/example/ios/Runner.xcworkspace \
  -scheme Runner \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

The root `Makefile` is a **proxy** that forwards every target to `example/Makefile`, so `make in`, `make g`, `make analyze`, etc. run from the root but operate on the example app. `USE_FVM=true` is the default; pass `USE_FVM=false` to bypass fvm.

## Architecture

### Library Layer (`lib/`)

```
lib/
├── locker/
│   ├── locker.dart              # Locker abstract interface
│   ├── mfa_locker.dart          # MFALocker — main implementation
│   └── models/biometric_state.dart
├── security/
│   ├── biometric_cipher_provider.dart  # Platform biometric operations
│   ├── security_provider.dart          # Authentication facade — returns CipherFunc per auth method
│   └── models/
│       ├── cipher_func.dart           # Abstract CipherFunc (encrypt/decrypt)
│       ├── password_cipher_func.dart  # Argon2id-derived AES-GCM cipher
│       ├── bio_cipher_func.dart       # TPM-backed biometric cipher (key-validity check before decrypt)
│       ├── biometric_config.dart
│       ├── key_validity_status.dart   # KeyValidityStatus enum (valid, invalid, unknown)
│       └── exceptions/biometric_exception.dart  # BiometricExceptionType includes keyInvalidated
├── storage/
│   ├── encrypted_storage.dart       # EncryptedStorage interface
│   ├── encrypted_storage_impl.dart  # JSON file-backed implementation
│   ├── hmac_storage_mixin.dart      # HMAC-SHA256 integrity verification
│   └── models/
│       ├── data/           # StorageData, StorageEntry, WrappedKey, KeyWrap, Origin
│       ├── domain/         # EntryId, EntryMeta, EntryValue, EntryAddInput, EntryUpdateInput
│       └── exceptions/     # StorageException, DecryptFailedException
├── erasable/
│   ├── erasable.dart              # Erasable interface
│   └── erasable_byte_array.dart   # Zeroes memory on erase()
└── utils/
    ├── cryptography_utils.dart    # AES-GCM encrypt/decrypt, Argon2id
    ├── sync.dart                  # Reentrant lock wrapper (Sync)
    └── list_extensions.dart
```

**Key design decisions:**

- **Master key wrapping**: A random master key encrypts all entries. The master key itself is encrypted ("wrapped") per authentication method (password or biometric), stored as `WrappedKey` with multiple `KeyWrap` entries identified by `Origin` (`pwd` or `bio`).
- **`CipherFunc`**: Abstraction over an authentication method. `PasswordCipherFunc` derives a key via Argon2id on every encrypt/decrypt call (intentional — minimizes derived key lifetime in memory). `BioCipherFunc` delegates to the TPM/Secure Enclave.
- **`ErasableByteArray`**: Overwrites bytes to zero on `erase()`. All sensitive data (`CipherFunc`, `EntryMeta`, `EntryValue`) implements `Erasable`. Every `MFALocker` operation calls `erase()` on its arguments in `finally` via `_executeWithCleanup`.
- **`Sync`**: Reentrant `synchronized` lock guards all `MFALocker` and `EncryptedStorageImpl` state mutations.
- **Metadata cache**: After unlock, `EntryMeta` objects are cached in `_metaCache`. Values (`EntryValue`) are never cached — fetched and erased on demand.
- **Storage format**: JSON file containing `salt`, `lockTimeout`, `masterKey` (wrapped key list), `entries` (array of encrypted meta+value), `hmacKey`, `hmacSignature`.
- **Public exception surface**: three types cross layer boundaries — `DecryptFailedException` (wrong password / corrupted data), `BiometricException` with typed `BiometricExceptionType` (`cancel`, `failure`, `keyInvalidated`, `keyNotFound`, `keyAlreadyExists`, `notAvailable`, `notConfigured`), and `StorageException` (`notInitialized`, `alreadyInitialized`, `invalidStorage`, `entryNotFound`). The Repository layer in the example app wraps these; BLoCs should not catch library exceptions directly.

### Example App Layer (`example/lib/`)

Architecture: **UI → BLoC → Repository → MFALocker**

```
example/lib/
├── features/
│   ├── locker/    # Core vault feature (unlock, entries CRUD, biometric)
│   ├── settings/  # Settings feature (auto-lock timeout)
│   └── tpm_test/  # TPM/biometric testing & diagnostics feature
├── core/          # Shared widgets, utilities
└── di/            # Dependency injection (DependencyScope, RepositoryFactory, BlocFactory)

example/packages/
├── action_bloc/       # Custom flutter_bloc extension adding side-effect Actions
└── package_info_plus/  # Platform integration
```

State management uses `action_bloc` + Freezed:
- **Events** (past tense): `UnlockRequested`, `EntryAdded`
- **States**: immutable data via Freezed
- **Actions** (side effects): `ShowErrorAction`, `NavigateAction`

The **Repository** layer is responsible for creating `CipherFunc` objects and wrapping all MFALocker exceptions. BLoCs receive plain types (e.g., `String password`) and never interact with `CipherFunc` directly.

Key example app dependencies: `flutter_bloc` + `action_bloc` (local package in `example/packages/`, not from pub.dev), `freezed` (immutable models), `build_runner` (code generation). The `biometric_cipher` plugin is also a local path dependency (`packages/biometric_cipher/`).

## Dart MCP Tools

**MUST use MCP tools instead of shell commands for Dart/Flutter operations.**

| Operation | MCP Tool |
|-----------|----------|
| Analyze | `mcp__dart__analyze_files` |
| Format | `mcp__dart__dart_format` |
| Fix | `mcp__dart__dart_fix` |
| Run tests | `mcp__dart__run_tests` |
| Pub get/add | `mcp__dart__pub` |
| Hot reload | `mcp__dart__hot_reload` |

**Exception**: `mcp__dart__run_tests` currently fails on this repo due to a `test`/`test_api` version resolution conflict (`test 1.26.2` vs `test_api 0.7.10` pinned by `flutter_test`) — fall back to `fvm flutter test` for running tests until the conflict is resolved.

Shell commands (`cp`, `mv`, `git`, `build_runner`) are fine.

## Code Conventions

All rules from `docs/code-style-guide.md` and `docs/conventions.md` apply. Key points:

- **Line length**: 120 characters (`dart format --line-length 120`)
- **Trailing commas**: Required on all multi-line function calls/constructors
- **Curly braces**: Not required on control flow structures (`curly_braces_in_flow_control_structures: false`)
- **Single quotes**: Use `'` not `"`
- **Abstract class naming**: no prefix for interface, `Impl` suffix for main implementation
- **Class member order**: static → constructor fields → constructor → other private fields → public methods → private methods
- **Dependencies**: Exact versions (no `^` caret), alphabetical order
- **TODOs**: `// TODO(f.lastname): Description`
- **One type per file**: File name must match the primary type it contains
- **Extensions**: File name must match the extension name (`LockerBlocBiometricStream` → `locker_bloc_biometric_stream.dart`)
- **`context.mounted`**: Always check before navigation or showing dialogs after `await`
- **Arrow syntax**: Use for simple one-line methods (`prefer_expression_function_bodies` enabled)
- **`const`**: Use `const` constructors everywhere possible (`prefer_const_constructors` enabled)
- **Sealed classes/enums**: Extract to dedicated files (one type per file rule)
- **Extensions on nullable types**: Use a single extension on `T?` — it works for both `T` and `T?`
- **Never ignore linter rules**: Fix the underlying issue instead
- **Strict analysis**: `strict-casts` and `strict-raw-types` are enabled

## Code Search

Use `ast-index` before any grep/search (17–69× faster):

```bash
/Applications/ast-index search "SymbolName"
/Applications/ast-index usages "MFALocker"
/Applications/ast-index implementations "CipherFunc"
/Applications/ast-index outline "mfa_locker.dart"
```

## Testing

Tests live in `test/` alongside mocks in `test/mocks/`. Use `mocktail` for mocking.

```bash
fvm flutter test                                   # all tests
fvm flutter test test/locker/mfa_locker_test.dart  # single file
fvm flutter test --name "test name pattern"        # by name
```

When grepping `fvm flutter test` output, pipe through `tr '\r' '\n'` first — the runner uses carriage returns to overwrite the progress line, so plain `grep` only sees the final line.

The `EncryptedStorage` interface is designed for injection (`@visibleForTesting` constructor param in `MFALocker`), enabling unit tests with mock storage.
