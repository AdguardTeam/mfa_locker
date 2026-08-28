# AW-321 — Can Android and Windows adopt the Darwin hybrid model?

**Ticket:** [AW-321](https://jira.int.agrd.dev/browse/AW-321)
**Companion to:** [`AW-321-biometric-cipher-crypto-analysis.md`](AW-321-biometric-cipher-crypto-analysis.md) — this note answers
the question that report's §7.2 raises: *"the hybrid model iOS already has is the one the other platforms should adopt"*
**Analysed revision:** `feature/AW-321-ios-crypto` @ `5a9481a`
**Date:** 2026-08-28

---

## 1. Short answer

**Yes — on both platforms, but they sit at very different distances from it.**

The thing to copy from iOS is not ECDH specifically. It is the *property* that ECIES delivers:

```
enroll    →  keypair born in hardware; public half readable by anyone
encrypt   →  public key only            → no prompt, no hardware round-trip
decrypt   →  private key, in hardware   → biometric gate enforced by the OS / TPM
```

- **Android** has first-class, documented APIs for this. Two routes; the recommended one needs no new crypto code.
- **Windows** has exactly one way to get both halves (prompt-free encrypt *and* a hardware-enforced Hello gate), and it
  runs through an undocumented key storage provider. There is a multi-year existence proof for it.

## 2. What both platforms lack today

Android and Windows both prompt on `encrypt()`:

- Android — `SecureServiceImpl.kt:33` passes the encrypt `Cipher` through `authenticateService.authenticateUser`
  because the AES key is `setUserAuthenticationRequired(true)` with a zero timeout.
- Windows — the AES key *is* `SHA-256(Hello signature)`, so obtaining it for encryption requires a signature, which
  requires a Hello gesture.

The crypto analysis (§5, row *"Encrypt needs biometrics?"*) identifies prompt-free encryption as the actual payoff of
the Darwin design: re-wrapping the master key on password change, key rotation or vault migration needs no user
interaction. Everything below is about giving Android and Windows that shape.

## 3. Android — clean, two routes

| | Route A · mirror iOS (ECDH) | Route B · RSA-OAEP wrap **(recommended)** |
|---|---|---|
| Key | EC P-256 in AndroidKeyStore, `PURPOSE_AGREE_KEY` | RSA-2048 in AndroidKeyStore, `PURPOSE_DECRYPT` (+ `PURPOSE_ENCRYPT`) |
| Min API | 31 (`PURPOSE_AGREE_KEY`) | 23; 28 for StrongBox — identical to today's constraint |
| Encrypt | `keyStore.getCertificate(alias).publicKey` → software ephemeral P-256 → ECDH → HKDF-SHA256 → AES-256-GCM, random 12-byte nonce, AAD = `version ‖ Qₑ` | `keyStore.getCertificate(alias).publicKey` → `RSA/ECB/OAEPWithSHA-256AndMGF1Padding` directly over the 32-byte master key (OAEP-2048/SHA-256 carries ≤ 190 B) |
| Decrypt gate | `BiometricPrompt.CryptoObject(KeyAgreement)` — listed in the framework reference; exposed by androidx only from **1.4.0-alpha06 (2026-03-25)**. Plugin is on `biometric-ktx:1.2.0-alpha05`. On API 31–34 fall back to a short time-bound auth window (`setUserAuthenticationParameters(n > 0, AUTH_BIOMETRIC_STRONG)`) | `BiometricPrompt.CryptoObject(Cipher)` — the exact pattern the plugin uses today, on every supported API level |
| Hand-rolled crypto in app | KDF + AES-GCM (same as Darwin, where those steps also run in-process) | **None** — every operation is inside the Keystore / StrongBox |
| Fixes from the analysis | F-3 (256-bit strength), prompt-free encrypt | F-3, prompt-free encrypt |
| Gotcha | Per-op binding for `KeyAgreement` is very new | AndroidKeyStore OAEP uses **MGF1-SHA1** by default; the software-provider encrypt must pass a matching `OAEPParameterSpec("SHA-256", "MGF1", MGF1ParameterSpec.SHA1, PSource.PSpecified.DEFAULT)` or decrypt fails |

Below API 31 (Route A) or on devices without hardware RSA (none in practice — StrongBox mandates RSA-2048), keep the
current symmetric path.

### Why Route B

- Same security model as Darwin: public-key encrypt without auth; private key never leaves hardware; per-operation
  biometric binding through `CryptoObject`; `setInvalidatedByBiometricEnrollment` (default `true`) behaves exactly
  as for the AES key today.
- Zero new cryptographic code. No KDF, no nonce, no AEAD to own. OAEP is randomised, so two wraps of the same key
  differ.
- Works on the androidx dependency already declared.
- If a payload ever exceeds 190 bytes, Route B becomes a KEM — RSA-OAEP wraps a random AES-256 key, AES-GCM wraps the
  payload — and is then literally the hybrid construction. The master key is 32 bytes, so today it does not need to be.

Route A is only worth its extra surface if byte-level parity with Darwin is a goal in itself.

### Route B sketch

```kotlin
// enrol — once
KeyPairGenerator.getInstance(KEY_ALGORITHM_RSA, "AndroidKeyStore").apply {
    initialize(
        KeyGenParameterSpec.Builder(alias, PURPOSE_DECRYPT or PURPOSE_ENCRYPT)
            .setKeySize(2048)
            .setDigests(DIGEST_SHA256)
            .setEncryptionPaddings(ENCRYPTION_PADDING_RSA_OAEP)
            .setIsStrongBoxBacked(strongBoxAvailable)
            .setUserAuthenticationRequired(true)
            .setUserAuthenticationParameters(0, AUTH_BIOMETRIC_STRONG)
            .build(),
    )
}.generateKeyPair()

// encrypt — no prompt
val pub = keyStore.getCertificate(alias).publicKey
val cipher = Cipher.getInstance("RSA/ECB/OAEPWithSHA-256AndMGF1Padding").apply {
    init(ENCRYPT_MODE, pub, OAEPParameterSpec("SHA-256", "MGF1", MGF1ParameterSpec.SHA1, PSource.PSpecified.DEFAULT))
}
val blob = byteArrayOf(VERSION_RSA_OAEP) + cipher.doFinal(masterKey)

// decrypt — prompt, bound to this operation
val priv = (keyStore.getEntry(alias, null) as KeyStore.PrivateKeyEntry).privateKey
val cipher = Cipher.getInstance("RSA/ECB/OAEPWithSHA-256AndMGF1Padding").apply { init(DECRYPT_MODE, priv) }
val authed = authenticateService.authenticateUser(cipher)   // BiometricPrompt.CryptoObject(cipher), as today
val masterKey = authed.doFinal(blob.copyOfRange(1, blob.size))
```

## 4. Windows — possible, with one wall in the way

**The wall.** `Windows.Security.Credentials.KeyCredential` — the API the plugin uses — exposes `RequestSignAsync`,
`RetrievePublicKey` and `GetAttestationAsync`. **There is no decrypt operation.** That is *why* the current code hashes
a signature into an AES key: at this API layer there is nothing else to build on. A sign-only key cannot give
prompt-free encryption, because the encryptor has no public operation whose result the key holder can reproduce.

| | Route W1 · Hello key via CNG **(recommended, unsupported)** | Route W2 · TPM key + Hello as yes/no (documented, weaker) |
|---|---|---|
| Key | RSA-2048 via `NCryptCreatePersistedKey` on **`"Microsoft Passport Key Storage Provider"`** (the NGC KSP behind Windows Hello) | RSA-2048 or ECDH-P256 on `MS_PLATFORM_CRYPTO_PROVIDER` — the provider `windows_tpm_repository_impl.cpp` already opens for the TPM version check |
| Encrypt | `NCryptOpenKey(…, NCRYPT_SILENT_FLAG)` + `NCryptEncrypt(…, NCRYPT_PAD_OAEP_FLAG)` — **no prompt** | `NCryptEncrypt` with the public key — no prompt |
| Decrypt gate | Set `NCRYPT_NGC_CACHE_TYPE_PROPERTY = NCRYPT_NGC_CACHE_TYPE_PROPERTY_AUTH_MANDATORY_FLAG` and `NCRYPT_PIN_CACHE_IS_GESTURE_REQUIRED_PROPERTY = 1` on the key → the NGC KSP / TPM demands a Hello gesture before `NCryptDecrypt`. **Enforced by the OS, not by the app** | `UserConsentVerifier.RequestVerificationAsync` in app code, then `NCryptDecrypt`. The TPM key itself is not Hello-gated: same-user malware can decrypt without a prompt |
| Fixes from the analysis | F-1, F-2 (private key never in process memory; no dependency on signature determinism), F-11 (`NCRYPT_WINDOW_HANDLE_PROPERTY` replaces the `AllowSetForegroundWindow` + `WH_CBT` hook), custom prompt text via `NCRYPT_USE_CONTEXT_PROPERTY` | F-1, F-2 |
| Invalidation | Tied to the Hello container: PIN reset / container reset invalidates; re-enrolling a fingerprint does not (same as today, F-6 unchanged) | Tied to the TPM key only; Hello changes are irrelevant to it |
| Risk | **Undocumented.** The property constants are in `ncrypt.h`; the behaviour is not in the docs. A Microsoft Q&A on exactly this usage (2024-10) went unanswered. Existence proof: **KeePassWinHello** has shipped precisely this design for years (367 ★, persistent-key mode) | Gate is software — a regression versus today on the "silent decrypt by a same-user process" threat |

### Why Route W1, with eyes open

W1 is the only route on Windows that gets both halves — prompt-free encrypt *and* a hardware-enforced biometric gate —
and it brings Windows to the same "key never enters the process" property the other two platforms have. The risk is
that it is unsupported. Two mitigations make it acceptable:

- The password wrap is an independent recovery path. If a Windows update ever breaks the NGC key, the blast radius is
  *"re-enrol biometrics"*, not data loss — the same failure mode the current design already carries via F-2.
- The plugin already calls `isAlgorithmSupported`-style probes before every operation on Darwin; the same pattern
  (`NCryptOpenKey` succeeds, `NCryptGetProperty(NgcCacheType)` returns the mandatory flag) turns a silent break into a
  typed error at the boundary.

Two corrections to the KeePassWinHello reference implementation:

1. Use `NCRYPT_PAD_OAEP_FLAG` with SHA-256, not their `NCRYPT_PAD_PKCS1_FLAG`. The spike must confirm the NGC KSP
   accepts OAEP.
2. Set `NCRYPT_KEY_USAGE_PROPERTY` to decrypt only, and verify on open that `NCRYPT_ALLOW_EXPORT_FLAG` is absent —
   KeePassWinHello does this integrity check and it is worth copying.

Note that literal ECIES is not available on this route — Hello keys are RSA-2048 — so Windows would be RSA-KEM. That
is fine; the property is what matters, not the curve.

### Route W1 sketch

```cpp
// enrol — once; prompts (key creation is a Hello operation)
NCryptOpenStorageProvider(&prov, L"Microsoft Passport Key Storage Provider", 0);
NCryptCreatePersistedKey(prov, &key, BCRYPT_RSA_ALGORITHM, name, 0, 0);
DWORD len = 2048;                       NCryptSetProperty(key, NCRYPT_LENGTH_PROPERTY, (PBYTE)&len, sizeof len, 0);
DWORD usage = NCRYPT_ALLOW_DECRYPT_FLAG; NCryptSetProperty(key, NCRYPT_KEY_USAGE_PROPERTY, (PBYTE)&usage, sizeof usage, 0);
DWORD cache = NCRYPT_NGC_CACHE_TYPE_PROPERTY_AUTH_MANDATORY_FLAG;
                                        NCryptSetProperty(key, NCRYPT_NGC_CACHE_TYPE_PROPERTY, (PBYTE)&cache, sizeof cache, 0);
NCryptSetProperty(key, NCRYPT_WINDOW_HANDLE_PROPERTY, (PBYTE)&hwnd, sizeof hwnd, 0);
NCryptFinalizeKey(key, 0);

// encrypt — no prompt
NCryptOpenKey(prov, &key, name, 0, NCRYPT_SILENT_FLAG);
BCRYPT_OAEP_PADDING_INFO oaep{ BCRYPT_SHA256_ALGORITHM, nullptr, 0 };
NCryptEncrypt(key, plain, plainLen, &oaep, out, outLen, &written, NCRYPT_PAD_OAEP_FLAG);

// decrypt — Hello gesture enforced by the KSP
NCryptOpenKey(prov, &key, name, 0, 0);
DWORD gesture = 1;                      NCryptSetProperty(key, NCRYPT_PIN_CACHE_IS_GESTURE_REQUIRED_PROPERTY, (PBYTE)&gesture, sizeof gesture, 0);
NCryptSetProperty(key, NCRYPT_USE_CONTEXT_PROPERTY, (PBYTE)message, bytes, 0);   // prompt text
NCryptDecrypt(key, blob, blobLen, &oaep, out, outLen, &written, NCRYPT_PAD_OAEP_FLAG);
```

## 5. Cross-platform shape

| Property | Darwin (unchanged) | Android · Route B | Windows · Route W1 |
|---|---|---|---|
| Scheme | ECIES (ephemeral ECDH → X9.63 → AES-128-GCM) | RSA-2048-OAEP-SHA256 over the master key | RSA-2048-OAEP-SHA256 over the master key |
| Encrypt needs biometrics | No | **No** | **No** |
| Decrypt needs biometrics | Yes | Yes | Yes |
| Per-op auth enforced by | Secure Enclave | Keystore + `CryptoObject` | NGC KSP / TPM |
| Private key location | Secure Enclave | TEE / StrongBox | TPM (via NGC) |
| Wrap-key material in process | Never | Never | **Never** (today: always) |
| Documented API | Yes | Yes | **No** |

One Dart contract: **`encrypt()` never prompts, `decrypt()` always prompts.** One blob format:
`version(1) ‖ KEM output ‖ …`, dispatched on the version byte in `decrypt`, with a transparent re-wrap to the new format
on the next successful unlock — the §7.4 migration from the crypto analysis, done once for everything instead of once
per platform. Darwin stays exactly as it is.

## 6. Before committing — three spikes, about a day each

1. **Android Route B.** RSA-OAEP Keystore key with per-op auth and `CryptoObject(Cipher)` decrypt on an API 28 device
   and on a StrongBox device. Confirm the OAEP / MGF1 parameter round-trip between the software encrypt and the
   Keystore decrypt. Measure StrongBox RSA-2048 decrypt latency (expected: hundreds of ms — one op per unlock, so
   acceptable, but it should be a number, not a guess).
2. **Android Route A — only if parity is wanted.** Pin the exact framework API level of
   `BiometricPrompt.CryptoObject(KeyAgreement)`: it is present in the API 35/36 reference, but the API-35 diff lists
   only `CryptoObject(long operationHandle)`, so the level that introduced the typed constructor is unconfirmed. Trial
   `androidx.biometric:1.4.0-alpha06`.
3. **Windows Route W1.** NGC-KSP key: create → silent encrypt → gated decrypt with `NCRYPT_PAD_OAEP_FLAG`. Then exercise
   sign-out / sign-in, Hello PIN reset, fingerprint re-enrolment, container reset and a feature update, and record
   which of those invalidate the key. This spike decides between W1 and W2.

## 7. Disposition

- This is the residual scope the crypto analysis identified in §7.3(b), widened from "fix Windows key protection" to
  "give Android and Windows the Darwin property". It deserves **two tickets** — one per platform — each with the spike
  above as its first task and the §5 contract as its acceptance criterion.
- It is not AW-321 as written. AW-321 should still be closed as "already implemented on Darwin" per the crypto
  analysis §7.1; these tickets are its successors, not its continuation.

---

## Appendix — Sources

- Android `KeyProperties.PURPOSE_AGREE_KEY` (API 31):
  <https://learn.microsoft.com/en-us/dotnet/api/android.security.keystore.keyproperties.purposeagreekey?view=net-android-34.0>
- Android `BiometricPrompt.CryptoObject` — supported operations incl. `KeyAgreement` and `long operationHandle`:
  <https://learn.microsoft.com/en-us/dotnet/api/android.hardware.biometrics.biometricprompt.cryptoobject?view=net-android-35.0>
- Android API 35 diff for `BiometricPrompt.CryptoObject` (adds `CryptoObject(long)` / `getOperationHandle()` only):
  <https://developer.android.com/sdk/api_diff/35/changes/android.hardware.biometrics.BiometricPrompt.CryptoObject>
- androidx.biometric release notes — `KeyAgreement` support in 1.4.0-alpha06 (2026-03-25):
  <https://developer.android.com/jetpack/androidx/releases/biometric>
- `Windows.Security.Credentials.KeyCredential` — sign / public-key / attestation only:
  <https://learn.microsoft.com/en-us/uwp/api/windows.security.credentials.keycredential?view=winrt-22621>
- KeePassWinHello `WinHelloProvider.cs` — the NGC-KSP encrypt/decrypt reference implementation:
  <https://github.com/sirAndros/KeePassWinHello/blob/master/src/AuthProviders/WinHelloProvider.cs>
- Microsoft Q&A, *"Undocumented usage of nCrypt API for Microsoft Passport Key Storage Provider"* (unanswered):
  <https://learn.microsoft.com/en-us/answers/questions/2100684/undocumented-usage-of-ncrypt-api-for-microsoft-pas>
- Local sources: `packages/biometric_cipher/android/…/SecureRepositoryImpl.kt`, `…/SecureServiceImpl.kt`,
  `packages/biometric_cipher/windows/winrt_encrypt_repository_impl.cpp`, `…/windows_hello_repository_impl.cpp`,
  `…/windows_tpm_repository_impl.cpp`, `packages/biometric_cipher/android/build.gradle` (`compileSdk 36`, `minSdk 23`,
  `biometric-ktx:1.2.0-alpha05`).
