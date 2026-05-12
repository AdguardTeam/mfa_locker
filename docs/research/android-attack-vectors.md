# mfa_locker — Android attack-vector analysis

**Status:** working notes for a red-team exercise. Target: the Android build
of `mfa_locker` as used by a crypto-wallet application.
**Date:** 2026-05-12
**Scope:** Decryption / tamper attacks against the on-disk vault. Android
sits between Windows (very open) and iOS (very closed): app sandbox is
strong, but root devices, Auto Backup, and overlay/keylogger malware create
real attack surfaces.

> Companion files: `windows-attack-vectors.md`, `macos-attack-vectors.md`,
> `ios-attack-vectors.md`.

---

## 1. Crypto / storage recap (Android specifics)

- **Storage file:** plain JSON in the app's private data directory
  (`/data/data/<package>/files/...` or `getFilesDir()`-relative). Owned by
  the app's per-app UID. Other apps cannot read without root.
- **App sandbox:** Linux per-UID isolation. Each app has a unique UID; the
  filesystem permissions are enforced by the kernel.
- **Biometric wrap (Android):** Android Keystore **symmetric** AES-256-GCM
  (`packages/biometric_cipher/android/src/main/kotlin/.../SecureRepositoryImpl.kt`):
  - Algorithm: `AES/GCM/NoPadding` (`SecureObjects.kt:7`).
  - `setUserAuthenticationRequired(true)` + `setUserAuthenticationParameters(0, AUTH_BIOMETRIC_STRONG)` — every operation needs **fresh** biometric authentication (timeout 0).
  - `BiometricPrompt.CryptoObject(cipher)` — the cipher is hardware-bound to the auth event; only after `onAuthenticationSucceeded` is it usable.
  - `setIsStrongBoxBacked(true)` when StrongBox is available (`SecureRepositoryImpl.kt:44`) — keys live in a dedicated hardware secure element separate from TEE.
  - `KeyPermanentlyInvalidatedException` fires on biometric re-enrollment — wrap becomes permanently unusable, forcing rewrap.
- **Key alias:** `biometric_cipher_<tag>` (`SecureObjects.kt:5`). Scoped per
  UID — predictable but not cross-app addressable.
- **Cross-platform crypto:** unchanged Argon2id `m=19 MiB / t=2` for password
  wrap; same UTF-16 → byte truncation for non-ASCII passwords.

This is the **strongest** biometric chain of the four platforms in terms of
local malware resistance:
- Symmetric key never leaves hardware.
- Per-op biometric (no replay window).
- Auto-invalidate on enrollment change.
- Per-app file isolation by kernel.

---

## 2. Attack vectors

### Vector A″ — Cross-app Keystore access  *(blocked on Android)*

Android Keystore aliases are scoped per UID. A different installed app cannot
open `biometric_cipher_biometric` — Keystore returns `KeyNotFound`. The
Windows-style replay (Vector A) does not apply.

Listed here only so the comparison with other platforms is complete.

---

### Vector B — Offline password brute force  *(cross-platform)*

The same offline Argon2id brute force as everywhere else, applicable when
the attacker obtains the vault file (Vectors C / D / E below). The Rust
implementation is identical to the Windows one.

---

### Vector C — Rooted device  *(the main local-attacker path)*

`/data/data/<package>/files/` is owned by the per-app UID and mode 0700 by
default. Other apps can't read it. `root` can.

- Many users install custom ROMs / `magisk`-rooted devices and grant root to
  random apps (file managers, ad-blockers, "system tuners").
- Once a malicious app holds root, it can `cat` the vault JSON in milliseconds.
- The biometric wrap is unusable to the attacker (the AES key stays in
  Keystore/StrongBox; `root` cannot dump Keystore keys). The **password
  wrap**, however, is offline-brute-forceable — Vector B applies.
- For users without a password set (bio-only), the vault would be unreadable
  from the file alone — but the example app's flow does set up a password
  wrap. So the password-wrap brute-force path always exists.

Severity: medium-high. Rooted devices are common (1–3% of Android users
based on recent industry reports). For a crypto wallet, that's a meaningful
fraction.

---

### Vector D — Auto Backup / `allowBackup` exfiltration

Android's Auto Backup (`adb backup` and Google Cloud backup) uploads app
data to Google Drive when:

- `android:allowBackup="true"` (default unless explicitly disabled).
- `android:fullBackupContent` doesn't exclude the file.
- The user has backup enabled in Android settings.

If enabled, the vault file ends up in the user's Google Drive backup. An
attacker who compromises the Google account can pull it (`adb` is gated,
but Drive sync isn't from Google's side once authenticated).

**Action item for defenders:** explicitly set `android:allowBackup="false"`
in the host app's `AndroidManifest.xml`, OR provide a `<full-backup-content>`
XML excluding the vault path. Verify the example app and host app config.

This is the Android analog of iOS Vector C and roughly the same severity.

---

### Vector E — `adb backup` on debuggable / engineering builds

If the host app ships with `android:debuggable="true"` (e.g., internal beta
APK accidentally promoted), `adb backup -f vault.ab <package>` extracts the
private data dir to a backup archive readable on a PC. No root needed.

Stock production APKs should not be debuggable. Worth verifying on every
release.

---

### Vector F — Overlay attacks against the unlock UI

`BiometricPrompt` is shown by the system and is overlay-resistant (the
system suppresses screen overlays during the prompt as of Android 12+).
**The app's password input is not** — it's an ordinary Flutter `TextField`.

Attack chain:
1. Malicious app with `SYSTEM_ALERT_WINDOW` permission (or `BIND_ACCESSIBILITY_SERVICE`) draws a transparent overlay over the password field.
2. User types password into the overlay, which forwards keystrokes to the real field — keys captured.
3. Attacker now has the password → Vector B → game over.

