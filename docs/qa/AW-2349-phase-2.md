# QA Plan: AW-2349 Phase 2 — Android Native: `ScreenLockStreamHandler`

Status: REVIEWED
Date: 2026-04-01

---

## Phase Scope

Phase 2 adds the Android native handler that feeds events into the `EventChannel("biometric_cipher/screen_lock")` established in Phase 1. It consists of exactly two files:

1. **New file:** `ScreenLockStreamHandler.kt` — a `BroadcastReceiver`-backed `EventChannel.StreamHandler` that listens for `ACTION_SCREEN_OFF` using the application context.
2. **Modified file:** `BiometricCipherPlugin.kt` — registers the `EventChannel` and `ScreenLockStreamHandler` in `onAttachedToEngine`, and tears them down in `onDetachedFromEngine`.

**Out of scope for Phase 2:** iOS/macOS handlers (Phase 3), Windows handler (Phase 4), plugin unit tests (Phase 5), example app wiring (Phases 6–8). No Dart files, no example app files, and no test files are modified in this phase.

---

## Implementation Status (observed)

### Task 2.1 — `ScreenLockStreamHandler.kt` (new file)

File path: `packages/biometric_cipher/android/src/main/kotlin/com/adguard/cryptowallet/biometric_cipher/handlers/ScreenLockStreamHandler.kt`

Findings:
- File is present in the new `handlers/` directory alongside the pre-existing `SecureMethodCallHandler.kt` and `SecureMethodCallHandlerImpl.kt`.
- Package declaration is correct: `com.adguard.cryptowallet.biometric_cipher.handlers`.
- Class implements `EventChannel.StreamHandler`.
- Constructor receives `applicationContext: Context` as a single parameter.
- `receiver: BroadcastReceiver?` field is private and nullable, initialized to `null`.
- `onListen`: creates an anonymous `BroadcastReceiver`, registers it with `applicationContext` using `IntentFilter(Intent.ACTION_SCREEN_OFF)`, stores it in `receiver`, then calls `events?.success(true)` on receipt.
- `onCancel`: unregisters and nullifies `receiver` via safe-call.
- All five imports are present: `BroadcastReceiver`, `Context`, `Intent`, `IntentFilter`, `EventChannel`.
- Implementation matches the spec in `docs/phase/AW-2349/phase-2.md` and `docs/idea-2349.md` exactly.

### Task 2.2 — EventChannel registered in `onAttachedToEngine`

File path: `packages/biometric_cipher/android/src/main/kotlin/com/adguard/cryptowallet/biometric_cipher/BiometricCipherPlugin.kt`

Findings:
- Class-level fields are present: `private var screenLockEventChannel: EventChannel? = null` (line 26) and `private var screenLockStreamHandler: ScreenLockStreamHandler? = null` (line 27).
- Both `EventChannel` and `ScreenLockStreamHandler` are imported at the top of the file (lines 17 and 6).
- In `onAttachedToEngine` (lines 68–75): `ScreenLockStreamHandler` is instantiated with `flutterPluginBinding.applicationContext`, an `EventChannel` is created with the channel name `"biometric_cipher/screen_lock"`, `setStreamHandler` is called, and both references are stored in the class fields.
- The EventChannel channel name string `"biometric_cipher/screen_lock"` matches the Dart-side `static const` string from Phase 1.
- Setup code appears after `biometricCipherMethodCallHandler.startListening(...)`, consistent with the order specified in the plan.

### Task 2.3 — Cleanup in `onDetachedFromEngine`

Findings:
- `onDetachedFromEngine` (lines 82–87): calls `screenLockEventChannel?.setStreamHandler(null)`, then nullifies both `screenLockEventChannel` and `screenLockStreamHandler`.
- This matches the spec exactly.
- `biometricCipherMethodCallHandler.stopListening()` is called first, preserving existing cleanup order.

**All three tasks in Phase 2 are fully implemented as specified.**

---

## Positive Scenarios

