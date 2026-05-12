# mfa_locker — Windows attack-vector analysis

**Status:** working notes for a red-team exercise. Target: the Windows build of
`mfa_locker` as used by a crypto-wallet application.
**Date:** 2026-05-12
**Scope:** Decryption / tamper attacks against the on-disk vault, mounted from a
same-user attacker process written in Rust. Local attacker assumed (no remote
network angle, no kernel privilege).

> The follow-up to this file is a Rust PoC tool. Each vector below lists the
> data the PoC needs and the Windows APIs it calls, so it can be turned into
> code with minimal further reading of the Flutter source.

---

## 1. Crypto / storage recap (Windows specifics)

- **Storage file:** plain JSON at `<app support dir>/<name>.json` (`example/lib/main.dart:30`).
  `_restrictFilePermissionsIfSupported` only chmods on macOS
  (`lib/storage/encrypted_storage_impl.dart:641`). On Windows the file inherits
  its parent directory ACL — readable by any process running as the same user.
- **File schema:** `salt`, `lockTimeout`, `masterKey` (a `WrappedKey` list of
  per-`Origin` `KeyWrap`s — `pwd`, `bio`), `entries` (encrypted meta+value),
  `hmacKey` (AES-GCM-encrypted), `hmacSignature`.
- **Password wrap:** AES-256-GCM, key = Argon2id(password, salt) with
  `m = 19 MiB`, `p = 1`, `t = 2`, output 32 bytes
  (`lib/utils/cryptography_utils.dart:25`). OWASP **floor** parameters — weak
  for a crypto-wallet threat model.
- **Biometric wrap (Windows):** AES-256-GCM, key = `SHA-256( RSA_sign(WindowsHello_priv, "<dataToSign>") )`.
  - `dataToSign` default: `"locker_authentication_request"`
    (`lib/security/models/biometric_config.dart:41`). Example app does not
    override it (`example/lib/di/factories/repository_factory.dart:46–53`).
  - `keyTag` default: `"biometric"` (`lib/security/security_provider.dart:25`).
  - Uses base `Windows.Security.Credentials.KeyCredentialManager`
    (`packages/biometric_cipher/windows/include/biometric_cipher/wrappers/windows_hello_wrapper_impl.h`).
    **Not** `RestrictedKeyCredentialManager`.
- **HMAC:** integrity over the file. HMAC key is itself wrapped with the master
  key, so HMAC = no additional brute-force friction.
- **Memory hygiene:** `ErasableByteArray` zeroes copies, but Dart `String`
  passwords are GC-managed and immortal until collected; intermediates from
  `package:cryptography` (`extractBytes`, `result.toUint8List()`) are not
  `Erasable`.

---

## 2. Attack vectors

### Vector A — Same-user biometric replay  *(headline)*

**Premise.** All ingredients to reproduce the biometric AES key sit outside the TPM:

1. `KeyCredentialManager` for unpackaged Win32 binds credentials to the **user**, not to the calling app identity. Any same-user process can `OpenAsync` the credential.
2. `KeyCredential.RequestSignAsync` uses **RSASSA-PKCS#1 v1.5** — deterministic. Same key + same input ⇒ same signature ⇒ same SHA-256 ⇒ same AES key.
3. `dataToSign` is the constant `"locker_authentication_request"`. `keyTag` is the constant `"biometric"`. Both readable from source / binary.
4. Vault file has no ACL hardening — attacker reads it freely.

**Attack chain (Rust PoC).**
1. Read the vault JSON. Parse out the `bio`-origin `KeyWrap.encryptedKey`.
2. `KeyCredentialManager::OpenAsync(L"biometric")` → `KeyCredential::RequestSignAsync( utf16le("locker_authentication_request") )`. Windows Hello UI pops; user authenticates (face / fingerprint / PIN). *Social-engineering surface — the only line of defence in the chain.*
3. `SHA-256(signature_buffer)` → 32-byte AES key.
4. AES-256-GCM decrypt the `bio` wrap. The `encryptedKey` bytes are formatted as `nonce(12) || cipher || tag(16)`. The wrap's bytes themselves are wrapped *again* by the WinRT layer at write time (`packages/biometric_cipher/windows/winrt_encrypt_repository_impl.cpp:33–52`) — same `nonce(12) || cipher || tag(16)` layout, base64'd. So the on-disk blob is one layer of base64 → one AES-GCM-decrypt with the derived key → plaintext master key.
5. Master key now decrypts entries, including the HMAC key for integrity proof.

