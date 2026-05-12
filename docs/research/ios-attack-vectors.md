# mfa_locker — iOS attack-vector analysis

**Status:** working notes for a red-team exercise. Target: the iOS build of
`mfa_locker` as used by a crypto-wallet application.
**Date:** 2026-05-12
**Scope:** Decryption / tamper attacks against the on-disk vault. iOS is the
most-restricted target — most of the attack surface is **off-device** (cloud
backups, supply chain) or **off-stock** (jailbreak).

> Companion files: `windows-attack-vectors.md`, `macos-attack-vectors.md`,
> `android-attack-vectors.md`. The Darwin native layer (Secure Enclave + ECIES
> ECC P-256) is shared with macOS; the platform difference is what's around
> it (sandbox, backups, distribution).

---

## 1. Crypto / storage recap (iOS specifics)

- **Native biometric implementation: shared with macOS** — same files in
  `packages/biometric_cipher/darwin/Classes/`. Secure Enclave P-256 + ECIES
  (`.eciesEncryptionCofactorX963SHA256AESGCM`), `.biometryCurrentSet`,
  `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
- **Storage file location:** inside the app sandbox — typically
  `<App_Sandbox>/Library/Application Support/<name>.json` or
  `Documents/<name>.json` depending on how the host app builds the path.
  `_restrictFilePermissionsIfSupported` does **not** chmod on iOS
  (`lib/storage/encrypted_storage_impl.dart:643` is macOS-only). It doesn't
  need to — sandbox makes the file unreachable from other apps anyway.
- **App sandbox:** every iOS app runs in its own data container, isolated by
  the kernel. `/var/mobile/Containers/Data/Application/<UUID>/...` — not
  enumerable by other apps.
- **Keychain scope:** Keychain items default to the app's
  `kSecAttrAccessGroup` (Team ID + Bundle ID). Other apps cannot read without
  matching `keychain-access-groups` entitlement signed by the same Team ID.
- **Cross-platform issues retained:** Argon2id `m=19 MiB / t=2`, UTF-16 →
  byte truncation in password handling, Dart String GC residue — all carry
  over (`lib/utils/cryptography_utils.dart`, `lib/security/models/password_cipher_func.dart:16`).

---

## 2. Attack vectors

### Vector A′ — Sibling-app Secure Enclave access  *(requires Team ID)*

Same idea as macOS Vector A′ but stricter on iOS:

- An app that wants to read the wallet's SE key must hold a
  `keychain-access-groups` entitlement that names the same access group, **and**
  be signed by the same Team ID, **and** be installed on the device.
- Realistic execution paths:
  1. **Compromised companion app from the same publisher** (helper app,
     widget, share extension) sharing the Team ID and access group. If
     compromised via supply-chain attack, it can call the same SE key.
  2. **Malicious SDK linked into the wallet itself** — an embedded analytics
     / push / crash-reporting SDK runs in the wallet's own sandbox and shares
     all entitlements. This is the most concerning iOS supply-chain risk.
  3. **App-extension / share-extension** of the wallet, if it inherits the
     access group: a future bug there could trigger SE decryption on
     attacker-supplied wrap data.

iOS does NOT permit a different-Team-ID app to access the key. Vector A
(Windows-style replay across user identity) is closed.

---

### Vector B — Offline password brute force  *(cross-platform)*

Pure crypto-layer attack. Identical to other platforms once the attacker
holds the JSON. The interesting question is **how the attacker gets the
JSON on iOS** — that's Vectors C and D below.

---

### Vector C — iCloud Backup exfiltration  *(highest blast radius)*

iOS iCloud Backup includes the app's entire sandbox **unless** the file is
marked excluded:

- Files in `<App>/Documents/` and `<App>/Library/Application Support/`
  are backed up by default.
- Files in `<App>/Library/Caches/` and `<App>/tmp/` are not.
- A file flagged with `NSURLIsExcludedFromBackupKey` is excluded.

`mfa_locker` does not call this — the encrypted vault rides along.

**Attack chain.**
1. Compromise the user's Apple ID (phishing, credential stuffing, password reuse).
2. Use commercial tooling (Elcomsoft Phone Breaker, Reincubate iPhone Backup
   Extractor, libimobiledevice + custom scripts) to download the iCloud
   backup.
3. Extract the wallet's container, locate the vault JSON.
4. Offline Argon2id brute force (Vector B). For a wallet-grade password the
   factor of safety here is **only** the password the user picked + Argon2id
   parameters. The Argon2id `m=19 MiB / t=2` parameters are the same problem
   as on every other platform.

This is the **single most realistic attack on the iOS build**. It does not
require malware on the device, doesn't touch Secure Enclave, doesn't need
jailbreak. It needs:
- A compromised Apple ID, **and**
- A weak-enough password to brute force.

Secure Enclave keys themselves are **not** in the backup (they cannot leave
the SE), so the `bio` wrap is unusable from an exfiltrated backup. Only the
`pwd` wrap matters here — but that's exactly the one with the weak Argon2id
parameters.

---

### Vector D — Jailbreak / device-side compromise

On a jailbroken device or a device with a known sandbox-escape exploit:

- `/var/mobile/Containers/Data/Application/<UUID>/` is readable as `root`.
- Frida + `objc::frida-trace` can hook the SE key call sites: the attacker
  doesn't need to extract the key — they need to be inside the wallet process
  when biometric auth succeeds, then snapshot the master key from RAM.
- `task_for_pid` is gated on iOS but jailbreaks routinely bypass.

Not a "build a Rust tool" attack — more of a "we lose on this device class."
Defenders should:
- Detect jailbreak indicators on startup, refuse to unlock.
- Use the SE key's `.biometryCurrentSet` to limit linger time of derived
  state in memory (the locker already does this).

The locker's current code does **not** appear to have jailbreak detection.

---

### Vector E — Lockdown / DFU / forensic extraction

Physical attacker with the locked device and access to commercial forensic
tools (Cellebrite, GrayKey, Magnet AXIOM):

- iOS extracts via "BFU" (before-first-unlock) vs "AFU" (after-first-unlock).
- `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` (used for the SE key) makes
  the key inaccessible until the device is unlocked once after boot.
- `NSFileProtectionComplete` (`kSecAttrAccessibleWhenUnlocked`) would protect
  the vault JSON similarly. **The current code does not explicitly set
  protection class on the vault file** — it gets the default
  (`NSFileProtectionCompleteUntilFirstUserAuthentication`), so the file is
  readable after the user has unlocked the device once even if subsequently
  re-locked. That's the weaker default.

Effect: an attacker with AFU forensic extraction gets the JSON. They then
need the password (Vector B) or a hot device (Vector D).

**Recommended hardening (out of scope for the PoC):** explicitly set
`NSFileProtectionComplete` on the vault file. Stiffens this vector.

---

### Vector F — Static analysis of the IPA

Not an attack on a specific vault — but useful reconnaissance:

- Hardcoded strings extractable from the binary:
  - `com.adguard.tpm.secureEnclavePrivateKey` (Keychain tag prefix).
  - `biometric` (default `keyTag`).
  - `locker_authentication_request` (default `windowsAuthData`, irrelevant on iOS but ships with the cross-platform library).
- Argon2id parameters: `19456, 1, 2` are in `cryptography_utils.dart` and
  visible in the AOT-compiled binary as constants.
- These confirm parameters for the offline brute-forcer; they do not break
  iOS sandboxing.

---

### Vector G — Side-channel / power analysis on Secure Enclave

Rare, expensive, requires physical device + custom equipment, requires SE-
specific exploitation research. Listed for completeness; not relevant for a
Rust PoC.

---

### Vector H — Pasteboard / screen-recording leakage

Out-of-channel leaks once the wallet is unlocked:

- If the wallet copies addresses / seeds to UIPasteboard without
  `localOnly: true` and an expiration date, the universal clipboard syncs
  them to other signed-in Apple devices (and through iCloud).
- iOS 14+ shows a banner on pasteboard read — visible signal to user, but
  the data has already been copied.
- App should set `UIScreen.isCaptured`/`isMirrored` checks and block sensitive
  UI when screen recording / mirroring is active.

Not part of the on-disk vault attack surface, but for a wallet these leaks
typically dominate the threat model.

---

## 3. Priority ranking for a PoC tool

| Rank | Vector | Why                                                                                                       | Cost   |
|------|--------|-----------------------------------------------------------------------------------------------------------|--------|
| 1    | C + B  | iCloud backup + offline Argon2id brute force. No malware, no jailbreak — realistic and historically common.| Medium.|
| 2    | E + B  | Forensic-tool extraction + Argon2id. Targets specific high-value users.                                   | High.  |
| 3    | A′     | Sibling-app SE access requires supply-chain / SDK compromise. Niche but recurring industry-wide.          | High.  |
| 4    | D      | Jailbreak. Out of scope for a Rust PoC; document as residual risk.                                        | —      |

Practically, an iOS PoC would be:
- **Tool 1 (cross-platform Rust):** parser + Argon2id brute-forcer fed by an
  iCloud-backup extraction. Same brute-forcer used for all platforms.
- **Tool 2 (Swift on a real iPhone):** demo of A′ — two test apps signed under
  the same Team ID, one writing, one reading the SE wrap, to demonstrate that
  the sibling-app boundary exists but is paper-thin once supply chain is
  compromised.

There is no realistic Rust-on-iOS attacker tool that bypasses the sandbox on
stock iOS. The Rust component is offline-only.

---

## 4. Pointers into the codebase

- Secure Enclave manager (shared with macOS): `packages/biometric_cipher/darwin/Classes/Managers/SecureEnclaveManager.swift`
- Keychain glue:                                `packages/biometric_cipher/darwin/Classes/Services/KeychainService.swift`
- Access control flags:                         `packages/biometric_cipher/darwin/Classes/Managers/AuthenticationManager.swift`
- iOS-specific plugin entry:                    `packages/biometric_cipher/ios/`
- Cross-platform crypto + Argon2:               `lib/utils/cryptography_utils.dart`
- Password wrap (truncation bug):               `lib/security/models/password_cipher_func.dart:16`
- Storage I/O (no iOS-specific protection):     `lib/storage/encrypted_storage_impl.dart` (`_restrictFilePermissionsIfSupported`)

---

## 5. Open questions for the next session

- Does the wallet host app mark the vault file with `NSURLIsExcludedFromBackupKey`? If not, Vector C is wide open by default.
- Does the wallet set a stricter file protection class (`NSFileProtectionComplete`) on the vault? Or rely on the default?
- Confirm the app's `keychain-access-groups` entitlement. If it adds extra groups (for sharing with an extension or sibling app), enumerate them — those are the Vector A′ pivots.
- Are there embedded SDKs in the wallet (Sentry, Firebase, AppsFlyer, etc.)? Each is a Vector A′ supply-chain risk because they run with full app entitlements.
- Does the app perform any jailbreak detection? If not, Vector D is unmitigated.
- Test if `evaluatedPolicyDomainState` cached in `UserDefaults` (`SecureEnclaveManager.swift` enrollment tracking) ends up in iCloud Backup. If yes, that's a small information leak; not a key compromise.
