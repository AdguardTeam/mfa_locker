# mfa_locker — macOS attack-vector analysis

**Status:** working notes for a red-team exercise. Target: the macOS build of
`mfa_locker` as used by a crypto-wallet application.
**Date:** 2026-05-12
**Scope:** Decryption / tamper attacks against the on-disk vault, mounted from
a same-user attacker process. Local attacker assumed (no remote network angle,
no kernel privilege).

> Companion files: `windows-attack-vectors.md`, `ios-attack-vectors.md`,
> `android-attack-vectors.md`. Cross-platform crypto-layer vectors are
> summarized once in the Windows file; this file focuses on what's different.

---

## 1. Crypto / storage recap (macOS specifics)

- **Storage file:** plain JSON typically at `~/Library/Application Support/<bundle>/<name>.json`.
  `_restrictFilePermissionsIfSupported` runs `chmod 600` (`lib/storage/encrypted_storage_impl.dart:643`).
  `chmod 600` ⇒ only the owning Unix user can read — but on a single-user Mac (≈ all real-world Macs), *every other process running as that user* can also read.
- **Password wrap:** unchanged from Windows — Argon2id `m=19 MiB, p=1, t=2` + AES-256-GCM. Same weakness for a wallet threat model.
- **Biometric wrap (macOS):** **NOT** sign + SHA-256 like Windows. Uses Secure Enclave **ECIES** asymmetric encryption directly (`packages/biometric_cipher/darwin/Classes/Managers/SecureEnclaveManager.swift:131`):
  - Key: `kSecAttrKeyTypeECSECPrimeRandom` (P-256) generated in Secure Enclave via `kSecAttrTokenIDSecureEnclave`.
  - Algorithm: `.eciesEncryptionCofactorX963SHA256AESGCM` — uses a fresh ephemeral EC keypair per `SecKeyCreateEncryptedData`, so the wrap is **randomized**. Same input ⇒ different ciphertext each time.
  - Access control: `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` + `[.privateKeyUsage, .biometryCurrentSet]` (`AuthenticationManager.swift:36–41`). Falls back to `.userPresence` if biometry isn't enrolled.
  - `.biometryCurrentSet` ⇒ key is auto-invalidated when the user adds/changes a Touch ID fingerprint.
- **Predictable identifiers:**
  - Key tag stored in Keychain: `com.adguard.tpm.secureEnclavePrivateKey.<tag>` (`darwin/Classes/AppConstants.swift:8` + `SecureEnclaveManager.getTagData`).
  - Application `<tag>` defaults to `"biometric"` from the locker layer.
  - Keychain access group defaults to the app's Team ID + Bundle ID.

---

## 2. Attack vectors

### Vector A′ — Cross-process Secure Enclave key access  *(weaker than Windows but real)*

**Premise.** The macOS-side biometric wrap is randomized (ECIES), so the
"deterministic signature replay" of Vector A on Windows does not apply
verbatim. The analog on macOS is **using the SE key in place** rather than
reproducing it:

- Secure Enclave keys aren't extractable, but the *capability to call
  `SecKeyCreateDecryptedData`* is what matters. Whoever can satisfy the
  Keychain ACL on the private key can decrypt the wrap.
- On macOS, Keychain items default to scope = (Team ID, access group, app
  identity). A different process with the **same code signature / Team ID /
  keychain-access-groups entitlement** can access the same key.

**Realistic attack chain.**
1. **Same Team ID app:** if the publisher ships another app (or the wallet
   has plugins/helpers) sharing the team identifier and group, that sibling
   can `SecItemCopyMatching` the SE private key by tag and call
   `SecKeyCreateDecryptedData(wrapBytes)`. macOS will surface the LocalAuth
   biometric prompt — user authenticates → master key is decrypted by the
   attacker process.
2. **Unsigned / unhardened attacker without entitlements:** keychain ACLs
   block access if the SE key was created with a default ACL bound to the
   creating app's signature. *But:* legacy macOS keychain items created with
   only `kSecAttrAccessControl` (no `kSecAttrAccessGroup` specifically restricting
   sharing) can sometimes be enumerated by `security(1)` interactive prompts
   that ask the user to "Always Allow" — clickjack-able for unsophisticated
   users.
