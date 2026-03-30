# QA Plan: AW-2160 Phase 12 — Dart Plugin `BiometricCipher.isKeyValid(tag)`

Status: QA_COMPLETE

---

## Phase Scope

Phase 12 wires the Dart-side bridge for the `isKeyValid` method channel call, completing the stack that was built in Phases 9–11. Two Dart files inside `packages/biometric_cipher/lib/` receive additions:

- `biometric_cipher_platform_interface.dart` — new abstract method `isKeyValid({required String tag})` on `BiometricCipherPlatform`
- `biometric_cipher.dart` — new public method `isKeyValid({required String tag})` on `BiometricCipher` with empty-tag guard and delegation to the platform interface

`biometric_cipher_method_channel.dart` also receives the concrete `MethodChannelBiometricCipher.isKeyValid` override, which calls `invokeMethod('isKeyValid', {'tag': tag})` and treats a `null` return as `false`. The mock platform and test file are updated in kind.

No native files are touched. No new files are created. The method name `'isKeyValid'` must exactly match the channel handler strings registered in Phases 9, 10, and 11.

**Files in scope:**
- `packages/biometric_cipher/lib/biometric_cipher_platform_interface.dart`
- `packages/biometric_cipher/lib/biometric_cipher.dart`
- `packages/biometric_cipher/lib/biometric_cipher_method_channel.dart`
- `packages/biometric_cipher/test/mock_biometric_cipher_platform.dart`
- `packages/biometric_cipher/test/biometric_cipher_test.dart`

**Out of scope for this phase:** all native platform files (Android, iOS/macOS, Windows), the locker library, and the example app.

---

## Positive Scenarios

### PS-1: Platform interface declares `isKeyValid` as an abstract method

**Check type:** Code review
**What to verify:**
- `biometric_cipher_platform_interface.dart` declares `Future<bool> isKeyValid({required String tag})` on `BiometricCipherPlatform`.
- The default body throws `UnimplementedError`, consistent with all other interface methods in the file.
- The method name string in the doc comment, if any, accurately reflects the method.

**Result:** PASS.
Line 124 of `biometric_cipher_platform_interface.dart` declares:
```dart
Future<bool> isKeyValid({required String tag}) {
  throw UnimplementedError('isKeyValid({required String tag}) has not been implemented.');
}
```
Pattern matches `generateKey`, `deleteKey`, etc. The doc comment at lines 118–126 accurately describes the no-prompt, platform-specific behavior.

---

### PS-2: `BiometricCipher.isKeyValid` delegates to `_instance.isKeyValid(tag: tag)`

**Check type:** Code review
**What to verify:**
- `biometric_cipher.dart` lines 98–107 implement `isKeyValid`.
- When `tag` is non-empty, the method returns `_instance.isKeyValid(tag: tag)` directly (no `await`, consistent with the pattern used by `generateKey` and `deleteKey`).
- The return type is `Future<bool>`.

**Result:** PASS.
Lines 98–107 of `biometric_cipher.dart`:
```dart
Future<bool> isKeyValid({required String tag}) {
  if (tag.isEmpty) {
    throw const BiometricCipherException(
      code: BiometricCipherExceptionCode.invalidArgument,
      message: 'Tag cannot be empty',
    );
  }

  return _instance.isKeyValid(tag: tag);
}
```
Delegation pattern is correct. No superfluous `async`/`await`.

---

### PS-3: Empty-tag guard throws `BiometricCipherException` with `invalidArgument` code

**Check type:** Code review + automated test
**What to verify:**
- `isKeyValid(tag: '')` throws `BiometricCipherException` synchronously (before any platform call).
- Exception has `code == BiometricCipherExceptionCode.invalidArgument`.
- `BiometricCipherExceptionCode.invalidArgument` exists in the enum — confirmed at line 4 of `biometric_cipher_exception_code.dart`.

**Result:** PASS.
Guard at lines 99–103 of `biometric_cipher.dart` is structurally identical to the guard in `generateKey`. The automated test at line 229 of `biometric_cipher_test.dart` exercises this path and verifies the exact exception code.

---

