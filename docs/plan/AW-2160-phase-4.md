# Plan: AW-2160 Phase 4 -- Locker Layer: Map `keyPermanentlyInvalidated` to `BiometricExceptionType.keyInvalidated`

Status: PLAN_APPROVED

## Phase Scope

Phase 4 closes the locker-layer gap in the error propagation chain. Phases 1-3 wired the entire path from native platforms through the Dart plugin to produce `BiometricCipherExceptionCode.keyPermanentlyInvalidated`. Currently, the locker layer's `_mapExceptionToBiometricException` has no arm for this code -- it falls through to the `_ =>` wildcard and is treated as a generic `BiometricExceptionType.failure`. The app layer cannot distinguish permanent key invalidation from a wrong-fingerprint error.

This phase adds:
1. A new enum value `keyInvalidated` to `BiometricExceptionType`.
2. A new switch arm in `_mapExceptionToBiometricException` mapping `keyPermanentlyInvalidated` to `keyInvalidated`.
3. A unit test verifying the new mapping (and confirming existing mappings are unaffected).

After this phase, the app layer receives `BiometricExceptionType.keyInvalidated` as a distinct, actionable error type, enabling the targeted recovery path in Phase 5.

---

## Components

### Affected

| Component | File | Change |
|-----------|------|--------|
| `BiometricExceptionType` enum | `lib/security/models/exceptions/biometric_exception.dart` | Add `keyInvalidated` enum value (position 7, appended after `notConfigured`) with a `///` doc comment |
| `BiometricCipherProviderImpl._mapExceptionToBiometricException()` | `lib/security/biometric_cipher_provider.dart` | Add one new switch arm: `BiometricCipherExceptionCode.keyPermanentlyInvalidated => const BiometricException(BiometricExceptionType.keyInvalidated)` immediately before the `_ =>` wildcard |
| New test file | `test/security/biometric_cipher_provider_test.dart` | Unit tests for the `keyPermanentlyInvalidated` mapping via `encrypt()`/`decrypt()` on a provider with a mock `BiometricCipher` |

### Unaffected (verified safe)

| Component | File | Why unaffected |
|-----------|------|---------------|
| `BiometricCipherExceptionCode` | `packages/biometric_cipher/lib/data/biometric_cipher_exception_code.dart` | Already has `keyPermanentlyInvalidated` (Phase 3 complete) |
| Example app `locker_bloc.dart` | `example/lib/features/locker/bloc/locker_bloc.dart` | Exhaustive switch statement on `BiometricExceptionType` will need `keyInvalidated` case, but `example/` is a separate package -- root `flutter analyze` does not scan it. Deferred to Phase 5 |
| Example app `settings_bloc.dart` | `example/lib/features/settings/bloc/settings_bloc.dart` | Same as above -- deferred to Phase 5 |
| `MFALocker` | `lib/locker/mfa_locker.dart` | No switch on `BiometricExceptionType`; propagates `BiometricException` to callers unchanged |

---

## API Contract

### Modified API

**`BiometricExceptionType` enum** (additive only):

```dart
enum BiometricExceptionType {
  cancel,
  failure,
  keyNotFound,
  keyAlreadyExists,
  notAvailable,
  notConfigured,

  /// Hardware-backed biometric key permanently invalidated due to a biometric enrollment change.
  keyInvalidated,  // NEW -- position 7
}
```

### Modified internal mapping

**`BiometricCipherProviderImpl._mapExceptionToBiometricException()`** -- one new arm added:

```dart
BiometricException _mapExceptionToBiometricException(BiometricCipherException e) => switch (e.code) {
      // ... existing arms unchanged ...
      BiometricCipherExceptionCode.configureError => const BiometricException(BiometricExceptionType.notConfigured),
      BiometricCipherExceptionCode.keyPermanentlyInvalidated =>                        // NEW
        const BiometricException(BiometricExceptionType.keyInvalidated),               // NEW
      _ => BiometricException(BiometricExceptionType.failure, originalError: e),       // unchanged
    };
```

### No new public APIs

No new classes, interfaces, or methods on `BiometricCipherProvider`. The enum value addition is the only public API change.

---

## Data Flows

### Before Phase 4

