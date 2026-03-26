# Phase 12: Locker — `BiometricState.keyInvalidated` + Proactive `determineBiometricState`

**Goal:** Add proactive key validity detection at init time — `determineBiometricState()` returns `BiometricState.keyInvalidated` when the hardware key is permanently invalidated, without triggering a biometric prompt.

## Context

### Feature Motivation

Phases 1–11 handle **reactive** detection: the app discovers `keyInvalidated` only when the user triggers a biometric operation (e.g., tapping the biometric unlock button). This causes the lock screen to briefly show the biometric button before hiding it.

Phase 12 adds **proactive** detection at the locker library level: `determineBiometricState()` checks key validity before returning `enabled`, so callers can hide the biometric button immediately at init time.

### Infrastructure Already in Place

- **Phase 9** — Android: `isKeyValid(tag)` channel handler using `Cipher.init()` probe (no `BiometricPrompt`).
- **Phase 10** — iOS/macOS: `isKeyValid(tag)` channel handler using `keyExists()` with `kSecUseAuthenticationUISkip` (no prompt).
- **Phase 11** — Dart plugin: `BiometricCipher.isKeyValid(tag)` public method on the platform interface.

Phase 12 wires this into the locker library: `BiometricCipherProvider.isKeyValid` → called from `MFALocker.determineBiometricState`.

### Call Path (Phases 9–12 Complete)

```
MFALocker.determineBiometricState(biometricKeyTag: tag)  [Phase 12]
  → _secureProvider.isKeyValid(tag: tag)                 [Phase 12 — BiometricCipherProvider]
  → _biometricCipher.isKeyValid(tag: tag)                [Phase 12 — BiometricCipherProviderImpl]
  → BiometricCipher.isKeyValid(tag: tag)                 [Phase 11]
  → MethodChannel("isKeyValid", tag)
  → Android: Cipher.init() probe                         [Phase 9]
  → iOS/macOS: keyExists() probe                         [Phase 10]
```

### Backwards Compatibility

`biometricKeyTag` is optional on `determineBiometricState`. Callers that don't pass it get the existing behavior (no key validity check, returns `enabled` as before).

### New State Value

`BiometricState.keyInvalidated` sits logically after `enabled` in the enum. Like `enabled`, it assumes biometrics are available in hardware and enrolled — the only difference is the hardware key is gone. Getters:
- `isKeyInvalidated` → `true` only for this value
- `isEnabled` → `false` (not usable for auth)
- `isAvailable` → `false` (key is permanently gone)

## Tasks

- [x] **12.1** Add `keyInvalidated` to `BiometricState` enum + `isKeyInvalidated` getter
  - File: `lib/locker/models/biometric_state.dart`
  - Add `keyInvalidated` value (after `enabled`)
  - Add `bool get isKeyInvalidated => this == keyInvalidated`

- [x] **12.2** Add `isKeyValid` to `BiometricCipherProvider` abstract class
  - File: `lib/security/biometric_cipher_provider.dart`
  - Add `Future<bool> isKeyValid({required String tag})`

- [x] **12.3** Implement `isKeyValid` in `BiometricCipherProviderImpl`
  - File: `lib/security/providers/biometric_cipher_provider_impl.dart`
  - Delegate: `_biometricCipher.isKeyValid(tag: tag)`

- [x] **12.4** Add optional `biometricKeyTag` parameter to `determineBiometricState` in `Locker` interface
  - File: `lib/locker/locker.dart`
  - Change signature to: `Future<BiometricState> determineBiometricState({String? biometricKeyTag})`

- [x] **12.5** Implement key validity check in `MFALocker.determineBiometricState`
  - File: `lib/locker/mfa_locker.dart`
  - After confirming biometrics are enabled in settings, before returning `enabled`:
  - If `biometricKeyTag != null`: call `_secureProvider.isKeyValid(tag: biometricKeyTag)`
  - If `!isValid` → return `BiometricState.keyInvalidated`
  - Backwards compatible: callers without `biometricKeyTag` get existing behavior

## Acceptance Criteria

**Test:** `fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` + `fvm flutter test`

- `BiometricState.keyInvalidated` exists as an enum value.
- `BiometricState.keyInvalidated.isKeyInvalidated` → `true`.
- `BiometricState.enabled.isKeyInvalidated` → `false`.
- `BiometricState.keyInvalidated.isEnabled` → `false`.
- `BiometricState.keyInvalidated.isAvailable` → `false`.
- `BiometricCipherProvider.isKeyValid(tag:)` is declared on the abstract class.
- `BiometricCipherProviderImpl.isKeyValid(tag:)` delegates to `_biometricCipher.isKeyValid(tag: tag)`.
- `determineBiometricState(biometricKeyTag: tag)` returns `BiometricState.keyInvalidated` when `isKeyValid` returns `false` and biometrics are enabled in settings.
- `determineBiometricState()` without `biometricKeyTag` returns `BiometricState.enabled` when biometrics are available and enabled (no key check).

## Dependencies

- Phase 11 complete (`BiometricCipher.isKeyValid(tag)` on the platform interface)
- `BiometricCipherProvider` and `BiometricCipherProviderImpl` already exist
- `MFALocker.determineBiometricState` already exists — this adds an optional parameter and one conditional block

## Technical Details

### Task 12.1 — `BiometricState.keyInvalidated`

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

  bool get isAvailable => this == availableButDisabled || this == enabled;
  bool get isEnabled => this == enabled;
  bool get isKeyInvalidated => this == keyInvalidated;  // new
}
```

### Task 12.2 — `BiometricCipherProvider` abstract method

```dart
/// Returns `true` if the biometric key identified by [tag] exists and is valid.
/// Does not trigger a biometric prompt.
Future<bool> isKeyValid({required String tag});
```

Add alongside existing `encrypt`, `decrypt`, `deleteKey` signatures. Follow the same pattern — abstract, no default body.

### Task 12.3 — `BiometricCipherProviderImpl` implementation

```dart
@override
Future<bool> isKeyValid({required String tag}) => _biometricCipher.isKeyValid(tag: tag);
```

One-liner delegation. No error mapping needed — `BiometricCipher.isKeyValid` returns `false` for invalid/missing keys (no exception thrown for the not-found case).

### Task 12.4 — `Locker` interface signature update

```dart
Future<BiometricState> determineBiometricState({String? biometricKeyTag});
```

### Task 12.5 — `MFALocker.determineBiometricState` key validity check

Insert after the `isEnabledInSettings` check, before the final `return BiometricState.enabled`:

```dart
// Proactive key validity check — no biometric prompt shown.
if (biometricKeyTag != null) {
  final isValid = await _secureProvider.isKeyValid(tag: biometricKeyTag);
  if (!isValid) {
    return BiometricState.keyInvalidated;
  }
}

return BiometricState.enabled;
```

The check is gated on `biometricKeyTag != null` for backwards compatibility. Only callers that opt in (by passing a tag) get the proactive check.

## Implementation Notes

- Tasks 12.1 → 12.2 → 12.3 → 12.4 → 12.5 must be done in order (each step builds on the previous).
- Do not add logging — `isKeyValid` is a pure query with no side effects.
- Do not change any existing `determineBiometricState` behavior when `biometricKeyTag` is `null`.
- Phase 13 (tests) and Phase 14 (example app integration) depend on this phase being complete.
