# AW-2160-11: Windows — `isKeyValid(tag)` Silent Probe

Status: PRD_READY

## Context / Idea

This is Phase 11 of AW-2160. The ticket as a whole adds biometric key invalidation detection and a password-only teardown path across the full stack, plus proactive key validity detection at init time without triggering a biometric prompt.

**Phases 1–10 status (all complete):**
- Phase 1: Android native emits `FlutterError(code: "KEY_PERMANENTLY_INVALIDATED")` for `KeyPermanentlyInvalidatedException`.
- Phase 2: iOS/macOS native emits `FlutterError(code: "KEY_PERMANENTLY_INVALIDATED")` when the Secure Enclave key is inaccessible after a biometric enrollment change.
- Phase 3: Dart plugin maps `'KEY_PERMANENTLY_INVALIDATED'` → `BiometricCipherExceptionCode.keyPermanentlyInvalidated`.
- Phase 4: Locker library maps `BiometricCipherExceptionCode.keyPermanentlyInvalidated` → `BiometricExceptionType.keyInvalidated`.
- Phase 5: `MFALocker.teardownBiometryPasswordOnly` is complete.
- Phase 6: Unit tests for all new Dart-layer code paths are complete.
- Phase 7: Example app detects `keyInvalidated` at runtime and updates UI accordingly.
- Phase 8: Example app password-only biometric disable recovery flow is complete.
- Phase 9: Android native `isKeyValid(tag)` silent probe is complete — `Cipher.init()` is used without `BiometricPrompt`; `KeyPermanentlyInvalidatedException` → `false`.
- Phase 10: iOS/macOS native `isKeyValid(tag)` silent probe is complete — `SecItemCopyMatching` with `kSecUseAuthenticationUISkip` suppresses all prompt UI; `errSecItemNotFound` → `false`.

**The problem this phase solves:** Phases 1–8 implement reactive detection: `keyInvalidated` is discovered only when the user triggers a biometric operation, causing the lock screen to briefly show the biometric button before hiding it. Phases 9–14 add proactive detection: `determineBiometricState()` checks key validity at init time without triggering any biometric prompt. Phase 11 is the Windows half of the platform `isKeyValid` method (Android = Phase 9, iOS/macOS = Phase 10). Phase 12 will wire the Dart-side method channel call, and Phase 13 will integrate it into `determineBiometricState()`.

**Windows platform specifics:** On Windows, `KeyCredentialManager::OpenAsync(tag)` returns a `KeyCredentialRetrievalResult` whose `Status()` property indicates credential availability. This call does not request a signing operation and therefore does not trigger a Windows Hello biometric prompt — it only queries credential metadata. `KeyCredentialStatus::NotFound` → credential is gone → return `false`. `KeyCredentialStatus::Success` → credential exists and is usable → return `true`. Unlike Android (enrollment-linked key invalidation) and iOS/macOS (OS deletes the Secure Enclave key on biometric change), Windows Hello credentials are tied to the user account, not biometric enrollment. They can be deleted externally (e.g., via `certutil`, device reset, or TPM clear).

**Scope:** Windows C++ native plugin layer only — `packages/biometric_cipher/windows/`. Five files modified across repository interface, impl header, impl cpp, service, enum, and plugin. No new files. No Dart-layer changes (those belong to Phase 12). No logging added (silent probe with no side effects).

**Call chain (new):**
```
MethodName::kIsKeyValid handler (BiometricCipherPlugin)
  → IsKeyValidCoroutine(tag, result)
  → BiometricCipherService::IsKeyValidAsync(tag)
  → WindowsHelloRepositoryImpl::IsKeyValidAsync(hTag)
  → CheckWindowsHelloIsStatusAsync() + m_HelloWrapper->OpenAsync(tag)
  → KeyCredentialStatus::Success → true / NotFound → false
```

**Dependencies:**
- Phase 9 complete (Android `isKeyValid` — establishes the shared method name `"isKeyValid"`).
- Phase 10 complete (iOS/macOS `isKeyValid` — same method name must match for Phase 12 Dart-side invocation).
- `ArgumentName::kTag` already exists in the argument parser (used by `encrypt`, `decrypt`, `deleteKey`).
- `CheckWindowsHelloIsStatusAsync()` and `m_HelloWrapper->OpenAsync()` already exist in `WindowsHelloRepositoryImpl`.