```
BiometricCipherExceptionCode.keyPermanentlyInvalidated
  -> _mapExceptionToBiometricException
  -> Falls through _ => BiometricException(BiometricExceptionType.failure, originalError: e)
  -> App receives "failure" -- cannot distinguish from wrong fingerprint
```

### After Phase 4

```
BiometricCipherExceptionCode.keyPermanentlyInvalidated
  -> _mapExceptionToBiometricException
  -> Explicit arm: const BiometricException(BiometricExceptionType.keyInvalidated)
  -> App receives "keyInvalidated" -- can offer targeted recovery (Phase 5)
```

### Complete error propagation chain (all phases)

```
Android: KeyPermanentlyInvalidatedException -> FlutterError("KEY_PERMANENTLY_INVALIDATED")  [Phase 1]
iOS/macOS: Secure Enclave key inaccessible -> FlutterError("KEY_PERMANENTLY_INVALIDATED")   [Phase 2]
  -> Dart plugin: BiometricCipherExceptionCode.keyPermanentlyInvalidated                    [Phase 3]
  -> Locker: BiometricExceptionType.keyInvalidated                                          [Phase 4]
  -> App: catches keyInvalidated -> teardownBiometryPasswordOnly                            [Phase 5]
```

### Unchanged flows (must not regress)

- Wrong fingerprint -> `authenticationError` -> `BiometricExceptionType.failure`
- User cancels prompt -> `authenticationUserCanceled` -> `BiometricExceptionType.cancel`
- Device lockout -> `authenticationError` -> `BiometricExceptionType.failure`
- Encryption/decryption error -> `BiometricExceptionType.failure`

---

## Testing Strategy

### Testability challenge

`BiometricCipherProviderImpl._mapExceptionToBiometricException()` is a private method. `BiometricCipherProviderImpl` uses a private constructor (`._()`) and a singleton `instance`. The `_biometricCipher` field is constructed inline (not injected). Direct unit testing of the mapping is not possible without a structural change.

### Chosen approach: `@visibleForTesting` constructor with injectable `BiometricCipher`

Add a `@visibleForTesting` named constructor to `BiometricCipherProviderImpl` that accepts a `BiometricCipher` parameter. This follows the exact same pattern used by `MFALocker` (which accepts a `storage` parameter via `@visibleForTesting`). The mapping can then be tested indirectly through `encrypt()` or `decrypt()` on a provider instance holding a mock `BiometricCipher` configured to throw `BiometricCipherException(code: keyPermanentlyInvalidated, ...)`.

Changes to `BiometricCipherProviderImpl`:

```dart
@visibleForTesting
BiometricCipherProviderImpl.forTesting(this._biometricCipher);
```

The existing `_biometricCipher` field changes from `final BiometricCipher _biometricCipher = BiometricCipher()` to be initialized in the constructor:

```dart
BiometricCipherProviderImpl._() : _biometricCipher = BiometricCipher();
```

### New test file: `test/security/biometric_cipher_provider_test.dart`

Tests:
1. `_mapExceptionToBiometricException` with `keyPermanentlyInvalidated` returns `BiometricException` with `type == BiometricExceptionType.keyInvalidated` -- verify by calling `decrypt()` on a provider whose mock `BiometricCipher` throws `BiometricCipherException(code: keyPermanentlyInvalidated, message: '...')`.
2. Same input does NOT produce `BiometricExceptionType.failure` (negative assertion on the caught exception).
3. Existing mapping: `authenticationUserCanceled` still produces `BiometricExceptionType.cancel`.
4. Existing mapping: `authenticationError` still produces `BiometricExceptionType.failure`.

New mock required: `test/mocks/mock_biometric_cipher.dart` -- `class MockBiometricCipher extends Mock implements BiometricCipher {}`.

---

## NFR