### PS-1: `ScreenLockStreamHandler` is instantiated with application context
- `BiometricCipherPlugin.onAttachedToEngine` passes `flutterPluginBinding.applicationContext` to `ScreenLockStreamHandler`.
- Application context (not activity context) is used — safe when the activity may be absent during screen-off.
- Verified: `BiometricCipherPlugin.kt` line 68.

### PS-2: EventChannel is created with the correct channel name
- `EventChannel(flutterPluginBinding.binaryMessenger, "biometric_cipher/screen_lock")` exactly matches the Dart-side constant `_screenLockEventChannel = EventChannel('biometric_cipher/screen_lock')` from Phase 1.
- Verified: `BiometricCipherPlugin.kt` line 69–72.

### PS-3: `onListen` registers a `BroadcastReceiver` for `ACTION_SCREEN_OFF`
- When Dart code first subscribes to `BiometricCipher.screenLockStream`, Flutter calls `onListen` on the handler.
- A new `BroadcastReceiver` is created and registered with the application context via `IntentFilter(Intent.ACTION_SCREEN_OFF)`.
- The receiver reference is stored in `this.receiver` for later unregistration.
- Verified: `ScreenLockStreamHandler.kt` lines 15–27.

### PS-4: Screen-off event propagates `true` to Dart
- When `ACTION_SCREEN_OFF` is broadcast by the OS, `onReceive` checks `intent?.action == Intent.ACTION_SCREEN_OFF` and calls `events?.success(true)`.
- This pushes `true` through the EventChannel to the Dart `Stream<bool>`.
- Verified: `ScreenLockStreamHandler.kt` lines 16–22.

### PS-5: `onCancel` unregisters the receiver cleanly
- When the Dart side cancels the stream subscription (e.g., `ScreenLockService.stopListening()`), Flutter calls `onCancel`.
- `receiver?.let { applicationContext.unregisterReceiver(it) }` safely unregisters only if registered.
- `receiver` is set to `null` after unregistration, preventing a double-unregister.
- Verified: `ScreenLockStreamHandler.kt` lines 29–32.

### PS-6: Plugin detach clears the stream handler reference
- `onDetachedFromEngine` calls `screenLockEventChannel?.setStreamHandler(null)`, which triggers `onCancel` on any active subscription and detaches the handler.
- Both fields are nullified, releasing references to the handler and channel.
- Verified: `BiometricCipherPlugin.kt` lines 83–86.

### PS-7: Multiple `ACTION_SCREEN_OFF` events produce multiple `true` emissions
- If the screen is turned off multiple times during an active subscription (e.g., repeated lock/unlock cycles), each `ACTION_SCREEN_OFF` broadcast triggers `events?.success(true)`.
- The Dart broadcast stream receives each event independently.
- This is guaranteed by the `BroadcastReceiver.onReceive` firing for each intent.

### PS-8: Phase 1 Dart-side contract is preserved
- No changes were made to the Phase 1 Dart files (`biometric_cipher_platform_interface.dart`, `biometric_cipher_method_channel.dart`, `biometric_cipher.dart`, mock, test).
- The `late final` `screenLockStream` on `MethodChannelBiometricCipher` now has a live native counterpart.

### PS-9: Existing plugin functionality is not regressed
- `onAttachedToEngine` still creates and starts the existing `SecureMethodCallHandler` before the new EventChannel setup.
- `onDetachedFromEngine` still calls `biometricCipherMethodCallHandler.stopListening()` before the new cleanup.
- No existing fields, imports, or methods were removed or changed.

---

## Negative and Edge Cases

### NC-1: `onListen` called when `events` is null
- `events` parameter in `onListen` is typed `EventChannel.EventSink?`.
- The `BroadcastReceiver` uses `events?.success(true)` — the safe-call means a null `events` is silently ignored.
- In practice Flutter never passes null `events` to `onListen`, but the null-safe call is defensive and correct.

