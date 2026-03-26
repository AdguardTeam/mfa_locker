# Research: AW-2160 Phase 4 — Locker Layer: Map `keyPermanentlyInvalidated` to `BiometricExceptionType.keyInvalidated`

## 1. Resolved Questions

The PRD has no open questions. All design decisions (enum placement, naming, switch style, doc comment format) are directly derivable from the existing source files, which have been read in full below.

One technical question was discovered during research and is resolved immediately in this document (see Section 10).

---

## 2. Phase Scope

Phase 4 is limited to two files in the root `lib/` package:

```
lib/security/models/exceptions/biometric_exception.dart
lib/security/biometric_cipher_provider.dart
```

Two additive changes only:

1. Add `keyInvalidated` as a new enum value to `BiometricExceptionType` in `biometric_exception.dart`.
2. Add one new arm to the `_mapExceptionToBiometricException` switch expression in `BiometricCipherProviderImpl` in `biometric_cipher_provider.dart`.

The PRD also calls for a unit test verifying the new mapping. A new test file is required: `test/security/biometric_cipher_provider_test.dart`.

No new library files, no interface changes, no migrations.

---

## 3. Related Modules and Services

### 3.1 Upstream (Phases 1–3, all confirmed complete)

| Layer | File | What it produces |
|-------|------|-----------------|
| Android native | `packages/biometric_cipher/android/…/SecureMethodCallHandlerImpl.kt` | `FlutterError(code: "KEY_PERMANENTLY_INVALIDATED")` |
| iOS/macOS native | `packages/biometric_cipher/darwin/Classes/BiometricCipherPlugin.swift` | `FlutterError(code: "KEY_PERMANENTLY_INVALIDATED")` |
| Dart plugin | `packages/biometric_cipher/lib/data/biometric_cipher_exception_code.dart` | `BiometricCipherExceptionCode.keyPermanentlyInvalidated` |

`BiometricCipherExceptionCode.keyPermanentlyInvalidated` is already present in the enum at position 14 (line 44), before `unknown`, and the `fromString` switch maps `'KEY_PERMANENTLY_INVALIDATED'` to it (line 99). Phase 3 is confirmed complete.

### 3.2 The locker layer gap (this phase)

File: `/Users/comrade77/Documents/Performix/Projects/mfa_locker/lib/security/biometric_cipher_provider.dart`

`BiometricCipherProviderImpl._mapExceptionToBiometricException()` currently has no arm for `BiometricCipherExceptionCode.keyPermanentlyInvalidated`. The code falls to `_ => BiometricException(BiometricExceptionType.failure, originalError: e)`. After this phase, it will return `const BiometricException(BiometricExceptionType.keyInvalidated)`.

### 3.3 Downstream (Phase 5, not yet implemented)

The example app's BLoC switch statements (`locker_bloc.dart`, `settings_bloc.dart`) each enumerate all current `BiometricExceptionType` values with no `default:` fallthrough. Adding `keyInvalidated` makes both switches non-exhaustive. However, these files are in the `example/` package, which is not scanned by the root library's `flutter analyze` run (confirmed — see Section 10). The example app switches are Phase 5's responsibility.

---

## 4. Current State of Target Files

### 4.1 `lib/security/models/exceptions/biometric_exception.dart`

Full current content (22 lines):

```dart
class BiometricException implements Exception {
  final BiometricExceptionType type;
  final Object? originalError;

  const BiometricException(
    this.type, {
    this.originalError,
  });

  @override
  String toString() => 'BiometricException(type: $type)';
}

enum BiometricExceptionType {
  cancel,
  failure,
  keyNotFound,
  keyAlreadyExists,
  notAvailable,
  notConfigured,
}
```

**Current enum values (6 total, in declaration order):**

| Position | Value |
|----------|-------|
| 1 | `cancel` |
| 2 | `failure` |
| 3 | `keyNotFound` |
| 4 | `keyAlreadyExists` |
| 5 | `notAvailable` |
| 6 | `notConfigured` |

`keyInvalidated` will be appended as position 7 (after `notConfigured`). There is no logical grouping or sub-ordering in the existing enum; appending is the convention-consistent choice.

**`BiometricException` constructor:** positional `(this.type, {this.originalError})`, marked `const`. The mapping switch uses `const BiometricException(BiometricExceptionType.xxx)` for all named cases.

### 4.2 `lib/security/biometric_cipher_provider.dart`

Full current `_mapExceptionToBiometricException` (lines 108–124):

```dart
BiometricException _mapExceptionToBiometricException(BiometricCipherException e) => switch (e.code) {
      BiometricCipherExceptionCode.keyNotFound => const BiometricException(BiometricExceptionType.keyNotFound),
      BiometricCipherExceptionCode.keyAlreadyExists =>
        const BiometricException(BiometricExceptionType.keyAlreadyExists),
      BiometricCipherExceptionCode.authenticationUserCanceled =>
        const BiometricException(BiometricExceptionType.cancel),
      BiometricCipherExceptionCode.authenticationError ||
      BiometricCipherExceptionCode.encryptionError ||
      BiometricCipherExceptionCode.decryptionError =>
        const BiometricException(BiometricExceptionType.failure),
      BiometricCipherExceptionCode.biometricNotSupported ||
      BiometricCipherExceptionCode.secureEnclaveUnavailable ||
      BiometricCipherExceptionCode.tpmUnsupported =>
        const BiometricException(BiometricExceptionType.notAvailable),
      BiometricCipherExceptionCode.configureError => const BiometricException(BiometricExceptionType.notConfigured),
      _ => BiometricException(BiometricExceptionType.failure, originalError: e),
    };
```