| Requirement | Target |
|-------------|--------|
| Backward compatibility | All existing `_mapExceptionToBiometricException` mappings produce identical results |
| Default fallback preserved | `_ =>` wildcard arm remains intact, still produces `BiometricExceptionType.failure` for unknown codes |
| Static analysis | `fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` passes at root (does not scan `example/`) |
| All tests pass | `fvm flutter test` exits 0 |
| No serialization impact | `BiometricExceptionType` is an in-memory enum, never stored to disk |
| Code style | Doc comment uses `///`; `const` on new `BiometricException`; trailing comma on new switch arm; 120-char line length |

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| `exhaustive_cases` lint fires on `example/` BLoC switches after adding `keyInvalidated` | Certain when `flutter analyze` runs from `example/` | None for Phase 4 -- root analyze does not scan `example/` (confirmed) | Deferred to Phase 5; document in PR description |
| New switch arm accidentally placed inside an existing `\|\|` multi-value group | Low | Medium -- would cause wrong `BiometricExceptionType` | Read actual switch structure before editing; `keyPermanentlyInvalidated` must be a standalone arm before `_ =>` |
| `@visibleForTesting` constructor introduction changes singleton behavior | None -- the testing constructor is additive; existing `instance` and `._()` are unchanged | None | Verify `instance` still uses the private constructor |
| `BiometricCipher` class is not mockable (e.g., uses `final` methods) | Low -- `BiometricCipher` is a standard Dart class from the plugin | Medium -- would require alternative test approach | Verify `BiometricCipher` API before creating mock; `mocktail` works with standard Dart classes |
| `prefer_const_constructors` lint fires if `const` omitted from new `BiometricException(...)` | Certain if omitted | Low -- easy to fix | Always use `const` as all other named arms do |
| `require_trailing_commas` lint fires if trailing comma omitted | Certain if omitted | Low | Always add trailing comma |

---

## Dependencies

### On previous phases

| Phase | Status | What it provides |
|-------|--------|-----------------|
| Phase 1 (Android) | Complete | `FlutterError(code: "KEY_PERMANENTLY_INVALIDATED")` from Android native |
| Phase 2 (iOS/macOS) | Complete | `FlutterError(code: "KEY_PERMANENTLY_INVALIDATED")` from iOS/macOS native |
| Phase 3 (Dart plugin) | Complete | `BiometricCipherExceptionCode.keyPermanentlyInvalidated` enum value + `fromString` mapping |

### For downstream phases

| Phase | What it needs from Phase 4 |
|-------|---------------------------|
| Phase 5 (App layer + teardown) | `BiometricExceptionType.keyInvalidated` exists so BLoC switches can handle it distinctly; locker layer propagates it correctly |

### External dependencies

None. No new packages, no new platform APIs, no build configuration changes.

---

## Implementation Steps

1. **Add `keyInvalidated` to `BiometricExceptionType`** in `lib/security/models/exceptions/biometric_exception.dart`:
   - Append `keyInvalidated` after `notConfigured` (position 7).
   - Add doc comment: `/// Hardware-backed biometric key permanently invalidated due to a biometric enrollment change.`

2. **Add mapping arm** in `lib/security/biometric_cipher_provider.dart`:
   - In `_mapExceptionToBiometricException`, add a standalone arm immediately before `_ =>`:
     ```
     BiometricCipherExceptionCode.keyPermanentlyInvalidated =>
       const BiometricException(BiometricExceptionType.keyInvalidated),
     ```

3. **Add `@visibleForTesting` constructor** to `BiometricCipherProviderImpl` in `lib/security/biometric_cipher_provider.dart`:
   - Add `import 'package:meta/meta.dart';`
   - Change `final BiometricCipher _biometricCipher = BiometricCipher();` to `final BiometricCipher _biometricCipher;`
   - Update private constructor: `BiometricCipherProviderImpl._() : _biometricCipher = BiometricCipher();`
   - Add testing constructor: `@visibleForTesting BiometricCipherProviderImpl.forTesting(this._biometricCipher);`

4. **Create mock** `test/mocks/mock_biometric_cipher.dart`:
   - `class MockBiometricCipher extends Mock implements BiometricCipher {}`

5. **Create test file** `test/security/biometric_cipher_provider_test.dart`:
   - Test that `decrypt()` with mock throwing `BiometricCipherException(code: keyPermanentlyInvalidated, ...)` produces `BiometricException` with `type == BiometricExceptionType.keyInvalidated`.
   - Negative assertion: `type != BiometricExceptionType.failure`.
   - Test existing mappings (`authenticationUserCanceled` -> `cancel`, `authenticationError` -> `failure`) are unaffected.

6. **Verify**: Run static analysis and tests from the root package.

---

## Open Questions

None. The scope is fully defined by the PRD, research document, phase task list, and the current state of the target files. All design decisions (naming, placement, style, test approach) follow established patterns in the codebase.
