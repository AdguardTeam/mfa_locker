# Locker

A secure storage library for Dart/Flutter applications that provides encrypted key-value storage with multi-factor authentication support (password + biometrics).

## Features

- **AES-GCM Encryption** — All data is encrypted using industry-standard AES-GCM algorithm
- **Password Protection** — Argon2id key derivation from user password
- **Biometric Authentication** — Optional biometric unlock via TPM/Secure Enclave (iOS, macOS, Android, Windows)
- **Biometric Key Invalidation Detection** — Proactive detection of hardware key invalidation after biometric enrollment changes, with silent key validity probes (no biometric prompt)
- **HMAC Integrity Verification** — Detects storage tampering using HMAC-SHA256
- **Auto-Lock** — Automatic locking after configurable inactivity timeout
- **Secure Memory Management** — Erasable byte arrays that securely wipe sensitive data from memory
- **Atomic Writes** — Safe file operations to prevent data corruption
- **Reactive State** — RxDart streams for monitoring lock/unlock state

## Installation

Add `locker` to your `pubspec.yaml`:

```yaml
dependencies:
  locker:
    git:
      url: https://github.com/AdguardTeam/mfa_locker.git
      ref: master
```

Or for local development:

```yaml
dependencies:
  locker:
    path: ../locker
```

## Usage

### 1. Initialize the Locker

```dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:locker/locker/mfa_locker.dart';
import 'package:locker/security/models/password_cipher_func.dart';
import 'package:locker/storage/models/domain/entry_add_input.dart';
import 'package:locker/storage/models/domain/entry_meta.dart';
import 'package:locker/storage/models/domain/entry_update_input.dart';
import 'package:locker/storage/models/domain/entry_value.dart';
import 'package:locker/erasable/erasable_byte_array.dart';

// Create locker instance with storage file
final file = File('/path/to/secure_storage.json');
final locker = MFALocker(file: file);

// Check if storage is already initialized
final isInitialized = await locker.isStorageInitialized;
if (isInitialized) {
  // Storage exists — unlock instead of init
}

// Create password cipher function
final passwordCipherFunc = PasswordCipherFunc(
  password: 'user_password',  // Pass String directly
  salt: salt,  // Use locker.salt after first init, or generate new
);

// Create initial entry data
final initialEntryMeta = EntryMeta.fromErasable(
  erasable: ErasableByteArray(Uint8List.fromList(utf8.encode('My Secret'))),
);
final initialEntryValue = EntryValue.fromErasable(
  erasable: ErasableByteArray(Uint8List.fromList(utf8.encode('secret_data_here'))),
);

// Wrap initial entry data
final initialEntry = EntryAddInput(
  meta: initialEntryMeta,
  value: initialEntryValue,
);

// Initialize with password and first entry
await locker.init(
  passwordCipherFunc: passwordCipherFunc,
  initialEntries: [initialEntry],
  lockTimeout: Duration(minutes: 5),
);
```

### 2. Listen to Lock State

```dart
locker.stateStream.listen((state) {
  switch (state) {
    case LockerState.locked:
      print('Locker is locked - authentication required');
      break;
    case LockerState.unlocked:
      print('Locker is unlocked - ready for operations');
      break;
  }
});
```

### 3. Read and Write Entries

```dart
// Write a new entry
final entryMeta = EntryMeta.fromErasable(
  erasable: ErasableByteArray(Uint8List.fromList(utf8.encode('API Key'))),
);
final entryValue = EntryValue.fromErasable(
  erasable: ErasableByteArray(Uint8List.fromList(utf8.encode('sk-abc123...'))),
);

final entryId = await locker.write(
  input: EntryAddInput(meta: entryMeta, value: entryValue),
  cipherFunc: passwordCipherFunc,
);

// Read entry value
final value = await locker.readValue(
  id: entryId,
  cipherFunc: passwordCipherFunc,
);

// Load all metadata (unlocks the locker if locked)
await locker.loadAllMeta(passwordCipherFunc);
final allMeta = locker.allMeta;
for (final entry in allMeta.entries) {
  print('Entry ID: ${entry.key}');
}

// Update an entry (meta, value, or both)
final updatedMeta = EntryMeta.fromErasable(
  erasable: ErasableByteArray(Uint8List.fromList(utf8.encode('Updated API Key'))),
);
await locker.update(
  input: EntryUpdateInput(id: entryId, meta: updatedMeta),
  cipherFunc: passwordCipherFunc,
);

// Delete an entry
await locker.delete(id: entryId, cipherFunc: passwordCipherFunc);

// Erase all storage data (irreversible)
await locker.eraseStorage();
```