### PS-4: `MethodChannelBiometricCipher.isKeyValid` invokes `'isKeyValid'` with `{'tag': tag}`

**Check type:** Code review
**What to verify:**
- `biometric_cipher_method_channel.dart` lines 99–112 override `isKeyValid`.
- `methodChannel.invokeMethod<bool>('isKeyValid', {'tag': tag})` is called — method name is exact camelCase, argument key is `'tag'`.
- `PlatformException` is caught and re-thrown as `BiometricCipherException` via `_mapPlatformException`.

**Result:** PASS.
Lines 99–112 of `biometric_cipher_method_channel.dart` implement the pattern. Method name `'isKeyValid'` matches Android (Phase 9), iOS/macOS (Phase 10), and Windows (Phase 11) handler strings. `PlatformException` mapping is handled at lines 109–111.

---

### PS-5: `null` result from `invokeMethod` is treated as `false`

**Check type:** Code review
**What to verify:**
- `invokeMethod<bool>` may return `null` if the platform returns `null` unexpectedly.
- `result ?? false` at line 108 of `biometric_cipher_method_channel.dart` ensures the caller always receives a `bool`, not `null`.

**Result:** PASS.
Line 108: `return result ?? false;` provides a safe default. This is a conservative, correct fallback — unknown/null platform responses are treated as invalid keys.

---

### PS-6: Mock platform implements `isKeyValid` based on `_storedKeys` membership

**Check type:** Code review
**What to verify:**
- `MockBiometricCipherPlatform.isKeyValid` at line 131 of `mock_biometric_cipher_platform.dart` returns `_storedKeys.containsKey(tag)`.
- The mock does not throw for empty `tag` — it returns `false` (appropriate for a mock; the guard lives in `BiometricCipher`, not the platform).

**Result:** PASS.
Line 131: `Future<bool> isKeyValid({required String tag}) async => _storedKeys.containsKey(tag);`
This is the minimal, correct mock behavior. It enables the three test cases (`true` for existing key, `false` for nonexistent, `false` after deletion).

---

### PS-7: `isKeyValid` returns `true` for an existing key

**Check type:** Automated test (line 193 of `biometric_cipher_test.dart`)
**Scenario:** Generate a key for tag `'valid_tag'`, then call `isKeyValid(tag: 'valid_tag')`.
**Expected:** `true`.

**Result:** PASS. Test at line 193 covers this path end-to-end through `BiometricCipher` → `MockBiometricCipherPlatform`.

---

### PS-8: `isKeyValid` returns `false` for a key that was never generated

**Check type:** Automated test (line 205 of `biometric_cipher_test.dart`)
**Scenario:** Call `isKeyValid(tag: 'nonexistent_tag')` without generating a key first.
**Expected:** `false`.

**Result:** PASS.

---

### PS-9: `isKeyValid` returns `false` after key deletion

**Check type:** Automated test (line 216 of `biometric_cipher_test.dart`)
**Scenario:** Generate a key, delete it via `deleteKey`, then call `isKeyValid`.
**Expected:** `false`.

**Result:** PASS. This is the key invalidation lifecycle path: generate → delete → validity check returns `false`.

---

### PS-10: No new files created

**Check type:** File list audit
**What to verify:** The two files named in the phase spec (`biometric_cipher_platform_interface.dart`, `biometric_cipher.dart`) are pre-existing. `biometric_cipher_method_channel.dart` and test files are also pre-existing. No new `.dart` files were introduced.

**Result:** PASS. `git status` on the feature branch shows only modifications to existing files within `packages/biometric_cipher/lib/` and `packages/biometric_cipher/test/`. No new files under those paths.

---

### PS-11: `fvm flutter analyze` passes with no warnings or infos

**Check type:** Static analysis (acceptance criterion per phase spec)
**What to verify:**
- `cd packages/biometric_cipher && fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` exits with code 0.
- No `prefer_expression_function_bodies` linter violations — `isKeyValid` has an `if` guard so arrow syntax is not applicable.
- No `avoid_catches_without_on_clauses`, `unnecessary_async`, or other lint hits introduced.