3. **TCC / Full Disk Access abuse:** if the attacker convinces the user to
   grant FDA (common for "system optimizer" malware), they can read raw
   keychain databases at `~/Library/Keychains/`. SE keys themselves remain in
   hardware, but the *metadata* (tags, attributes) plus the on-disk vault file
   is enough to script a same-Team-ID helper to do the actual decrypt call.

**Bottom line.** macOS prevents the *unsigned, untrusted, unrelated app*
replay that Windows allows. It does **not** prevent a sibling app from the same
publisher, a compromised auto-updater, a notarized "helper" tool, or anything
running with FDA. The defense rests entirely on **code-signing identity
isolation**.

**Inputs needed for a PoC:** macOS app signed with the wallet's Team ID (or
ad-hoc-signed for local testing on SIP-disabled systems), vault JSON path,
the key tag string.

---

### Vector B — Offline password brute force  *(cross-platform)*

Identical to Windows Vector B (`windows-attack-vectors.md §2 Vector B`):

- Salt is in the file; Argon2id params are constants in source.
- Argon2id `m=19 MiB / t=2` is OWASP floor — below wallet-tier norms.
- Non-ASCII passphrases are silently truncated to bytes via `password.codeUnits.toUint8List()` (`lib/security/models/password_cipher_func.dart:16`), collapsing entropy.

CPU-only Rust PoC reuses 100% of the Windows brute-forcer for this vector.

---

### Vector C — File substitution / wallet swap

`chmod 600` doesn't help against a same-user attacker. The user's own
processes can rewrite the file freely. Combined with Vector D below to obtain
the master key from a live wallet, the wallet-swap attack works identically
to Windows.

**macOS-specific twist:** `chflags uchg` (user-immutable flag) is **not**
applied — easy to bypass even if it were, but the absence of any FS-level
write protection means a launchd background helper installed via "Login
Items" can persistently rewrite the vault.

---

### Vector D — Live-process memory scrape

`task_for_pid` is the entry point. **Whether it succeeds depends entirely on
how the wallet binary is signed:**

| Wallet build flavor                                 | Attacker can read memory? |
|-----------------------------------------------------|----------------------------|
| Unsigned / ad-hoc signed (dev builds)               | Yes — `task_for_pid` succeeds for same-user.                                                                                                  |
| Signed without Hardened Runtime                     | Yes.                                                                                                                                          |
| Signed with Hardened Runtime, no `get-task-allow`   | No, unless attacker holds `com.apple.security.cs.debugger` entitlement signed by Apple. Effectively closed.                                   |
| Signed + Hardened Runtime + Library Validation      | Same as above. The strongest config.                                                                                                          |

**Action item for defenders:** verify the wallet release binary is built
with Hardened Runtime and **without** `com.apple.security.get-task-allow`.
Recent versions of Xcode default this correctly but a forgotten dev flag
flips it.

When `task_for_pid` succeeds:
- `mach_vm_region` + `mach_vm_read` to scan heap pages.
- Same residue concerns as Windows: Dart Strings, non-`Erasable` byte buffers,
  `_metaCache` entries.

---

### Vector E — Time Machine / iCloud backup exfil