### 4. Configure Biometric Authentication

```dart
import 'package:locker/security/models/biometric_config.dart';
import 'package:locker/security/models/bio_cipher_func.dart';
import 'package:locker/locker/models/biometric_state.dart';

// Configure biometrics (call once at app startup)
await locker.configureBiometricCipher(
  BiometricConfig(
    promptTitle: 'Authenticate',
    promptSubtitle: 'Use biometrics to unlock your vault',
    androidCancelButtonText: 'Cancel',
    androidPromptDescription: 'Authenticate to access your secure storage',
  ),
);

// Check biometric availability
final biometricState = await locker.determineBiometricState();
if (biometricState.isAvailable) {
  // Biometrics available (availableButDisabled or enabled)
}

// Check biometric availability with key validation (no biometric prompt)
final state = await locker.determineBiometricState(
  biometricKeyTag: 'com.myapp.biometric_key',
);
if (state.isKeyInvalidated) {
  // Key was invalidated by biometric enrollment change — disable and re-setup
  await locker.teardownBiometry(
    passwordCipherFunc: passwordCipherFunc,
    biometricKeyTag: 'com.myapp.biometric_key',
  );
}

// Check if biometric unlock is currently enabled
final isEnabled = await locker.isBiometricEnabled;

// Enable biometric unlock (requires password confirmation)
final bioCipherFunc = BioCipherFunc(keyTag: 'com.myapp.biometric_key');
await locker.setupBiometry(
  bioCipherFunc: bioCipherFunc,
  passwordCipherFunc: passwordCipherFunc,
);

// Disable biometric unlock (password-only, no biometric prompt)
await locker.teardownBiometry(
  passwordCipherFunc: passwordCipherFunc,
);

// Disable biometric unlock and delete the hardware key
await locker.teardownBiometry(
  passwordCipherFunc: passwordCipherFunc,
  biometricKeyTag: 'com.myapp.biometric_key',
);
```

### 5. Lock Management

```dart
// Manual lock
locker.lock();

// Read current lock timeout
final timeout = await locker.lockTimeout;

// Update auto-lock timeout
await locker.updateLockTimeout(
  lockTimeout: Duration(minutes: 10),
  cipherFunc: passwordCipherFunc,
);
```

### 6. Change Password

Using old password:
```dart
await locker.changePassword(
  existingCipherFunc: PasswordCipherFunc(
    password: 'old_password',
    salt: await locker.salt,
  ),
  newCipherFunc: PasswordCipherFunc(
    password: 'new_password',
    salt: await locker.salt,
  ),
);
```

Using biometrics:
```dart
await locker.changePassword(
  existingCipherFunc: BioCipherFunc(keyTag: 'biometric'),
  newCipherFunc: PasswordCipherFunc(
    password: 'new_password',
    salt: await locker.salt,
  ),
);
```

### 7. Cleanup

```dart
// Dispose when done
locker.dispose();
```

### 8. Error Handling

The library throws three main exception types:

- **`DecryptFailedException`** — wrong password or corrupted data
- **`BiometricException`** — biometric auth failures; check `BiometricExceptionType` for specifics:
  - `cancel` — user dismissed the biometric prompt
  - `failure` — authentication failed (wrong fingerprint, lockout)
  - `keyInvalidated` — hardware key permanently invalidated after biometric enrollment change
  - `keyNotFound` — biometric key does not exist in secure hardware
  - `notAvailable` — biometrics not available on device
  - `notConfigured` — biometric cipher not configured
- **`StorageException`** — storage lifecycle errors (`notInitialized`, `alreadyInitialized`, `invalidStorage`, `entryNotFound`)

```dart
import 'package:locker/security/models/exceptions/biometric_exception.dart';
import 'package:locker/storage/models/exceptions/decrypt_failed_exception.dart';
import 'package:locker/storage/models/exceptions/storage_exception.dart';

try {
  await locker.loadAllMeta(cipherFunc);
} on DecryptFailedException {
  // Wrong password or corrupted data
} on BiometricException catch (e) {
  switch (e.type) {
    case BiometricExceptionType.cancel:
      // User cancelled — no action needed
    case BiometricExceptionType.keyInvalidated:
      // Key invalidated — disable biometrics and prompt re-setup
    default:
      // Other biometric failure
  }
} on StorageException catch (e) {
  // Storage error — check e.type for specifics
}
```

## Project Structure