### NC-2: `onCancel` called before `onListen` (receiver is null)
- If `onCancel` is invoked when no listener was registered (i.e., `receiver == null`), the safe-call `receiver?.let { ... }` is a no-op.
- No `IllegalArgumentException` from unregistering an unregistered receiver.
- Verified: `ScreenLockStreamHandler.kt` line 30.

### NC-3: `onListen` called a second time without an intervening `onCancel` (double-register)
- The spec defines the EventChannel lifecycle as: `onListen` once, then `onCancel` once.
- If `onListen` were called twice, the first `BroadcastReceiver` would be overwritten in `receiver` (line 25), causing a leak — the first receiver would never be unregistered.
- This scenario is not possible under the Flutter EventChannel contract (only one Dart listener at a time per channel), but no guard exists inside `onListen` to unregister a previously stored `receiver` before overwriting it.
- **Assessment:** Low risk — the Flutter EventChannel protocol guarantees `onCancel` before any subsequent `onListen`. No production defect. However, a defensive `onCancel(null)` call at the start of `onListen` would be belt-and-suspenders hygiene. Not blocking.

### NC-4: Receiver not unregistered when engine detaches with active subscription
- If the Dart stream is actively subscribed when `onDetachedFromEngine` is called, the call chain is: `setStreamHandler(null)` → Flutter engine calls `onCancel` internally → `unregisterReceiver` is called.
- This cleanup path depends on the Flutter engine calling `onCancel` as part of `setStreamHandler(null)`. This is the documented Flutter EventChannel behavior.
- **Assessment:** Correct by design. The cleanup order (set handler to null, then nullify fields) is consistent with the Flutter plugin lifecycle guidelines.

### NC-5: `ACTION_SCREEN_OFF` on Android API level with behavioral differences
- `ACTION_SCREEN_OFF` is a protected broadcast and has been available since API 1. It cannot be registered in the manifest — only dynamic registration is supported.
- The implementation uses dynamic registration (`registerReceiver` inside `onListen`), which is the only supported approach.
- Confirmed compatible across all target Android API levels.

### NC-6: App in background when screen turns off
- If the Flutter engine is suspended (app backgrounded) when `ACTION_SCREEN_OFF` fires, the `BroadcastReceiver` is still registered with the application context and will receive the intent.
- However, `events?.success(true)` delivers the event to the Flutter EventChannel, which may buffer or drop the event depending on engine state.
- Per `docs/idea-2349.md`: "if the app is already suspended when the device locks, the EventChannel event may not be delivered. This is acceptable because the existing `shouldLockOnResume` mechanism handles this case."
- **Assessment:** Known, accepted edge case. Covered by the existing timer/resume fallback.

### NC-7: Screen turns off without a configured lock screen (no passcode)
- `ACTION_SCREEN_OFF` fires regardless of whether the device has a PIN/password/biometric lock configured. The MFA spec requires locking on every screen-off, even on unprotected devices.
- The implementation correctly uses `ACTION_SCREEN_OFF` rather than `KeyguardManager.isKeyguardLocked()`, which would not fire synchronously.
- No conditional logic based on lock screen configuration — `events?.success(true)` is called unconditionally.
- **Assessment:** Correct and intentional. Matches the security-first design decision documented in `docs/idea-2349.md`.

### NC-8: No native-side unit tests for `ScreenLockStreamHandler`
- Phase 2 does not add Android JVM/instrumented unit tests for `ScreenLockStreamHandler`.
- `BroadcastReceiver` registration/unregistration in `onListen`/`onCancel` is tested via the acceptance criterion (`fvm flutter build apk --debug`) and manual device verification.
- Plugin-level Dart tests covering `screenLockStream` are explicitly deferred to Phase 5 (tasklist iteration 5.1–5.2).
- **Assessment:** Acceptable gap for this phase. Phase 5 will add the Dart test coverage. Native Kotlin unit tests for the handler class are not part of the plan.