By default `~/Library/Application Support/<bundle>/` **is backed up by Time
Machine** and is **not** excluded from iCloud Drive Desktop & Documents
sync (the path lives under the user's home).

- Time Machine writes the file to an attached external drive, often less
  protected than the Mac itself.
- An attacker with Time Machine read access (physical theft of backup disk;
  Time Capsule compromise; cloud backup service compromise) holds the
  encrypted vault → Vector B against it.
- The app does not currently call `setResourceValue(forKey: .isExcludedFromBackupKey)`
  or use `NSURLIsExcludedFromBackupKey` on the vault path.

This is the **single largest realistic exposure surface** for the macOS
build. A user who loses their Time Machine disk has effectively published
their encrypted vault.

---

### Vector F — Keychain database scraping

Even though the SE private key cannot be extracted, the encrypted vault file
plus the Keychain entry attributes tell an attacker:

- That a `biometric` SE-backed key exists for this app.
- The exact key tag string to use in a sibling-app PoC.
- The biometric enrollment state stored in `UserDefaults` under the
  `com.adguard.tpm.enrollmentState.*` prefix (`SecureEnclaveManager.swift:11`)
  — leaks whether biometrics has been re-enrolled since wrap was minted.

Low severity directly; useful for chaining with Vector A′.

---

### Vector G — App Sandbox status

If the wallet is *not* sandboxed (typical for non-MAS distribution), it
writes to `~/Library/Application Support/<bundle>/` directly — readable by
any same-user process. If it *is* App-Sandboxed (Mac App Store), it writes
to `~/Library/Containers/<bundle>/Data/Library/Application Support/<bundle>/`
— still readable by any same-user process with TCC consent for the user's
home; TCC does not protect this path from same-user code.

Sandboxing does **not** protect the on-disk vault from same-user attackers
on macOS, in contrast to iOS. It only protects against the wallet itself
escaping its own sandbox.

---

### Vector H — Login-keychain side door (legacy)

If the wallet's onboarding ever stored *any* secret in the login keychain
(passphrase, recovery seed, etc.) without `.biometryCurrentSet` + SE token,
that item is accessible via `security find-generic-password` with a single
user click on "Always Allow." Currently the locker library does not appear
to write to the login keychain — confirm this hasn't changed in app-level
code outside `packages/biometric_cipher/`.

---

## 3. Priority ranking for a Rust/Swift PoC tool

| Rank | Vector | Why                                                                                                       | Cost   |
|------|--------|-----------------------------------------------------------------------------------------------------------|--------|
| 1    | E + B  | Time Machine snapshot + offline Argon2id → no live attacker needed. Highest realistic blast radius.       | Low.   |
| 2    | C + D  | Wallet-swap once master key is in hand. Requires unhardened build for D.                                  | Medium.|
| 3    | A′     | Same-Team sibling attack against SE key. Demonstrates Keychain ACL boundary clearly.                      | Medium.|
| 4    | B (standalone) | Pure offline brute force when the attacker only has the file.                                     | Medium.|

The PoC tool would naturally be:
- A Swift CLI for Vector A′ (needs SE / Keychain APIs).
- A Rust tool for Vectors B / E (parses JSON, runs Argon2id, AES-GCM, validates).
- Both can share the JSON parser.

---

## 4. Pointers into the codebase

- Secure Enclave manager:            `packages/biometric_cipher/darwin/Classes/Managers/SecureEnclaveManager.swift`
- Keychain glue:                     `packages/biometric_cipher/darwin/Classes/Services/KeychainService.swift`
- ACL flags:                         `packages/biometric_cipher/darwin/Classes/Managers/AuthenticationManager.swift`
- Constants (predictable tag):       `packages/biometric_cipher/darwin/Classes/AppConstants.swift`
- Storage I/O (chmod 600 on macOS):  `lib/storage/encrypted_storage_impl.dart` (`_restrictFilePermissionsIfSupported`)
- Cross-platform crypto + Argon2:    `lib/utils/cryptography_utils.dart`
- Password wrap (byte truncation):   `lib/security/models/password_cipher_func.dart`

---

## 5. Open questions for the next session

- Confirm release-build configuration: Hardened Runtime on, `get-task-allow` off, Library Validation on. If yes, Vector D collapses for distributed users.
- Verify whether the app sets `NSURLIsExcludedFromBackupKey` on the vault path or `com.apple.metadata:com_apple_backup_excludeItem`. If no, file Time Machine exposure as a P1.
- Test cross-app Keychain access with two ad-hoc-signed test apps to confirm whether Team-ID grouping or per-app-signature ACLs are the actual barrier in the wallet's signing config.
- Check if the wallet sets a Keychain access group via `kSecAttrAccessGroup` anywhere — the current darwin code does not, leaving the default (app's primary group). Verify what that resolves to in production builds.
- Audit any helper / login-item / XPC service shipped with the wallet — those are the most likely Vector A′ pivots inside the same Team ID.
