# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`locker` is a Dart/Flutter library providing AES-GCM encrypted key-value storage with multi-factor authentication (password + biometrics via TPM/Secure Enclave). It targets iOS, macOS, Android, and Windows.

The repo contains:
- **`lib/`** — the `locker` library itself
- **`packages/biometric_cipher/`** — native Flutter plugin wrapping TPM/Secure Enclave
- **`packages/secure_mnemonic/`** — companion package
- **`example/`** — `mfa_demo` Flutter app demonstrating the library

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

### Example App (`cd example` first)

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

Flutter version is pinned via `.ci-flutter-version` → **3.41.4**. Use `fvm` to match.

## Architecture

### Library Layer (`lib/`)

```
lib/
├── locker/
│   ├── locker.dart              # Locker abstract interface
│   ├── mfa_locker.dart          # MFALocker — main implementation
│   └── models/biometric_state.dart
├── security/
│   ├── cipher_func.dart         # Abstract CipherFunc (encrypt/decrypt)
│   ├── password_cipher_func.dart  # PBKDF2-derived AES-GCM cipher
│   ├── bio_cipher_func.dart       # TPM-backed biometric cipher
│   ├── biometric_cipher_provider.dart  # Platform biometric operations
│   └── models/biometric_config.dart
├── storage/
│   ├── encrypted_storage.dart       # EncryptedStorage interface
│   ├── encrypted_storage_impl.dart  # JSON file-backed implementation
│   ├── hmac_storage_mixin.dart      # HMAC-SHA256 integrity verification
│   └── models/
│       ├── data/        # StorageData, StorageEntry, WrappedKey, KeyWrap, Origin
│       └── domain/      # EntryId, EntryMeta, EntryValue
├── erasable/
│   ├── erasable.dart              # Erasable interface
│   └── erasable_byte_array.dart   # Zeroes memory on erase()
└── utils/
    ├── cryptography_utils.dart    # AES-GCM encrypt/decrypt, PBKDF2
    ├── sync.dart                  # Reentrant lock wrapper (Sync)
    └── list_extensions.dart
```

**Key design decisions:**

- **Master key wrapping**: A random master key encrypts all entries. The master key itself is encrypted ("wrapped") per authentication method (password or biometric), stored as `WrappedKey` with multiple `KeyWrap` entries identified by `Origin` (`pwd` or `bio`).
- **`CipherFunc`**: Abstraction over an authentication method. `PasswordCipherFunc` derives a key via PBKDF2 on every encrypt/decrypt call (intentional — minimizes derived key lifetime in memory). `BioCipherFunc` delegates to the TPM/Secure Enclave.
- **`ErasableByteArray`**: Overwrites bytes to zero on `erase()`. All sensitive data (`CipherFunc`, `EntryMeta`, `EntryValue`) implements `Erasable`. Every `MFALocker` operation calls `erase()` on its arguments in `finally` via `_executeWithCleanup`.
- **`Sync`**: Reentrant `synchronized` lock guards all `MFALocker` and `EncryptedStorageImpl` state mutations.
- **Metadata cache**: After unlock, `EntryMeta` objects are cached in `_metaCache`. Values (`EntryValue`) are never cached — fetched and erased on demand.
- **Storage format**: JSON file containing `salt`, `lockTimeout`, `masterKey` (wrapped key list), `entries` (array of encrypted meta+value), `hmacKey`, `hmacSignature`.

### Example App Layer (`example/lib/`)

Architecture: **UI → BLoC → Repository → MFALocker**

```
example/lib/
├── features/
│   ├── locker/    # Core vault feature (unlock, entries CRUD, biometric)
│   └── settings/  # Settings feature
├── core/          # Shared widgets, utilities
└── di/            # Dependency injection
```

State management uses `action_bloc` + Freezed:
- **Events** (past tense): `UnlockRequested`, `EntryAdded`
- **States**: immutable data via Freezed
- **Actions** (side effects): `ShowErrorAction`, `NavigateAction`

The **Repository** layer is responsible for creating `CipherFunc` objects and wrapping all MFALocker exceptions. BLoCs receive plain types (e.g., `String password`) and never interact with `CipherFunc` directly.

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

Shell commands (`cp`, `mv`, `git`, `build_runner`) are fine.

## Code Conventions

All rules from `docs/code-style-guide.md` and `docs/conventions.md` apply. Key points:

- **Line length**: 120 characters (`dart format --line-length 120`)
- **Trailing commas**: Required on all multi-line function calls/constructors
- **Curly braces**: Always on control flow structures
- **Single quotes**: Use `'` not `"`
- **Abstract class naming**: no prefix for interface, `Impl` suffix for main implementation
- **Class member order**: static → constructor fields → constructor → other private fields → public methods → private methods
- **Dependencies**: Exact versions (no `^` caret), alphabetical order
- **TODOs**: `// TODO(f.lastname): Description`
- **One type per file**: File name must match the primary type it contains
- **Extensions**: File name must match the extension name (`LockerBlocBiometricStream` → `locker_bloc_biometric_stream.dart`)
- **`context.mounted`**: Always check before navigation or showing dialogs after `await`

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

The `EncryptedStorage` interface is designed for injection (`@visibleForTesting` constructor param in `MFALocker`), enabling unit tests with mock storage.