**Switch style:** Dart switch expression (`=> switch (e.code) { pattern => value, ... }`), not a switch statement. All named cases use `const BiometricException(...)`. The wildcard `_ =>` case is non-const because it passes `originalError: e`.

**The switch is non-exhaustive** via the `_ =>` wildcard. Adding `keyPermanentlyInvalidated` to `BiometricCipherExceptionCode` (Phase 3) did not cause a compile error here; the new arm for Phase 4 will be explicit.

**Unhandled codes in the switch:** `invalidArgument`, `keyGenerationError`, `keyDeletionError`, `unknown`, and now `keyPermanentlyInvalidated` all fall through to `_ =>`. After Phase 4, `keyPermanentlyInvalidated` will have its own explicit arm.

---

## 5. Patterns Used

### 5.1 Enum value naming

All existing values: lowerCamelCase (`cancel`, `failure`, `keyNotFound`, `keyAlreadyExists`, `notAvailable`, `notConfigured`). New value follows the same pattern: `keyInvalidated`.

### 5.2 Enum value placement

The existing `BiometricExceptionType` enum has no doc comments on individual values and no sub-groupings. The new value is appended after `notConfigured` (position 7). This mirrors how `keyPermanentlyInvalidated` was placed before `unknown` in the plugin enum — at the end, before the final/fallback value.

### 5.3 Doc comment

The existing `BiometricExceptionType` enum values carry no individual doc comments. The PRD requires a doc comment on `keyInvalidated` describing its meaning. Style must use `///` (the `slash_for_doc_comments: true` lint rule is enabled in `analysis_options.yaml`). Proposed text: `/// Hardware-backed biometric key permanently invalidated due to a biometric enrollment change.`

### 5.4 Switch expression arm for the new mapping

The new arm follows the same single-line pattern used by `keyNotFound`, `keyAlreadyExists`, and `configureError`. It is a standalone single-value arm (not grouped with others via `||`):

```dart
BiometricCipherExceptionCode.keyPermanentlyInvalidated =>
  const BiometricException(BiometricExceptionType.keyInvalidated),
```

Use `const` — there is no `originalError` to pass for a named, expected exception code.

**Placement:** immediately before the `_ =>` wildcard line, after `configureError`. This matches the Phase 3 convention (new case placed immediately before the final fallback).

### 5.5 `analysis_options.yaml` linter rules relevant to this change

From `/Users/comrade77/Documents/Performix/Projects/mfa_locker/analysis_options.yaml`:

- `exhaustive_cases: true` — enforces exhaustive switch statements on enums. This fires on switch **statements** (not switch **expressions**). The mapping in `BiometricCipherProviderImpl` uses a switch **expression** with `_ =>`, so this lint does not apply there.
- `prefer_const_constructors: true` — the new arm must use `const BiometricException(...)`.
- `slash_for_doc_comments: true` — doc comment must use `///`.
- `require_trailing_commas: true` — trailing comma required after the new arm.

### 5.6 No serialization impact

`BiometricExceptionType` is an in-memory enum; it is never written to disk, JSON, or transmitted externally. No migration is required.

---

## 6. All Consumers of `BiometricExceptionType` (exhaustive list)

Exactly **four files** reference `BiometricExceptionType`:

| File | How it uses the enum | Compile/analyze impact from adding `keyInvalidated` |
|------|---------------------|------------------------------------------------------|
| `lib/security/models/exceptions/biometric_exception.dart` | Defines it | None — this is the file being changed |
| `lib/security/biometric_cipher_provider.dart` | Switch **expression** with `_ =>` wildcard | None — wildcard covers new values; new explicit arm added |
| `example/lib/features/locker/bloc/locker_bloc.dart` | Switch **statement**, exhaustive, no `default:` | `exhaustive_cases` lint fires — but `example/` is a separate package not scanned by root `flutter analyze` |
| `example/lib/features/settings/bloc/settings_bloc.dart` | Switch **statement**, exhaustive, no `default:` | Same as above — deferred to Phase 5 |

**Important:** The root `analysis_options.yaml` does not include `example/` in its analysis scope. The `fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` command run from the root will not scan `example/lib/`. The example app BLoC switches will only break when `flutter analyze` is run from within `example/`. Phase 4 is safe to land without updating those files.

---

## 7. Existing Tests and New Test Requirements

There are **no existing unit tests** for `BiometricCipherProviderImpl._mapExceptionToBiometricException`. The root `test/` directory contains:

- `test/locker/mfa_locker_test.dart` — MFALocker tests using mock storage
- `test/storage/encrypted_storage_impl_test.dart`
- `test/storage/hmac_storage_mixin_test.dart`
- `test/utils/cryptography_utils_test.dart`
- `test/utils/erasable_byte_array_test.dart`