**No password ever required. No crypto crack required.** The only thing in the chain that resists a Rust attacker is the Windows Hello UI prompt. The attacker controls process context, so prompt text can be plausible.

**Required APIs (`windows` crate):**
- `Windows::Security::Credentials::KeyCredentialManager::OpenAsync`
- `KeyCredential::RequestSignAsync`
- `Windows::Security::Cryptography::Core::HashAlgorithmProvider` + `SymmetricKeyAlgorithmProvider::AesGcm` (or `aes-gcm` + `sha2` crates directly).

**Inputs needed:** path to vault JSON, hardcoded `keyTag` and `dataToSign` strings.

---

### Vector B — Offline password brute force

For users without biometrics (or as a fallback path against the `pwd` wrap):

- Salt is in the file; Argon2id params are compiled-in constants.
- For each candidate: derive Argon2id key → AES-GCM decrypt the `pwd` wrap. GCM tag confirms a hit.
- Argon2id `m=19 MiB / t=2` ≈ 50–100 ms/attempt on CPU; memory-hard so GPU/ASIC gains are limited but real. **For a crypto wallet this is below industry norms** (`m ≥ 64 MiB` typical).
- `PasswordCipherFunc` widens the keyspace problem: `password.codeUnits.toUint8List()` (`lib/security/models/password_cipher_func.dart:16`) downcasts UTF-16 code units to bytes — non-ASCII chars ≥ U+0100 are truncated, collapsing entropy of non-ASCII passphrases.

**Required APIs:** `argon2` crate, `aes-gcm` crate. Pure CPU; embarrassingly parallel.

**Inputs needed:** vault JSON, password candidate list.

---

### Vector C — File substitution / wallet-swap  *(highest blast radius)*

No crypto at all. With same-user file write access:

1. Attacker pre-generates a vault JSON encrypted with a password they know, containing entries that look like the victim's wallet but with the deposit address swapped to the attacker.
2. Replace the victim's vault file (or wait for unlock window and overwrite). HMAC doesn't defend — HMAC key sits in the file and the attacker minted both.
3. User opens the wallet, unlocks with the attacker-set password? No — they don't know it. **But:**
   - Variant C1: Drop a vault with a *known weak* password and prompt the user to "set a new password" — relies on the app's onboarding code, not exploitable in steady state.
   - Variant C2 *(realistic):* Wait until user unlocks, swap **only the displayed deposit address** at the entry level — but encrypting a forged entry requires the master key, which we don't have without Vector A or B. So pure C is limited to substitution of the *whole* vault, which the user notices.

Honest assessment: pure file substitution is loud. C2 in combination with **Vector D** (live memory scrape of master key) is the practical wallet-swap — attacker reads master from RAM while unlocked, encrypts a forged entry against it, writes back, recomputes HMAC. The user keeps unlocking happily until the next outgoing send goes to the wrong address.

**Required APIs:** plain file I/O; combine with Vector D for the master key.

**Inputs needed:** vault path, master key (from D or A or B).

---

### Vector D — Live-process memory scrape

While the locker is unlocked:

- Master key lives in heap (in an `ErasableByteArray`), but several
  intermediates (`extractBytes` outputs, `result.toUint8List()` in `decrypt`,
  cached `EntryMeta` in `_metaCache`) are not erased.
- Dart `String` for the password is immortal until GC.
- Same-user attacker can `OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_INFORMATION)`
  without elevation and `ReadProcessMemory` page-by-page. AES-256 candidates are
  scannable (32-byte high-entropy blobs followed by AES round-key expansion
  shape, or recognized by trial-decrypt of one storage entry).

**Required APIs:** `OpenProcess`, `VirtualQueryEx`, `ReadProcessMemory` (windows crate or `winapi`).