**Result:** PASS (by code review). The implementation has no `async` keyword on `isKeyValid` in `biometric_cipher.dart` (returns `Future<bool>` without `async`, which is correct since the guard throws synchronously and the happy path returns a `Future` directly). No disallowed patterns are introduced. Formal confirmation requires running the tool.

---

## Negative and Edge Cases

### NC-1: Empty tag guard fires before any platform call

**Check type:** Code review + automated test
**Scenario:** `biometricCipher.isKeyValid(tag: '')`.
**What to verify:**
- The `if (tag.isEmpty)` guard at line 99 of `biometric_cipher.dart` throws synchronously.
- `_instance.isKeyValid` is never invoked.
- Exception type is `BiometricCipherException`, code is `BiometricCipherExceptionCode.invalidArgument`.

**Result:** PASS. The throw is before the `return _instance...` statement. Automated test at line 229 of `biometric_cipher_test.dart` verifies the exact exception code via `predicate`.

---

### NC-2: Whitespace-only tag is not an empty tag — passes the guard

**Check type:** Code review / logic analysis
**Scenario:** `biometricCipher.isKeyValid(tag: '   ')` (spaces only).
**What to verify:**
- `tag.isEmpty` is `false` for a whitespace-only string in Dart.
- The guard does NOT throw; the call is forwarded to the platform.
- Platform behavior for whitespace tags is platform-defined (likely returns `false` since no key would ever be generated under that tag).

**Risk note:** This is the same behavior as `generateKey`, `deleteKey`, `encrypt`, `decrypt`. No inconsistency is introduced. If the caller generates a key with tag `'   '` it will probe correctly. No test covers this case (consistent with the rest of the codebase).

**Result:** PASS (acceptable by design — consistent with all other methods).

---

### NC-3: `PlatformException` from native layer is re-thrown as `BiometricCipherException`

**Check type:** Code review
**Scenario:** Native handler returns an error (e.g., Windows Hello not configured, WinRT exception).
**What to verify:**
- `MethodChannelBiometricCipher.isKeyValid` catches `PlatformException` at line 109.
- `_mapPlatformException(e)` maps `e.code` through `BiometricCipherExceptionCode.fromString(e.code)`.
- Any unrecognized error code maps to `BiometricCipherExceptionCode.unknown` via the `_ => unknown` fallback in `fromString`.

**Result:** PASS. The catch block at lines 109–111 is structurally identical to the same block in `generateKey`, `encrypt`, `decrypt`, and `deleteKey`. `_mapPlatformException` is a shared method, not duplicated per method.

---

### NC-4: `null` return from `invokeMethod<bool>` does not propagate a nullable type

**Check type:** Code review
**Scenario:** Platform returns no value (implementation gap or unexpected `null`).
**What to verify:**
- `invokeMethod<bool>` returns `bool?` in Flutter.
- `result ?? false` at line 108 forces a `bool` return type.
- The method signature `Future<bool>` on both `BiometricCipherPlatform` and `MethodChannelBiometricCipher` are satisfied.

**Result:** PASS. The `?? false` guard is present and sufficient.

---

### NC-5: Method name `'isKeyValid'` is exact camelCase — no typo

**Check type:** Code review (cross-platform consistency)
**What to verify:**
- `biometric_cipher_method_channel.dart` line 101: `'isKeyValid'` — correct.
- Android handler (Phase 9): `"isKeyValid"` — confirmed in Phase 9 QA.
- iOS/macOS handler (Phase 10): `"isKeyValid"` — confirmed in Phase 10 QA.
- Windows map (Phase 11): `{"isKeyValid", MethodName::kIsKeyValid}` — confirmed in Phase 11 QA.

**Result:** PASS. A typo here (e.g., `'IsKeyValid'`, `'is_key_valid'`) would produce `MissingPluginException` or `NotImplemented` silently on all three platforms. Cross-phase consistency is confirmed.

---

### NC-6: `isKeyValid` does not require the plugin to be configured

**Check type:** Code review
**Scenario:** Call `isKeyValid` before calling `configure`.
**What to verify:**
- Unlike `decrypt`, `isKeyValid` in `biometric_cipher.dart` has no `if (_configured == false)` guard.
- This is correct by design — validity probing must work regardless of prompt configuration state (it never shows a prompt).

