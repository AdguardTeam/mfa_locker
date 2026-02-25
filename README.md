# Locker

A secure storage library for Dart/Flutter applications that provides encrypted key-value storage with multi-factor authentication support (password + biometrics).

## Features

- **AES-GCM Encryption** — All data is encrypted using industry-standard AES-GCM algorithm
- **Password Protection** — PBKDF2 key derivation from user password
- **Biometric Authentication** — Optional biometric unlock via TPM/Secure Enclave (iOS, macOS, Android, Windows)
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
import 'package:locker/storage/models/domain/entry_meta.dart';
import 'package:locker/storage/models/domain/entry_value.dart';
import 'package:locker/erasable/erasable_byte_array.dart';

// Create locker instance with storage file
final file = File('/path/to/secure_storage.json');
final locker = MFALocker(file: file);

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

// Initialize with password and first entry
await locker.init(
  passwordCipherFunc: passwordCipherFunc,
  initialEntryMeta: initialEntryMeta,
  initialEntryValue: initialEntryValue,
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
  entryMeta: entryMeta,
  entryValue: entryValue,
  cipherFunc: passwordCipherFunc,
);

// Read entry value
final value = await locker.readValue(
  id: entryId,
  cipherFunc: passwordCipherFunc,
);

// Load all metadata (locker must be unlocked)
final allMeta = await locker.loadAllMeta(cipherFunc: passwordCipherFunc);
for (final entry in allMeta.entries) {
  print('Entry ID: ${entry.key}');
}

// Delete an entry
await locker.delete(id: entryId, cipherFunc: passwordCipherFunc);
```

### 4. Configure Biometric Authentication

```dart
import 'package:locker/security/models/biometric_config.dart';
import 'package:locker/security/models/bio_cipher_func.dart';

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
if (biometricState == BiometricState.availableButDisabled) {
  // Biometrics available, can be enabled
}

// Enable biometric unlock (requires password confirmation)
final bioCipherFunc = BioCipherFunc(keyTag: 'com.myapp.biometric_key');
await locker.setupBiometry(
  bioCipherFunc: bioCipherFunc,
  passwordCipherFunc: passwordCipherFunc,
);

// Disable biometric unlock
await locker.teardownBiometry(
  bioCipherFunc: bioCipherFunc,
  passwordCipherFunc: passwordCipherFunc,
);
```

### 5. Lock Management

```dart
// Manual lock
locker.lock();

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

## Project Structure

```
locker/
├── lib/
│   ├── locker/           # Core locker interface and implementation
│   ├── security/         # Cipher functions, biometric config
│   ├── storage/          # Encrypted storage implementation
│   ├── erasable/         # Secure memory management
│   └── utils/            # Utilities
├── packages/
│   └── biometric_cipher/  # TPM/biometric plugin (iOS, macOS, Android, Windows)
├── example/              # Demo Flutter app (mfa_demo)
├── test/                 # Unit tests
└── docs/                 # Documentation
```

## Example App

The `example/` directory contains a full Flutter demo app showcasing:
- Password-based storage initialization
- Biometric authentication setup
- Entry CRUD operations
- Auto-lock behavior
- Settings management

To run the example:

```bash
cd example
flutter pub get

# Generate freezed classes (required)
dart run build_runner build --delete-conflicting-outputs

flutter run
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

#### Using fvm

```bash
# Install dependencies
fvm flutter pub get

# Run analyzer
fvm dart analyze

# Run tests
fvm flutter test

# Build example app (Android)
cd example
fvm flutter pub get
fvm dart run build_runner build --delete-conflicting-outputs
fvm flutter build apk --release

# Build example app (iOS)
cd example
fvm flutter pub get
fvm dart run build_runner build --delete-conflicting-outputs
fvm flutter build ios --release --no-codesign

# Build example app (macOS)
cd example
fvm flutter pub get
fvm dart run build_runner build --delete-conflicting-outputs
fvm flutter build macos --release

# Build example app (Windows)
cd example
fvm flutter pub get
fvm dart run build_runner build --delete-conflicting-outputs
fvm flutter build windows --release
```

#### Format and Lint

```bash
# Format code
fvm dart format . --line-length 120

# Apply dart fixes
fvm dart fix --apply
```

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
| Dart SDK | >= 3.5.0 < 4.0.0 |
| Flutter SDK | >= 3.35.0 |
| fvm | Latest |

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

See [docs/MFA_Locker.md](docs/MFA_Locker.md) for detailed information about:
- Encryption algorithms (AES-GCM, HMAC-SHA256, PBKDF2)
- Storage file structure
- Key derivation and wrapping
- Biometric key management via TPM/Secure Enclave

## License

MIT License

Copyright (c) 2026 AdGuard Software Limited

See [LICENSE](LICENSE) for details.