---

## Goals

1. Add `IsKeyValidAsync(const winrt::hstring tag)` as a pure virtual method to the `WindowsHelloRepository` interface.
2. Declare and implement `IsKeyValidAsync` in `WindowsHelloRepositoryImpl`: call `CheckWindowsHelloIsStatusAsync()` then `m_HelloWrapper->OpenAsync(tag)`, return `status == KeyCredentialStatus::Success`.
3. Add `IsKeyValidAsync(const std::string& tag)` to `BiometricCipherService`: convert tag to `hstring` and delegate to `m_WindowsHelloRepository->IsKeyValidAsync(hTag)`.
4. Add `kIsKeyValid` to the `MethodName` enum (before `kNotImplemented`) and add `{"isKeyValid", MethodName::kIsKeyValid}` to `METHOD_NAME_MAP` in `method_name.cpp`.
5. Add `case MethodName::kIsKeyValid:` to the `HandleMethodCall` switch in `BiometricCipherPlugin`, parse the `tag` argument using the existing `ArgumentName::kTag`, and call `IsKeyValidCoroutine`.
6. Implement `IsKeyValidCoroutine` in `BiometricCipherPlugin` following the same `fire_and_forget` + `hresult_error` catch pattern used by all existing coroutines; call `m_SecureService->IsKeyValidAsync(tag)` and return the `bool` result via `result->Success(isValid)`.
7. Add `IsKeyValidCoroutine` declaration to `biometric_cipher_plugin.h`.
8. Update `MockWindowsHelloRepository` to add a `MOCK_METHOD` for `IsKeyValidAsync` so the mock remains consistent with the interface (required for the existing test suite to compile).

---

## User Stories

**US-1 — Platform returns `false` for a missing credential without any biometric prompt**
As a Flutter developer consuming the `biometric_cipher` plugin, when I call `isKeyValid(tag)` on Windows and the Windows Hello credential does not exist (e.g., was deleted via `certutil` or a TPM clear), I need the method to return `false` without showing any Windows Hello dialog, so that `determineBiometricState()` can detect invalidation silently at init time.

**US-2 — Platform returns `true` for a valid credential without any biometric prompt**
As a Flutter developer consuming the `biometric_cipher` plugin, when I call `isKeyValid(tag)` on Windows and the credential exists and is accessible, I need the method to return `true` without showing any Windows Hello dialog, so that the biometric button is correctly displayed on the lock screen.

**US-3 — Method name matches Android and iOS/macOS handlers**
As a Flutter developer wiring the Dart-side method channel in Phase 12, I need the Windows handler to respond to the method name `"isKeyValid"` — the same string used by the Android and iOS/macOS handlers — so that a single `invokeMethod('isKeyValid', {'tag': tag})` call dispatches correctly on all platforms.

**US-4 — Plugin errors are surfaced, not swallowed**
As a Flutter developer, when `IsKeyValidAsync` throws an unexpected WinRT exception (e.g., `E_ACCESSDENIED`, hardware fault), I need the error to surface as a Flutter `MethodChannel` error (via `result->Error(...)`) rather than being silently ignored, so that the Dart layer can handle unexpected failures appropriately.

---

## Main Scenarios

### Scenario 1: Credential has been deleted — `isKeyValid` returns `false` silently

1. Phase 12 (Dart side) calls `invokeMethod('isKeyValid', {'tag': 'biometric'})` on Windows.
2. `BiometricCipherPlugin::HandleMethodCall` resolves `"isKeyValid"` → `MethodName::kIsKeyValid`.
3. Parser extracts `tag = "biometric"` using `ArgumentName::kTag`.
4. `IsKeyValidCoroutine("biometric", result)` is called.
5. `m_SecureService->IsKeyValidAsync("biometric")` is awaited.
6. `BiometricCipherService` converts tag to `hstring`, calls `m_WindowsHelloRepository->IsKeyValidAsync(hTag)`.
7. `WindowsHelloRepositoryImpl::IsKeyValidAsync`: `CheckWindowsHelloIsStatusAsync()` succeeds (Windows Hello available).
8. `m_HelloWrapper->OpenAsync(hTag)` returns `KeyCredentialStatus::NotFound` — credential does not exist.
9. `status == KeyCredentialStatus::Success` evaluates to `false`.
10. `co_return false` propagates up to `IsKeyValidCoroutine`.
11. `result->Success(false)` is called. No Windows Hello prompt was shown at any point.
12. Dart receives `false`. No biometric button is shown on the lock screen.

