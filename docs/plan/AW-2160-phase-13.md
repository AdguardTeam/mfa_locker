# Plan: AW-2160 Phase 13 -- Locker: `BiometricState.keyInvalidated` + Proactive `determineBiometricState`

Status: PLAN_APPROVED

## Phase Scope

Add proactive key validity detection at the Dart locker library level so that `determineBiometricState()` can return `BiometricState.keyInvalidated` at init time -- before any user-triggered biometric operation -- eliminating the biometric button flash on the lock screen.

Five changes across four existing files in `lib/`. No new files. No native code. No example app changes (Phase 15 handles that). All changes are additive and backwards compatible.

### Critical Finding: Implementation Already Exists

Research confirms that all five tasks (13.1 through 13.5) have already been implemented in the codebase. The corresponding Phase 14 tests (14.1 through 14.4) are also already present and passing. The tasklist (`docs/tasklist-2160.md`) is stale -- it still marks Phase 13 tasks as "not started."

The remaining work for this phase is:
1. Verify that `fvm flutter analyze` and `fvm flutter test` pass cleanly.
2. Update the tasklist to mark tasks 13.1 through 13.5 as done.

---

## Components

| Component | File | Change | Status |
|-----------|------|--------|--------|
| `BiometricState` enum | `lib/locker/models/biometric_state.dart` | + `keyInvalidated` value (line 28), + `isKeyInvalidated` getter (line 38) | Already implemented |
| `BiometricCipherProvider` abstract | `lib/security/biometric_cipher_provider.dart` | + `isKeyValid({required String tag})` abstract method (line 56) | Already implemented |
| `BiometricCipherProviderImpl` | `lib/security/biometric_cipher_provider.dart` | + `isKeyValid` delegation to `_biometricCipher.isKeyValid(tag: tag)` (line 118) | Already implemented |
| `Locker` interface | `lib/locker/locker.dart` | + `{String? biometricKeyTag}` param on `determineBiometricState` (line 183) | Already implemented |
| `MFALocker` implementation | `lib/locker/mfa_locker.dart` | + key validity check at lines 329-334 in `determineBiometricState` | Already implemented |

### File Structure Note

The phase doc and tasklist reference `lib/security/providers/biometric_cipher_provider_impl.dart` for Task 13.3, but this file does not exist. `BiometricCipherProviderImpl` lives in `lib/security/biometric_cipher_provider.dart` alongside the abstract class. The implementation is correct as-is.

---

## API Contract

### `BiometricState` enum (modified)

```dart
enum BiometricState {
  tpmUnsupported, tpmVersionIncompatible, hardwareUnavailable, notEnrolled,
  disabledByPolicy, securityUpdateRequired, availableButDisabled, enabled,
  keyInvalidated,  // NEW -- 9th value
  ;

  bool get isAvailable => this == availableButDisabled || this == enabled;
  bool get isEnabled => this == enabled;
  bool get isKeyInvalidated => this == keyInvalidated;  // NEW getter
}
```

Semantics: `keyInvalidated.isAvailable == false`, `keyInvalidated.isEnabled == false`, `keyInvalidated.isKeyInvalidated == true`. It is an error state, distinct from `availableButDisabled` (where the hardware key may still be valid).

### `BiometricCipherProvider` (modified)

```dart
abstract class BiometricCipherProvider {
  // ... existing methods ...
  Future<bool> isKeyValid({required String tag});  // NEW
}
```

### `Locker` interface (modified)

```dart
Future<BiometricState> determineBiometricState({String? biometricKeyTag});  // param added
```

Backwards compatible: omitting `biometricKeyTag` produces identical behavior to before.

### `MFALocker.determineBiometricState` (modified)

New logic inserted after the `!isEnabledInSettings` guard, before the `return BiometricState.enabled` fallthrough:

```dart
if (biometricKeyTag != null) {
  final isValid = await _secureProvider.isKeyValid(tag: biometricKeyTag);
  if (!isValid) return BiometricState.keyInvalidated;
}
```

---

## Data Flows

### Proactive Detection Flow (new)