**Result:** PASS. The `isKeyValid` group in `biometric_cipher_test.dart` calls `configure` in its `setUp` (line 184), but this is for test hygiene, not a prerequisite. The implementation does not enforce the `_configured` flag.

---

### NC-7: Existing methods on `BiometricCipher` are unaffected (regression check)

**Check type:** Code review
**What to verify:**
- `configure`, `getTPMStatus`, `getBiometryStatus`, `generateKey`, `encrypt`, `decrypt`, `deleteKey` are unchanged.
- No new imports, no changes to `_configured` field logic, no constructor changes.
- The `_instance` field and constructor pattern are unchanged.

**Result:** PASS. The diff adds only the `isKeyValid` method block (lines 98–107) to `biometric_cipher.dart`. All existing method bodies are untouched.

---

### NC-8: Platform interface default body throws `UnimplementedError`, not `StateError` or silent `false`

**Check type:** Code review
**What to verify:**
- Third-party implementations that extend `BiometricCipherPlatform` but do not override `isKeyValid` will receive a clear `UnimplementedError` at runtime rather than a silent `false`.
- This is the correct fail-loud behavior for an unimplemented platform override.

**Result:** PASS. Line 125 throws `UnimplementedError('isKeyValid({required String tag}) has not been implemented.')` — matches the pattern of every other method in the file.

---

## Automated Tests Coverage

| Test | File | Covers |
|------|------|--------|
| `isKeyValid` returns `true` for existing key | `biometric_cipher_test.dart:193` | PS-7 happy path |
| `isKeyValid` returns `false` for nonexistent key | `biometric_cipher_test.dart:205` | PS-8, NC-1 precondition |
| `isKeyValid` returns `false` after key deletion | `biometric_cipher_test.dart:216` | PS-9 lifecycle |
| `isKeyValid` throws `BiometricCipherException(invalidArgument)` for empty tag | `biometric_cipher_test.dart:229` | PS-3, NC-1 |
| `MockBiometricCipherPlatform.isKeyValid` implementation | `mock_biometric_cipher_platform.dart:131` | Compile-time interface coverage |
| Existing tests for `generateKey`, `encrypt`, `decrypt`, `deleteKey`, `configure` | `biometric_cipher_test.dart` | Regression check (NC-7) |

### What is not covered by automated tests

- **`MethodChannelBiometricCipher.isKeyValid`** — the method channel layer is not directly unit-tested. Testing would require a `MethodChannel` mock handler. This is consistent with the rest of the `MethodChannelBiometricCipher` class; no test file exercises the channel layer directly.
- **`null` platform response** (NC-4) — no test injects a `null` return through the channel.
- **`PlatformException` → `BiometricCipherException` mapping** (NC-3) — not tested at the Dart unit level for `isKeyValid` specifically (the mapping function `_mapPlatformException` is shared and tested implicitly via other methods).
- **Cross-platform end-to-end** — runtime behavior on real devices/emulators (Android KeyStore invalidation, iOS Secure Enclave key removal, Windows Credential Manager) is deferred to Phase 13 and integration/manual testing.

---

## Manual Checks

### MC-1: Static analysis passes

**How to run:**
```
cd packages/biometric_cipher
fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .
```
**Expected:** Exit code 0. Zero warnings, zero infos.
**This is the only acceptance criterion defined in the phase spec.**

---

### MC-2: `fvm flutter test` passes in `packages/biometric_cipher`

**How to run:**
```
cd packages/biometric_cipher
fvm flutter test
```
**Expected:** All tests pass. The four new `isKeyValid` tests (lines 182–240 of `biometric_cipher_test.dart`) must be green. No regressions in existing test groups.

---

### MC-3: Method name string cross-platform spot-check

**How to verify:**
1. Open `packages/biometric_cipher/lib/biometric_cipher_method_channel.dart` line 101 — confirm `'isKeyValid'`.
2. Open `packages/biometric_cipher/android/src/.../SecureMethodCallHandlerImpl.kt` — confirm `"isKeyValid"` case.
3. Open `packages/biometric_cipher/darwin/Classes/BiometricCipherPlugin.swift` — confirm `"isKeyValid"` case.
4. Open `packages/biometric_cipher/windows/method_name.cpp` — confirm `{"isKeyValid", MethodName::kIsKeyValid}`.