### NC-9: EventChannel channel name hardcoded as a literal string in `BiometricCipherPlugin.kt`
- The channel name `"biometric_cipher/screen_lock"` appears as a string literal in `BiometricCipherPlugin.kt` line 71, not as a reference to the Dart `static const` (which is in Dart code and is not accessible from Kotlin).
- This is a cross-language boundary — Kotlin cannot import Dart constants.
- The single source of truth for the channel name in Kotlin is this literal. Any future rename must be updated in both Dart and Kotlin.
- **Assessment:** Accepted limitation of the Flutter plugin architecture. The Phase 2 plan explicitly documents this: "Native phases reference it by this constant indirectly by documenting the identical string." The strings currently match. Low risk of regression since the channel name is unlikely to change.

### NC-10: `screenLockStreamHandler` field stored but not used after initialization
- The plan's implementation notes say: "The `screenLockStreamHandler` field is stored but not otherwise used after setup; keeping the reference prevents premature GC and makes cleanup explicit."
- Verified: the field is assigned in `onAttachedToEngine` and nullified in `onDetachedFromEngine`, with no other reads.
- **Assessment:** Correct by design. The reference prevents the handler from being garbage-collected before `onDetachedFromEngine`.

---

## Automated Tests Coverage

| Test | File | Status |
|------|------|--------|
| Android APK builds without errors | `cd example && fvm flutter build apk --debug` | Manual verification required (acceptance criterion) |
| `screenLockStream` emits events from platform (Dart) | `packages/biometric_cipher/test/biometric_cipher_test.dart` | Present from Phase 1, green — but exercises mock, not the new Kotlin handler |
| Kotlin unit tests for `ScreenLockStreamHandler` | — | **Not present** (deferred to Phase 5 instrumented tests or manual testing) |
| `onListen` / `onCancel` lifecycle via EventChannel | — | **Not present** in this phase; covered by Phase 5 |
| All pre-existing plugin Dart tests | `packages/biometric_cipher/test/biometric_cipher_test.dart` | Unaffected by Phase 2 changes |

**Overall automated coverage for Phase 2:** The phase has no automated test additions of its own. All new code is Kotlin and requires either an instrumented Android test or a real/emulator device to verify. The acceptance criterion (`flutter build apk --debug`) validates compilation correctness but not runtime behavior. Runtime behavior must be manually verified. Phase 5 will address the test gap.

---

## Manual Checks Needed

### MC-1: Android APK builds without compilation errors
Run from the `example/` directory:
```
fvm flutter build apk --debug
```
Expected: build succeeds with exit code 0. This validates that:
- `ScreenLockStreamHandler.kt` compiles without errors.
- The `handlers/` package is on the Kotlin source path.
- All imports (`BroadcastReceiver`, `Context`, `Intent`, `IntentFilter`, `EventChannel`) resolve correctly.
- `BiometricCipherPlugin.kt` compiles with the new imports and fields.
- No Kotlin compilation errors from the modified plugin code.

### MC-2: EventChannel channel name string matches exactly
Visually confirm that `BiometricCipherPlugin.kt` line 71 contains:
```
"biometric_cipher/screen_lock"
```
and that `biometric_cipher_method_channel.dart` line 12 contains:
```
'biometric_cipher/screen_lock'
```
These two strings must be identical (modulo quote style). A mismatch would cause the stream to silently produce no events.

### MC-3: Screen lock event fires on a physical or emulated Android device
Manual end-to-end test:
1. Install the debug APK on an Android device or emulator.
2. Open the example app and unlock the locker with a password.
3. Confirm the locker is in `unlocked` state.
4. Lock the device screen (power button or `adb shell input keyevent KEYCODE_POWER`).
5. Observe: the `ACTION_SCREEN_OFF` broadcast fires; the `BroadcastReceiver.onReceive` is triggered; `events?.success(true)` is called; the Dart stream emits `true`.
6. For now (Phases 3–8 not implemented): verify the raw event is emitted by observing logcat or adding a temporary print to `LockerBloc` or `ScreenLockService` (once wired in Phase 5+).