### Scenario 2: Valid credential exists — `isKeyValid` returns `true` silently

1–6. Same as Scenario 1.
7. `CheckWindowsHelloIsStatusAsync()` succeeds.
8. `m_HelloWrapper->OpenAsync(hTag)` returns `KeyCredentialStatus::Success`.
9. `status == KeyCredentialStatus::Success` evaluates to `true`.
10. `co_return true` propagates up.
11. `result->Success(true)` is called. No Windows Hello prompt was shown.
12. Dart receives `true`. Biometric button is displayed normally.

### Scenario 3: WinRT exception during key probe — error surfaced to Dart

1–6. Same as Scenario 1.
7. `CheckWindowsHelloIsStatusAsync()` or `OpenAsync()` throws `hresult_error` (e.g., hardware unavailable).
8. `IsKeyValidCoroutine` catch block executes: extracts `hr` and `message`, calls `OutputException`, calls `result->Error(GetErrorCodeString(hr), errorMessage)`.
9. Dart receives a `PlatformException`. Dart layer can handle or propagate as appropriate.

### Scenario 4: Existing method calls are unaffected (no regression)

1. Any call to `encrypt`, `decrypt`, `generateKey`, `deleteKey`, `getTPMStatus`, `getBiometryStatus`, or `configure` proceeds through the existing switch cases without change.
2. `kIsKeyValid` is a new enum value added before `kNotImplemented` — it does not alter the integer values or ordering of existing enum members in a way that affects runtime behavior (the switch dispatches by enum value, not by integer).
3. The `default` / `kNotImplemented` case continues to call `result->NotImplemented()` for unrecognized method names.

### Scenario 5: Mock stays compilable — test suite does not break

1. After adding `IsKeyValidAsync` to `WindowsHelloRepository`, `MockWindowsHelloRepository` must implement the new pure virtual method.
2. A `MOCK_METHOD` for `IsKeyValidAsync` is added to `mock_windows_hello_repository.h`.
3. Existing Windows tests (`biometric_cipher_service_test.cpp`, `windows_hello_repository_test.cpp`) compile and pass without change to their test logic.

---

## Success / Metrics

| Criterion | How to verify |
|-----------|--------------|
| `IsKeyValidAsync` pure virtual method added to `WindowsHelloRepository` | Code review of `windows_hello_repository.h` |
| `WindowsHelloRepositoryImpl` declares and implements `IsKeyValidAsync` | Code review of header + `.cpp` |
| Implementation calls `CheckWindowsHelloIsStatusAsync()` then `OpenAsync(tag)` | Code review |
| Returns `true` when `status == KeyCredentialStatus::Success`, `false` otherwise | Code review |
| `BiometricCipherService` declares and implements `IsKeyValidAsync(const std::string& tag)` | Code review |
| Service converts `std::string` tag to `hstring` before delegating | Code review |
| `kIsKeyValid` added to `MethodName` enum before `kNotImplemented` | Code review of `method_name.h` |
| `{"isKeyValid", MethodName::kIsKeyValid}` added to `METHOD_NAME_MAP` | Code review of `method_name.cpp` |
| `case MethodName::kIsKeyValid:` added to `HandleMethodCall` switch | Code review of `biometric_cipher_plugin.cpp` |
| `IsKeyValidCoroutine` declared in `biometric_cipher_plugin.h` | Code review |
| `IsKeyValidCoroutine` implemented following existing `fire_and_forget` + `hresult_error` pattern | Code review |
| `result->Success(isValid)` called with the `bool` return value | Code review |
| `MockWindowsHelloRepository` has `MOCK_METHOD` for `IsKeyValidAsync` | Code review of `mock_windows_hello_repository.h` |
| No Windows Hello prompt triggered during `isKeyValid` call | Design property — confirmed by `OpenAsync` API semantics |
| Method name `"isKeyValid"` matches Android (Phase 9) and iOS/macOS (Phase 10) | Cross-phase check |
| `fvm flutter build windows --debug` succeeds with no compilation errors | Build test |
| No new logging statements added | Code review |
| No new files created | Code review |

