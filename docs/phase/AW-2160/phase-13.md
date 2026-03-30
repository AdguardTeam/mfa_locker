# Phase 13: Locker — `BiometricState.keyInvalidated` + Proactive `determineBiometricState`

**Goal:** Add proactive key validity detection at init time — `determineBiometricState()` returns `BiometricState.keyInvalidated` when the hardware key is permanently invalidated, without triggering a biometric prompt.

**Ref:** `docs/idea-2160.md` Sections G4, G5, G6

## Context

### Feature Motivation

Phases 1–8 implement **reactive** detection: `keyInvalidated` is discovered only when the user triggers a biometric operation. This causes the lock screen to briefly show the biometric button before hiding it after a failed attempt.

Phases 9–12 built the silent key validity probe on all platforms:
- **Phase 9 (Android):** `Cipher.init()` probe — `KeyPermanentlyInvalidatedException` → `false`
- **Phase 10 (iOS/macOS):** `keyExists()` with `kSecUseAuthenticationUISkip` — no auth prompt → `false` if key is gone
- **Phase 11 (Windows):** `KeyCredentialManager::OpenAsync()` status check — no signing → `false` if credential not found
- **Phase 12 (Dart plugin):** `BiometricCipher.isKeyValid(tag)` — public API wiring all three platforms

This phase adds **proactive** detection at the locker library level: `determineBiometricState()` checks key validity at init time and returns `BiometricState.keyInvalidated` when the hardware key is permanently invalidated. The lock screen can immediately show password-only mode — no biometric button flash.

### Proactive Detection Flow

```
determineBiometricState(biometricKeyTag: "biometric")
  │
  ├── Existing checks: TPM → biometry hardware → app settings
  │
  └── NEW: if biometricKeyTag provided && biometrics enabled in settings:
        │
        ├── _secureProvider.isKeyValid(tag: biometricKeyTag)
        │     │
        │     ├── Android: Cipher.init() — no BiometricPrompt
        │     │   └── KeyPermanentlyInvalidatedException → false
        │     │
        │     ├── iOS/macOS: keyExists() with kSecUseAuthenticationUISkip
        │     │   └── errSecItemNotFound → false
        │     │
        │     └── Windows: KeyCredentialManager.OpenAsync() — no signing
        │         └── KeyCredentialStatus::NotFound → false
        │
        ├── isValid == false → return BiometricState.keyInvalidated
        └── isValid == true  → return BiometricState.enabled
```

**Key property:** `isKeyValid()` never triggers a biometric prompt on any platform. `biometricKeyTag` is optional — callers without it get existing behavior (backwards compatible).

### Files Changed

```
lib/
├── locker/
│   ├── models/
│   │   └── biometric_state.dart              # + keyInvalidated enum value + isKeyInvalidated getter
│   ├── locker.dart                           # + biometricKeyTag param on determineBiometricState
│   └── mfa_locker.dart                       # + key validity check in determineBiometricState
└── security/
    ├── biometric_cipher_provider.dart        # + isKeyValid(tag) abstract method
    └── providers/
        └── biometric_cipher_provider_impl.dart  # + isKeyValid(tag) implementation
```

No new files. All changes are additions to existing files.

## Tasks

- [ ] **13.1** Add `keyInvalidated` to `BiometricState` enum + `isKeyInvalidated` getter
  - File: `lib/locker/models/biometric_state.dart`
  - Add `keyInvalidated` value (after `enabled`)
  - Add `bool get isKeyInvalidated => this == keyInvalidated`

- [ ] **13.2** Add `isKeyValid` to `BiometricCipherProvider` abstract class
  - File: `lib/security/biometric_cipher_provider.dart`
  - Add `Future<bool> isKeyValid({required String tag})`

- [ ] **13.3** Implement `isKeyValid` in `BiometricCipherProviderImpl`
  - File: `lib/security/providers/biometric_cipher_provider_impl.dart`
  - Delegate: `_biometricCipher.isKeyValid(tag: tag)`

- [ ] **13.4** Add optional `biometricKeyTag` parameter to `determineBiometricState` in `Locker` interface
  - File: `lib/locker/locker.dart`
  - Change signature to: `Future<BiometricState> determineBiometricState({String? biometricKeyTag})`

- [ ] **13.5** Implement key validity check in `MFALocker.determineBiometricState`
  - File: `lib/locker/mfa_locker.dart`
  - After confirming biometrics are enabled in settings, before returning `enabled`:
  - If `biometricKeyTag != null`: call `_secureProvider.isKeyValid(tag: biometricKeyTag)`
  - If `!isValid` → return `BiometricState.keyInvalidated`
  - Backwards compatible: callers without `biometricKeyTag` get existing behavior

## Acceptance Criteria

**Test:** `fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` + `fvm flutter test`