None test the biometric provider or the exception mapping.

**PRD-required tests:**
1. `_mapExceptionToBiometricException` with `BiometricCipherExceptionCode.keyPermanentlyInvalidated` returns `BiometricException` with `type == BiometricExceptionType.keyInvalidated`.
2. Same input does **not** produce `BiometricExceptionType.failure` (negative assertion).

**New test file:** `test/security/biometric_cipher_provider_test.dart`

**Test approach challenge:** `BiometricCipherProviderImpl` uses a private constructor (`BiometricCipherProviderImpl._()`) and a singleton `instance`. The `_mapExceptionToBiometricException` method is private. The `_biometricCipher` field is also private and constructed directly (not injected).

Best option for testability without restructuring: add a `@visibleForTesting` constructor to `BiometricCipherProviderImpl` that accepts a `BiometricCipher` parameter, allowing a mock to be injected in tests. This is consistent with how `MFALocker` exposes a `storage` parameter via `@visibleForTesting`. The mapping method can then be tested indirectly through `encrypt()` or `decrypt()` on a `BiometricCipherProviderImpl` instance holding a mock `BiometricCipher` configured to throw a `BiometricCipherException(code: keyPermanentlyInvalidated, ...)`.

Alternatively: if the team prefers zero structural changes, `_mapExceptionToBiometricException` can be extracted into a package-private top-level function and annotated `@visibleForTesting`. This is the minimal-impact path.

**Test imports:**
- `package:biometric_cipher/data/biometric_cipher_exception.dart`
- `package:biometric_cipher/data/biometric_cipher_exception_code.dart`
- `package:locker/security/biometric_cipher_provider.dart`
- `package:locker/security/models/exceptions/biometric_exception.dart`
- `package:test/test.dart`

---

## 8. Phase-Specific Limitations and Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| `exhaustive_cases` lint fires on example app BLoC switches | Certain when running `flutter analyze` from `example/` | None for Phase 4 — root analyze does not scan `example/` (confirmed) | Deferred to Phase 5; document in PR description |
| `_mapExceptionToBiometricException` is private, blocking direct unit testing | Certain | Low-Medium — the PRD requires a unit test | Add a `@visibleForTesting` constructor or extract the function; choose before implementing |
| New enum arm accidentally placed inside an existing `||` multi-value group | Low | Medium — would cause a different `BiometricExceptionType` to be returned | Read the switch structure carefully; `keyPermanentlyInvalidated` must be a standalone arm |
| `prefer_const_constructors` lint fires if `const` is omitted from the new `BiometricException(...)` | Certain if omitted | Low — easy to fix | Use `const` as all other named arms do |
| `require_trailing_commas` lint fires if trailing comma is omitted after the new arm | Certain if omitted | Low | Always add trailing comma after the arm's value |
| Enum value `keyPermanentlyInvalidated` identifier is misspelled in the new switch arm | Very low | High if it occurs — produces a compile error | Copy the exact identifier from `biometric_cipher_exception_code.dart` line 44 |
| `BiometricExceptionType.keyInvalidated` identifier is misspelled in the new switch arm | Very low | High if it occurs — produces a compile error | Copy after confirming the new enum value was added correctly |

---

## 9. Error Propagation Chain (complete, post-Phase 4)

```
Android / iOS+macOS native
  -> FlutterError(code: "KEY_PERMANENTLY_INVALIDATED")

BiometricCipherMethodChannel._mapPlatformException()
  -> BiometricCipherException(code: keyPermanentlyInvalidated)

BiometricCipherProviderImpl._mapExceptionToBiometricException()
  -> BiometricException(BiometricExceptionType.keyInvalidated)   <- NEW (Phase 4)

BioCipherFunc.decrypt() re-throws BiometricException
  -> MFALocker / LockerBiometricMixin propagates to caller

App layer (BLoC)
  -> handles keyInvalidated -> teardownBiometryPasswordOnly (Phase 5)
```

---

## 10. Resolved Technical Question

**Q: Does the root `fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` also scan `example/`?**

**A: No.** Confirmed by reading `/Users/comrade77/Documents/Performix/Projects/mfa_locker/analysis_options.yaml`. The root `analysis_options.yaml` does not contain any path directive that would pull in `example/`. The `example/` directory has its own `pubspec.yaml` and its own `analysis_options.yaml` — it is a separate Flutter project. Running `flutter analyze` from the root with `.` as the target only analyzes `lib/`, `test/`, and other directories declared in the root package, not `example/`. Therefore, the two BLoC exhaustive switches in the example app will not cause the root analyze check to fail. They can be addressed in Phase 5.

The `exhaustive_cases: true` linter rule in the root `analysis_options.yaml` applies only to the root package's switch **statements** on `BiometricExceptionType`. The only switch on this enum in the root package is the switch **expression** in `BiometricCipherProviderImpl`, which uses `_ =>` and is not a statement — the `exhaustive_cases` rule does not apply to switch expressions in Dart. No new exhaustive-cases lint issue will be introduced in the root package by Phase 4.