Note: End-to-end lock behavior (locker state changing to `locked`) cannot be fully verified until Phases 5–8 wire `ScreenLockService` into `LockerBloc`. Phase 2's scope ends at the native event delivery.

### MC-4: `onCancel` unregisters the receiver (no crash on teardown)
1. With the debug APK running, subscribe to `screenLockStream` (will happen automatically once Phase 5+ is wired; for now, add a temporary subscriber in a test harness or the example app).
2. Navigate away from the screen or kill the app.
3. Confirm no `IllegalArgumentException: Receiver not registered` or ANR in logcat.

### MC-5: No changes outside `packages/biometric_cipher/android/`
Confirm via `git diff --name-only` on the current branch that only the following files are added/modified compared to the Phase 1 state:
- `packages/biometric_cipher/android/src/main/kotlin/com/adguard/cryptowallet/biometric_cipher/handlers/ScreenLockStreamHandler.kt` (new)
- `packages/biometric_cipher/android/src/main/kotlin/com/adguard/cryptowallet/biometric_cipher/BiometricCipherPlugin.kt` (modified)

No Dart files, no iOS/macOS/Windows files, no example app files, and no test files should appear in the diff for Phase 2.

### MC-6: Existing biometric functionality unaffected on Android
Run the example app on Android and verify:
- Password-based unlock works.
- Biometric (fingerprint/face) unlock works.
- Lock via timer still fires.
- Lock on background resume still fires (`shouldLockOnResume`).

---

## Risk Zone

| Risk | Likelihood | Impact | Assessment |
|------|-----------|--------|------------|
| Channel name string literal mismatch between Kotlin and Dart | Low | High | Both strings currently match `"biometric_cipher/screen_lock"`. Cross-language constant sharing is impossible; the risk is a future rename updating only one side. |
| `onListen` double-call leaves a leaked `BroadcastReceiver` | Very Low | Medium | Not possible under Flutter EventChannel protocol. No defensive guard in the implementation; acceptable given the guarantee. |
| `BroadcastReceiver` not unregistered if engine detaches with active stream | Very Low | Low | `setStreamHandler(null)` triggers `onCancel` per Flutter's EventChannel contract. Correctly handled. |
| App backgrounded during screen-off causes event loss | Medium | Low | Accepted, documented edge case. The existing `shouldLockOnResume` fallback covers it. |
| No automated tests for Kotlin handler in Phase 2 | Certain | Medium | Accepted — Phase 5 covers this. Manual device test (MC-3) is required before merging. |
| `ACTION_SCREEN_OFF` fires on screen-off without a configured lock screen | N/A | N/A | Intentional behavior per security spec. No risk. |
| Kotlin code causes minification issues in release APK | Low | Low | `ScreenLockStreamHandler` is an inner-package class with no reflection usage. No ProGuard rules needed. |

---

## Final Verdict

**RELEASE WITH RESERVATIONS**

Phase 2 delivers a correct, minimal Android native implementation that matches the specification in all observable respects. The `ScreenLockStreamHandler.kt` file and the `BiometricCipherPlugin.kt` modifications are both exactly as designed. The EventChannel channel name matches the Dart constant. Application context is used correctly. The `BroadcastReceiver` lifecycle is properly tied to `onListen`/`onCancel`. Engine-detach cleanup is correct.

The reservation is **MC-3 (manual device test)**: the Android APK build (`MC-1`) confirms compilation, but actual `ACTION_SCREEN_OFF` delivery and propagation to the Dart stream must be verified on a device or emulator before the branch can be considered fully validated. Without a live test there is no assurance that the EventChannel binary messenger is correctly wired to the right channel name, that the `BroadcastReceiver` fires, or that `events?.success(true)` reaches Dart.

The absence of automated Kotlin-side tests (NC-8) is an accepted gap per the project plan — Phase 5 will add coverage.

Phase 2 is ready to proceed to Phase 3 (iOS/macOS) once `MC-1` (APK build) and `MC-3` (device smoke test) are confirmed passing.