```
locker/
├── lib/
│   ├── locker/           # Core locker interface (Locker) and implementation (MFALocker)
│   ├── security/         # Cipher functions, biometric config, BiometricCipherProvider
│   ├── storage/          # Encrypted storage interface and JSON file-backed implementation
│   ├── erasable/         # Secure memory management (ErasableByteArray)
│   └── utils/            # Cryptography utilities, reentrant lock (Sync), extensions
├── packages/
│   └── biometric_cipher/  # Native Flutter plugin wrapping TPM/Secure Enclave (iOS, macOS, Android, Windows)
├── example/              # Demo Flutter app (mfa_demo) — UI → BLoC → Repository → MFALocker
└── test/                 # Unit tests (mocktail)
```

## Example App

The `example/` directory contains a full Flutter demo app showcasing:
- Password-based storage initialization
- Biometric authentication setup and key invalidation recovery
- Entry CRUD operations
- Auto-lock behavior
- Settings management

To run the example:

```bash
cd example
fvm flutter pub get

# Generate freezed classes (required)
fvm dart run build_runner build --delete-conflicting-outputs

fvm flutter run
```

---

## Building for CI/CD

This project uses [fvm](https://fvm.app/) (Flutter Version Management) to ensure consistent Flutter/Dart versions across environments.

### Prerequisites

1. **Install fvm:**
   ```bash
   dart pub global activate fvm
   ```

2. **Configure fvm for the project:**
   ```bash
   fvm install
   fvm use
   ```

### CI/CD Build Commands

```bash
# Library — analyze, test, format
fvm flutter pub get
fvm dart analyze
fvm flutter test
fvm dart format . --line-length 120
fvm dart fix --apply

# Example app — common setup (required before any platform build)
cd example
fvm flutter pub get
fvm dart run build_runner build --delete-conflicting-outputs
```

Platform-specific build commands (run from `example/`):

| Platform | Command |
|----------|---------|
| Android  | `fvm flutter build apk --release` |
| iOS      | `fvm flutter build ios --release --no-codesign` |
| macOS    | `fvm flutter build macos --release` |
| Windows  | `fvm flutter build windows --release` |

### GitHub Actions Example

```yaml
name: CI

on:
  push:
    branches: [master]
  pull_request:
    branches: [master]

jobs:
  build:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - name: Install fvm
        run: dart pub global activate fvm

      - name: Setup Flutter via fvm
        run: |
          fvm install
          fvm flutter --version

      - name: Get dependencies
        run: fvm flutter pub get

      - name: Analyze
        run: fvm dart analyze

      - name: Run tests
        run: fvm flutter test

      - name: Check formatting
        run: fvm dart format --set-exit-if-changed .

      - name: Get example dependencies
        run: |
          cd example
          fvm flutter pub get

      - name: Generate freezed classes
        run: |
          cd example
          fvm dart run build_runner build --delete-conflicting-outputs

      - name: Build example (Android)
        run: |
          cd example
          fvm flutter build apk --release
```

### Environment Requirements

| Requirement | Version |
|-------------|---------|
| Dart SDK | ^3.11.0 |
| Flutter SDK | ^3.41.4 |
| fvm | Latest |

Flutter version is pinned via `.ci-flutter-version` (currently **3.41.4**). Use `fvm` to match.

---

## Contributing

This is a source-available project maintained by **AdGuard Software Limited**.

**We do not accept pull requests from external contributors.** Development is handled internally to ensure code quality, security standards, and alignment with our product roadmap.

However, we welcome:
- **Bug reports** - Help us identify and fix issues
- **Feature suggestions** - Share your ideas for improvements
- **Documentation improvements** - Point out errors or unclear sections

Please see [CONTRIBUTING.md](CONTRIBUTING.md) for details on how to report issues and suggest features.

## Security

The library implements the following security measures:
- **Encryption**: AES-GCM for all data at rest
- **Key derivation**: Argon2id password hashing with per-vault salt
- **Integrity verification**: HMAC-SHA256 detects storage tampering
- **Master key wrapping**: Random master key encrypted per auth method (password/biometric)
- **Biometric key management**: TPM/Secure Enclave hardware-backed keys via the `biometric_cipher` plugin
- **Biometric key invalidation**: Proactive detection via silent `isKeyValid` probe when biometric enrollment changes (no biometric prompt); `BioCipherFunc` also performs fallback key validity checks during decrypt failures
- **Memory safety**: `ErasableByteArray` zeroes sensitive data on `erase()`; all operations auto-erase arguments in `finally` blocks

## License

MIT License

Copyright (c) 2026 AdGuard Software Limited

See [LICENSE](LICENSE) for details.