---

## Constraints and Assumptions

- **Windows C++ native layer only.** No changes to Dart files (`lib/`, `packages/biometric_cipher/lib/`), no changes to Android or iOS/macOS native code. All 8 touches are within `packages/biometric_cipher/windows/`.
- **No new files.** All changes are additions to existing files.
- **Task ordering is strict.** 11.1 (interface) → 11.2 (impl) → 11.3 (service) → 11.4 (enum + mapping) → 11.5 (plugin handler + coroutine) → mock update. Each step depends on the previous.
- **`ArgumentName::kTag` already exists.** Used by `encrypt`, `decrypt`, and `deleteKey` handlers. No new argument name is needed.
- **`CheckWindowsHelloIsStatusAsync()` already exists** as a private method in `WindowsHelloRepositoryImpl`. Re-use it as-is — no modification required.
- **`m_HelloWrapper->OpenAsync(tag)` already exists** and is called in `SignAsync`. The `IsKeyValidAsync` implementation reuses it for a metadata-only query (no signing operation follows).
- **No logging.** The operation is a silent probe with no observable side effects. The phase description explicitly prohibits adding logging.
- **`result->Success(isValid)` passes a `bool` directly.** The Flutter method channel's `StandardMethodCodec` encodes `bool` natively; no string conversion is needed.
- **Phases 9 and 10 must be complete** before Phase 11 ships, to ensure method name consistency is validated end-to-end.
- **Mock update is required** because `WindowsHelloRepository` is an abstract interface. Adding a pure virtual method without updating `MockWindowsHelloRepository` will cause a compilation error in any test that instantiates the mock.
- **Acceptance test is a build test only.** `fvm flutter build windows --debug` verifying no compilation errors. No automated behavior test is required for this phase (behavior testing is deferred to Phase 12/13 integration).

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| `KeyCredentialStatus` enum values other than `Success` and `NotFound` exist (e.g., `UserCanceled`) and are silently treated as `false` | Low — `isKeyValid` only checks existence; any non-`Success` status means the credential is not accessible | Low — returning `false` for unexpected statuses is the conservative correct behavior | Treat any non-`Success` status as `false`; document in code comment |
| `CheckWindowsHelloIsStatusAsync()` throws (Windows Hello not supported or not configured) when called from `IsKeyValidAsync` | Low — same guard is used in `SignAsync`; `isKeyValid` is not expected to be called when Windows Hello is unavailable | Medium — would surface as a WinRT exception to Dart rather than a clean `false` | The `hresult_error` catch in `IsKeyValidCoroutine` handles this; Dart layer receives an error rather than a crash |
| `MockWindowsHelloRepository` update is forgotten, breaking the test build | Medium — easy to overlook | High — CI build failure | Include mock update explicitly in task list and acceptance criteria |
| `kIsKeyValid` enum position (before `kNotImplemented`) shifts integer values of `kNotImplemented` if code elsewhere relies on its integer value | Very low — the switch dispatches by enum label, not by integer | None in practice | Confirmed: `GetMethodName` falls through to `kNotImplemented` by value comparison, not integer; no serialization of enum integers |
| Method name `"isKeyValid"` typo vs. Android/iOS handler | Low — string literal is specified in phase description and idea doc | High — Phase 12 Dart channel call would not reach the Windows handler | Cross-check string literal against Phase 9 and Phase 10 implementations before merging |

---

## Open Questions

None — the phase description, idea doc (section G2b), and vision doc provide sufficient technical detail to implement without ambiguity. The acceptance criterion (build test) is clear, and all architectural decisions are already established by Phases 9 and 10.