`SYSTEM_ALERT_WINDOW` is no longer auto-granted on modern Android, but
accessibility services are still trivially exploited by social-engineered
malware ("turn on accessibility for our app").

Mitigation in app code: detect overlays (`MotionEvent.FLAG_WINDOW_IS_OBSCURED`)
on the password input and refuse input. The Flutter app does not currently
do this.

---

### Vector G — Screen recording / capture

If the host app does not set `FLAG_SECURE` on the unlock window, the
password input and decrypted entry values can be captured by:

- Built-in screen recorders (most modern Android has one).
- MediaProjection-using apps the user has granted screen capture to.
- ADB `screenrecord` on debuggable builds.

`FLAG_SECURE` blocks all three. Verify host activity sets it for sensitive
screens. The library can't force this — it's an app-shell concern.

---

### Vector H — Accessibility-service keylogger

A malicious app with `BIND_ACCESSIBILITY_SERVICE`:

- Receives `AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED` for password fields
  unless the field is marked `password` and the malicious service hasn't
  bypassed the protection.
- Can perform gesture injection to dismiss security dialogs, etc.
- Cannot trigger the biometric prompt on the user's behalf — biometric is
  TEE-enforced. But it captures passwords, and Vector B does the rest.

Same end state as Vector F (overlay) — different mechanism, same payoff.

---

### Vector I — Static analysis of the APK

Reconnaissance, not a direct attack:

- Argon2id constants (`19456, 1, 2`) and `KEY_PREFIX = "biometric_cipher_"`
  are extractable from the Dart/Kotlin code in the APK via `apktool` +
  `dexdump` or `jadx`.
- The hardcoded `keyTag = "biometric"` is the default — host app may override.
- Confirms parameters for the offline brute-forcer (Vector B).

---

### Vector J — Hardware StrongBox bypass (residual risk)

On devices where StrongBox is unavailable, keys fall back to TEE
(`setIsStrongBoxBacked(isStrongBoxAvailable())`, `SecureRepositoryImpl.kt:44`).
TEE has historically had vulnerabilities (Qualcomm QSEE, Samsung TEEGRIS,
TrustZone bugs) leading to occasional key extraction in research papers.

Not a practical attacker tool target — depends on a fresh n-day exploit for
a specific chipset. Listed for completeness.

---

## 3. Priority ranking for a PoC tool

| Rank | Vector | Why                                                                                                       | Cost   |
|------|--------|-----------------------------------------------------------------------------------------------------------|--------|
| 1    | C + B  | Rooted device → vault file → offline Argon2id. Direct, no user interaction beyond initial root grant.     | Low.   |
| 2    | D + B  | Auto Backup → Google Drive → offline. Depends on host-app manifest config.                                | Medium.|
| 3    | F      | Overlay/accessibility password capture. Demonstrates the password-input weakness.                         | Medium.|
| 4    | E + B  | `adb backup` on debuggable build. Sanity check for release-config hygiene.                                | Low.   |

Practical PoC tooling:
- **Rust offline brute-forcer:** shared across all platforms.
- **Android malicious-companion APK** to demonstrate overlay capture (F) and Auto Backup retrieval (D). Both are standard Android-security course material; nothing exotic.

There is no realistic Rust-on-Android tool that bypasses the per-UID sandbox.
The Rust component is offline-only; on-device demos need an APK.

---

## 4. Pointers into the codebase

- Keystore key generation (StrongBox, per-op bio):   `packages/biometric_cipher/android/src/main/kotlin/com/adguard/cryptowallet/biometric_cipher/repositories/SecureRepositoryImpl.kt`
- BiometricPrompt wiring (CryptoObject):             `packages/biometric_cipher/android/src/main/kotlin/com/adguard/cryptowallet/biometric_cipher/repositories/AuthenticationRepositoryImpl.kt`
- Service glue:                                      `packages/biometric_cipher/android/src/main/kotlin/com/adguard/cryptowallet/biometric_cipher/services/SecureServiceImpl.kt`
- Constants (predictable alias prefix):              `packages/biometric_cipher/android/src/main/kotlin/com/adguard/cryptowallet/biometric_cipher/objects/SecureObjects.kt`
- Cross-platform crypto + Argon2:                    `lib/utils/cryptography_utils.dart`
- Password wrap (truncation bug):                    `lib/security/models/password_cipher_func.dart:16`
- Storage I/O (no Android-specific hardening):       `lib/storage/encrypted_storage_impl.dart`

---

## 5. Open questions for the next session

- **`android:allowBackup`**: what is the example app and intended host-app value? If `true` or unset, file as P1 — Vector D is wide open.
- **`android:debuggable`** in release builds: confirm `false`. Verify CI gate.
- **`FLAG_SECURE`** on the unlock activity: is it set? If not, file Vectors G/F as P1.
- **Overlay protection** on password input: does the app check `FLAG_WINDOW_IS_OBSCURED` or `MotionEvent.FLAG_WINDOW_IS_PARTIALLY_OBSCURED`? Default is no.
- **Root detection**: is there a SafetyNet / Play Integrity API check on app start? If not, Vector C is unmitigated.
- **StrongBox usage in production**: a meaningful share of mid-range devices lack StrongBox and fall through to TEE. Confirm logging or telemetry exists to know which class of users is on which backend.
- **Keystore key alias collision**: `biometric_cipher_biometric` is a constant. If the host app uses multiple `BioCipherFunc` instances with different tags, are they namespaced? Currently yes (per-`tag`), but verify host doesn't reuse aliases.