**Inputs needed:** PID of the wallet (enumerate via `Toolhelp32Snapshot`), vault JSON (to validate candidate keys by trial-decrypt).

---

### Vector E — Exfil via backups / sync / AV cloud

Because the file lives in a normal user-writable location with no ACL
hardening, it is routinely picked up by Windows Backup, OneDrive, third-party
backup tools, AV cloud sample uploads, crash dumps. Widens the blast radius of
Vector B: an offline attacker who never had local code execution can still get
the file via a compromised cloud account.

**Required APIs:** none — this is an exposure observation, not a code path.

---

### Vector F — Wrap injection at onboarding

`addOrReplaceWrap` (`lib/storage/encrypted_storage_impl.dart:177`) replaces a
wrap when a valid existing wrap unlocks the master. An attacker with Vector A's
signature (i.e. once they have master key) can mint a new `pwd` wrap of a
master *they choose*, then rewrite the vault so future user writes encrypt
under the attacker-known master. Niche — really only matters if the attacker
wants to give the user back a "working" vault that the attacker can read
forever, even after key rotation.

---

### Vector G — Information leakage (low severity, completeness)

- `lockTimeout` and salt are in cleartext (by design) but file size and mtime
  reveal usage patterns.
- `_writeDataToFile` creates `stor_<uuid>.tmp` in the same directory before
  rename; on Windows the temp file may persist if the process is killed mid-
  write. Could leak older state snapshots.

---

## 3. Priority ranking for the Rust PoC

| Rank | Vector | Why                                                                                                       | Cost   |
|------|--------|-----------------------------------------------------------------------------------------------------------|--------|
| 1    | A      | Most novel; one Windows Hello prompt buys full vault. Demonstrates the design flaw cleanly.               | Low.   |
| 2    | C + D  | Wallet-swap is the worst real-world outcome for a wallet — silent, persistent, no decryption needed.      | Medium.|
| 3    | B      | Offline brute force for short / non-ASCII passwords; good as a CLI mode.                                  | Medium.|
| 4    | E,F,G  | Supporting context, not a standalone PoC.                                                                 | —      |

---

## 4. Pointers into the codebase

- Argon2 + AES-GCM helper:           `lib/utils/cryptography_utils.dart`
- Password wrap derivation:          `lib/security/models/password_cipher_func.dart`
- Biometric wrap (Dart side):        `lib/security/models/bio_cipher_func.dart`
- Biometric provider config & defaults: `lib/security/models/biometric_config.dart`, `lib/security/security_provider.dart`
- Storage I/O (no ACL on Windows):   `lib/storage/encrypted_storage_impl.dart` (esp. `_writeDataToFile`, `_restrictFilePermissionsIfSupported`)
- Windows Hello sign + AES-GCM glue: `packages/biometric_cipher/windows/biometric_cipher_service.cpp`
- Sign / SHA-256 / AES-GCM bytes:    `packages/biometric_cipher/windows/winrt_encrypt_repository_impl.cpp`
- KeyCredentialManager usage:        `packages/biometric_cipher/windows/include/biometric_cipher/wrappers/windows_hello_wrapper_impl.h`
- Example app wire-up:               `example/lib/main.dart`, `example/lib/di/factories/repository_factory.dart`

---

## 5. Open questions for the next session

- Confirm via `windows` crate experiment: does `KeyCredentialManager::OpenAsync(L"biometric")` from a different EXE owned by the same user actually succeed when the credential was created by the Flutter app? (Microsoft docs say yes for unpackaged Win32; verify against the build.)
- Confirm `RequestSignAsync` is RSA PKCS#1 v1.5 in current Windows builds — the KeyCredential API doesn't expose the algorithm choice. Empirically: signature length should be 256 bytes for a 2048-bit key, signing the same data twice should produce identical bytes. If non-deterministic in some configuration, Vector A degrades to "can sign, must capture during user auth" rather than "can replay later".
- Test whether OneDrive / "Known Folder Move" actually picks up the vault directory on a default install — if yes, Vector E is a one-click data exfil for any compromised Microsoft account.
- Confirm whether the user's chosen vector matches Vector A, C+D, or something else not on this list.