```
App init / lock screen mount
  |
  v
determineBiometricState(biometricKeyTag: "biometric")
  |
  +-- TPM check (existing) --> tpmUnsupported / tpmVersionIncompatible
  +-- Biometry check (existing) --> hardwareUnavailable / notEnrolled / disabledByPolicy / securityUpdateRequired
  +-- App settings check (existing) --> availableButDisabled
  |
  +-- NEW: biometricKeyTag != null && isEnabledInSettings
        |
        +-- _secureProvider.isKeyValid(tag: biometricKeyTag)
              |
              +-- false --> BiometricState.keyInvalidated (EARLY RETURN)
              +-- true  --> fall through to BiometricState.enabled
```

### Provider Delegation (new)

```
MFALocker._secureProvider.isKeyValid(tag)
  --> BiometricCipherProviderImpl.isKeyValid(tag)
    --> BiometricCipher.isKeyValid(tag: tag)   [Phase 12 plugin API]
      --> Platform method channel "isKeyValid"
        --> Android: Cipher.init() probe (no BiometricPrompt)
        --> iOS/macOS: SecItemCopyMatching with kSecUseAuthenticationUISkip
        --> Windows: KeyCredentialManager.OpenAsync() (no signing)
```

### Guard Conditions

The `isKeyValid` call is skipped when:
- `biometricKeyTag` is null (backwards compatibility)
- `isEnabledInSettings` is false (irrelevant when biometrics disabled; exits early as `availableButDisabled`)
- Any hardware/TPM check fails (exits early before reaching the key check)

---

## NFR

| Requirement | How Met |
|-------------|---------|
| No biometric prompt | `isKeyValid` uses silent platform probes (Phases 9-11); no user interaction |
| Backwards compatibility | `biometricKeyTag` is `String?`; omitting it produces pre-Phase 13 behavior |
| No logging | Silent probe with no observable side effects; phase spec prohibits logging |
| No new files | All changes are additions to existing files |
| Memory safety | No new sensitive data handled; `isKeyValid` returns a simple `bool` |
| Performance | `isKeyValid` is a single platform call (~1-5ms); acceptable at init time |

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| New `keyInvalidated` enum value breaks downstream exhaustive switches | Low | Medium | Adding a value to a non-sealed enum causes compile errors in exhaustive switches, which is helpful -- forces consumers to handle the new state |
| `isKeyValid` unexpectedly triggers a biometric prompt (regression in Phases 9-11) | Very low | High | Platform implementations are specifically tested for this property; unit tests mock the provider |
| `isKeyValid` throws an unhandled exception | Low | Medium | No try-catch added intentionally; exception propagation to caller is by design; same behavior as any other provider error |
| Tasklist staleness causes duplicate implementation work | Medium | Low | Research confirmed code is already present; plan documents this finding clearly |

---

## Dependencies

### On Previous Phases

| Phase | Dependency | Status |
|-------|-----------|--------|
| Phase 12 | `BiometricCipher.isKeyValid(tag)` Dart plugin API must exist | Complete |
| Phases 9-11 | Native `isKeyValid` implementations on all platforms | Complete |
| Phase 4 | `BiometricExceptionType.keyInvalidated` in locker exception hierarchy | Complete |

### Task Ordering Within Phase

- Tasks 13.1, 13.2, 13.3 are independent of each other.
- Task 13.4 (interface signature) must precede Task 13.5 (implementation).
- All of 13.1-13.3 must be complete before 13.5 (the implementation references `BiometricState.keyInvalidated` and `_secureProvider.isKeyValid`).

### Forward Dependencies

- Phase 14 (tests) depends on this phase. Tests are already implemented.
- Phase 15 (example app integration) wires `biometricKeyTag` through `LockerBiometricMixin`. Phase 15 is already marked complete.

---

## Implementation Approach

Given that all code and tests are already present in the codebase:

1. **Verify** -- Run `fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` and `fvm flutter test` at the root to confirm everything passes.
2. **Update tasklist** -- Mark tasks 13.1 through 13.5 as done in `docs/tasklist-2160.md`.
3. **No code changes needed** -- The implementation matches the spec exactly.

If verification reveals failures, investigate and fix. Otherwise, the phase is complete.

---

## Open Questions

None. The research confirms that all five tasks are already implemented, all Phase 14 tests exist and cover the acceptance criteria, and the implementation exactly matches the spec from the phase doc, idea doc (Sections G4-G6), and vision doc (Section 4).