- `BiometricState.keyInvalidated` exists as an enum value
- `BiometricState.keyInvalidated.isKeyInvalidated` returns `true`
- `BiometricState.enabled.isKeyInvalidated` returns `false`
- `BiometricState.keyInvalidated.isEnabled` returns `false`
- `BiometricState.keyInvalidated.isAvailable` returns `false`
- `determineBiometricState(biometricKeyTag: tag)` returns `keyInvalidated` when `isKeyValid` returns `false` and biometrics are enabled in settings
- `determineBiometricState()` without `biometricKeyTag` retains existing behavior (no key validity check)
- Analysis passes with no warnings or infos

## Dependencies

- Phase 12 complete (`BiometricCipher.isKeyValid(tag)` Dart plugin API done)
- `_secureProvider.isKeyValid(tag:)` must be reachable from `MFALocker` — requires tasks 13.2 and 13.3 first

## Technical Details

### Task 13.1 — `BiometricState` enum (`biometric_state.dart`)

```dart
enum BiometricState {
  tpmUnsupported,
  tpmVersionIncompatible,
  hardwareUnavailable,
  notEnrolled,
  disabledByPolicy,
  securityUpdateRequired,
  availableButDisabled,
  enabled,
  keyInvalidated,  // new — hardware key permanently invalidated after biometric enrollment change
  ;

  /// Whether biometric is available for use (not an error state)
  bool get isAvailable => this == availableButDisabled || this == enabled;

  /// Whether biometric is currently enabled
  bool get isEnabled => this == enabled;

  /// Whether the biometric key has been permanently invalidated
  bool get isKeyInvalidated => this == keyInvalidated;
}
```

Note: `keyInvalidated` is NOT included in `isAvailable` or `isEnabled` — it is an error state that happens to have the `Origin.bio` wrap present in storage.

### Task 13.2 — Abstract method in `BiometricCipherProvider` (`biometric_cipher_provider.dart`)

```dart
/// Returns `true` if the biometric key identified by [tag] exists and is valid.
/// Does not trigger a biometric prompt.
Future<bool> isKeyValid({required String tag});
```

Add alongside existing abstract methods (`deleteKey`, `encrypt`, `decrypt`, etc.).

### Task 13.3 — Implementation in `BiometricCipherProviderImpl` (`biometric_cipher_provider_impl.dart`)

```dart
@override
Future<bool> isKeyValid({required String tag}) => _biometricCipher.isKeyValid(tag: tag);
```

### Task 13.4 — Interface signature in `Locker` (`locker.dart`)

```dart
Future<BiometricState> determineBiometricState({String? biometricKeyTag});
```

The parameter is optional (`String?`) to preserve backwards compatibility. Existing callers with no arguments continue to work unchanged.

### Task 13.5 — Key validity check in `MFALocker` (`mfa_locker.dart`)

```dart
@override
Future<BiometricState> determineBiometricState({String? biometricKeyTag}) async {
  final tpmStatus = await _secureProvider.getTPMStatus();
  if (tpmStatus == TPMStatus.unsupported) {
    return BiometricState.tpmUnsupported;
  }
  if (tpmStatus == TPMStatus.tpmVersionUnsupported) {
    return BiometricState.tpmVersionIncompatible;
  }

  final biometryStatus = await _secureProvider.getBiometryStatus();

  if (biometryStatus == BiometricStatus.unsupported ||
      biometryStatus == BiometricStatus.deviceNotPresent ||
      biometryStatus == BiometricStatus.deviceBusy) {
    return BiometricState.hardwareUnavailable;
  }
  if (biometryStatus == BiometricStatus.notConfiguredForUser) {
    return BiometricState.notEnrolled;
  }
  if (biometryStatus == BiometricStatus.disabledByPolicy) {
    return BiometricState.disabledByPolicy;
  }
  if (biometryStatus == BiometricStatus.androidBiometricErrorSecurityUpdateRequired) {
    return BiometricState.securityUpdateRequired;
  }

  final isEnabledInSettings = await isBiometricEnabled;
  if (!isEnabledInSettings) {
    return BiometricState.availableButDisabled;
  }

  // Proactive key validity check — no biometric prompt shown.
  if (biometricKeyTag != null) {
    final isValid = await _secureProvider.isKeyValid(tag: biometricKeyTag);
    if (!isValid) {
      return BiometricState.keyInvalidated;
    }
  }

  return BiometricState.enabled;
}
```

## Implementation Notes

- Tasks 13.1 → 13.2 → 13.3 can be done in any order within the group, but must all complete before 13.4 and 13.5.
- Tasks 13.4 → 13.5 must be done in order: the interface must declare `biometricKeyTag` before the implementation can override it.
- The key validity check only runs when `biometricKeyTag` is provided AND biometrics are enabled in settings. This prevents a key validity call when biometrics are already disabled — the `isKeyValid` result is irrelevant in that case.
- Do not add logging for the key validity check — it is a silent probe with no side effects.
- The `isKeyInvalidated` getter follows the same pattern as `isEnabled` and `isAvailable` — a simple equality check.
- Phase 15 (example app integration) already passes `biometricKeyTag` in `determineBiometricState` — once this phase is complete, that integration becomes active.