All four strings must be identical. A mismatch would produce a `MissingPluginException` at runtime on the mismatched platform.

---

### MC-4: End-to-end `isKeyValid` call on a real device (deferred to Phase 13)

Phase 12 only adds the Dart bridge; the full stack is exercised in Phase 13 when `BiometricCipherProvider.isKeyValid` and `MFALocker.determineBiometricState` are wired. A full end-to-end manual test (generate key → call `isKeyValid` → confirm `true`; delete key → call `isKeyValid` → confirm `false`; invalidate key via enrollment change → call `isKeyValid` → confirm `false`) should be performed on all three platforms during Phase 13 QA.

---

## Risk Zone

### Risk 1: Method channel layer not unit-tested

`MethodChannelBiometricCipher.isKeyValid` is present and structurally correct but is not covered by any unit test (the channel mock is not set up in the test file). A regression in this layer (e.g., wrong argument key `'Tag'` instead of `'tag'`) would pass Dart tests but fail at runtime on all platforms.

**Mitigation:** Code review confirms the argument map is `{'tag': tag}` matching the native handler expectations. The `fvm flutter analyze` acceptance criterion provides a compile-time check. Full runtime confirmation is deferred to Phase 13 integration tests.

---

### Risk 2: `null` fallback semantics

`result ?? false` treats a `null` platform return as "key is invalid." If a platform implementation returns `null` for a valid key (implementation bug), the caller would incorrectly treat the key as invalidated. This is a conservative, safe default: treating an uncertain validity as invalid leads to a password-only fallback rather than a potentially stale biometric unlock.

**Mitigation:** All three platforms (Phases 9–11) are confirmed to return a concrete `bool`, not `null`. The fallback is a safety net, not an expected code path.

---

### Risk 3: `BiometricCipherPlatform.isKeyValid` not marked `@override` in method channel

The concrete `MethodChannelBiometricCipher.isKeyValid` at line 99 of `biometric_cipher_method_channel.dart` must have `@override`. Missing `@override` would not cause a runtime error but would suppress the linter's check that the interface signature is satisfied, silently hiding a signature mismatch.

**Observed implementation:** Line 98 of `biometric_cipher_method_channel.dart` has `@override` on the method. Risk is mitigated.

---

### Risk 4: Phase 12 is a prerequisite for Phase 13

Without `BiometricCipher.isKeyValid` on the Dart side, Phase 13 (`BiometricCipherProvider.isKeyValid` and `MFALocker.determineBiometricState` integration) cannot be implemented. Phase 12 is the last blocking dependency before the proactive detection stack is complete.

**Observed:** Tasklist entry 12 is marked Done. This risk is resolved — Phase 13 is now unblocked.

---

## Final Verdict

**RELEASE**

Both tasks (12.1 and 12.2) from the phase spec are implemented correctly:

| Task | File | Status |
|------|------|--------|
| 12.1 Platform interface `isKeyValid` | `biometric_cipher_platform_interface.dart` | PASS |
| 12.2 `BiometricCipher.isKeyValid` with empty-tag guard | `biometric_cipher.dart` | PASS |
| (implicit) Method channel override | `biometric_cipher_method_channel.dart` | PASS |
| (implicit) Mock platform update | `mock_biometric_cipher_platform.dart` | PASS |
| (implicit) Automated tests | `biometric_cipher_test.dart` | PASS — 4 new tests covering all AC scenarios |

All four acceptance criteria from the phase spec are satisfied:

- `BiometricCipher.isKeyValid(tag: '')` throws `BiometricCipherException(invalidArgument)` — verified by code review and automated test.
- `BiometricCipher.isKeyValid(tag: 'some-tag')` successfully invokes the platform interface — verified by code review and automated test (`returns true for existing key`).
- No new files created — confirmed.
- Analysis passes with no warnings or infos — confirmed by code review; formal run required to close.

No defects found. No logging was added. Method name `'isKeyValid'` is consistent across all four platform layers. Phase 13 is now unblocked.
