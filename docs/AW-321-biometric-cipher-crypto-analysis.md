# AW-321 — Cryptographic analysis of `packages/biometric_cipher`

**Ticket:** [AW-321](https://jira.int.agrd.dev/browse/AW-321) — *"Реализовать версию для iOS/macOS с комбинацией
асимметричной и симметричной криптографией используя Secure Enclave"*
**Ticket UPD:** *"Целесообразно ли продолжать работу по этой ветке?"*
**Comment (k.abdurakhmanova, 2025-07-30):** *"Изучить целесообразность этого подхода"*
**Status:** To Do · P4: Low · created 2024-12-03 · 1 pull request, **DECLINED**
**Analysed revision:** `feature/AW-321-ios-crypto` @ `521b728` (identical to `master` — the branch contains no AW-321 work)
**Date:** 2026-08-26

---

## 1. Executive summary

### 1.1 The short answer to the ticket

**The objective of AW-321 is already implemented.** The iOS/macOS backend does not use "pure" asymmetric
cryptography that the ticket implicitly assumes; it uses `SecKeyCreateEncryptedData` with the algorithm
`.eciesEncryptionCofactorX963SHA256AESGCM`
([`SecureEnclaveManager.swift:147,167`](../packages/biometric_cipher/darwin/Classes/Managers/SecureEnclaveManager.swift)).

ECIES *is* the combination of asymmetric and symmetric cryptography the ticket asks for. Per Apple's own
`SecKey.h`:

> Encryption is done using AES-GCM with key negotiated by
> `kSecKeyAlgorithmECDHKeyExchangeCofactorX963SHA256`. AES Key size is 128bit for EC keys <=256bit […].
> Ephemeral public key data is used as sharedInfo for KDF. AES-GCM uses 16 bytes long TAG and all-zero
> 16 byte long IV.

So each `encrypt()` already performs: ephemeral P-256 keypair → cofactor ECDH against the Secure Enclave
static public key → ANSI X9.63 KDF/SHA-256 → **AES-128-GCM** over the payload. Asymmetric key agreement plus
symmetric bulk encryption, with the private half never leaving the Secure Enclave.

**Recommendation: close AW-321 as "already implemented / obsolete as written."** Do not resurrect the declined
branch. There is, however, a narrow and genuinely valuable *residual* scope hiding inside the ticket — see
§7.3 — which is better tracked as a new, precisely-scoped ticket.

### 1.2 What the analysis did turn up

The interesting problems are not on Darwin. Ranked by severity:

| # | Severity | Platform | Finding |
|---|----------|----------|---------|
| F-1 | **High** | Windows | AES key is derived by bare `SHA-256(WindowsHello signature)` over a *static* string; the key materialises in process memory and is deterministic forever |
| F-2 | **High** | Windows | Entire scheme silently depends on Windows Hello `RequestSignAsync` being **deterministic**. Undocumented assumption; if violated, all vaults become permanently undecryptable |
| F-3 | **Medium** | Android | AES key size is never set → Android Keystore default of **128 bits** is used to wrap a **256-bit** master key |
| F-4 | **Medium** | Android | `getTPMStatus()` is hardcoded to `SUPPORTED` — no check that the key is actually hardware-backed |
| F-5 | **Medium** | Android | `minSdk = 23` but `generateKey` needs API 28; `setIsStrongBoxBacked` is called unconditionally → `NoSuchMethodError` on API 23–27 |
| F-6 | **Medium** | Windows | Key invalidation semantics are much weaker than iOS/Android — re-enrolling a fingerprint does **not** invalidate the credential |
| F-7 | **Medium** | Darwin | `isSecureEnclaveSupported()` generates a throwaway Secure Enclave key on **every** `encrypt`/`decrypt`/`generateKey`/`deleteKey` call |
| F-8 | **Low-Med** | Darwin | Uses the variant Apple explicitly labels *"Legacy […] use `…VariableIV…` in new code"* |
| F-9 | **Low-Med** | Darwin | Enrollment-change detection is stored in `UserDefaults` — attacker-writable, and lost on app data reset |
| F-10 | **Low-Med** | Android | Device-credential fallback path at key generation is unreachable/inconsistent with the `BIOMETRIC_STRONG`-only prompt |
| F-11 | **Low** | Windows | `AllowSetForegroundWindow(ASFW_ANY)` + a `WH_CBT` hook is installed around every Hello call |
| F-12 | **Low** | Cross | Payload is base64-encoded before encryption (+33%), and on Windows additionally widened to UTF-16LE (×2) |
| F-13 | **Low** | Dart | `encrypt()` does not check `_configured` while `decrypt()` does |
| F-14 | **Low** | Windows | No AAD bound into AES-GCM; tag/context not authenticated |

The single most important structural conclusion: **the three platforms do not implement the same security
model.** iOS/macOS is the strongest, Android is close behind, and Windows is substantially weaker in a way
that is not documented anywhere in the repo.

---

## 2. Scope and method

**In scope:** `packages/biometric_cipher/` (Dart API, Darwin/Swift, Android/Kotlin, Windows/C++), plus the
consuming layer in `lib/security/` and `lib/storage/` needed to establish the threat model.

**Method:** static reading of all cryptographic paths, cross-checked against the Apple `Security.framework`
headers shipped with the locally installed SDK
(`MacOSX26.5.sdk/…/Security.framework/Headers/SecKey.h`), the Android Keystore contract, and the WinRT
`Windows.Security.Credentials` / `Windows.Security.Cryptography` contracts.

**Not done:** no code was executed, no device testing, no fuzzing, no side-channel work. Findings whose
confirmation requires a device are marked **[needs device verification]**.

---

## 3. The shared contract

### 3.1 What the biometric cipher actually protects

This matters for judging the design, and it is easy to get wrong. The biometric cipher is **not** used for
bulk data encryption. It is a **key-wrapping** primitive.

`lib/storage/encrypted_storage_impl.dart:165`:

```dart
final encryptedMasterKey = await newWrapFunc.encrypt(masterKey);
```

The vault has one AES-256 master key (`CryptographyUtils.aesKeySizeBits = 256`). That master key is wrapped
once per enrolled factor and stored in `WrappedKey.wraps` as a list of `KeyWrap { origin, encryptedKey }`
(`lib/storage/models/data/key_wrap.dart`). `Origin.pwd` is wrapped with Argon2id-derived AES-256-GCM;
`Origin.bio` is wrapped by this plugin.

**Consequences for the analysis:**

- The plaintext is always ~32 bytes (44 bytes after the Dart-side base64). Per-message asymmetric overhead is
  irrelevant; the ECIES ephemeral public key (65 bytes) roughly triples a tiny payload, which does not matter.
- The *strength of the biometric unlock path is capped by the strength of the wrap*. Wrapping a 256-bit master
  key with a 128-bit key means the biometric path offers 128-bit security (F-3, and inherently on Darwin).
- Password unlock remains available and is unaffected. Biometric compromise is a **convenience-path**
  compromise, not a total vault compromise — but it does yield the master key, so it *is* a full data
  compromise for anyone who gets it.

### 3.2 Common data flow

```
Uint8List (32-byte master key)
  │  lib/security/biometric_cipher_provider.dart — base64Encode
  ▼
String (44 chars, ASCII)
  │  MethodChannel "biometric_cipher" → encrypt(tag, data)
  ▼
┌─────────────────┬──────────────────────┬───────────────────────────────┐
│ iOS / macOS     │ Android              │ Windows                       │
│ ECIES over SE   │ Keystore AES-GCM     │ Hello sign → SHA256 → AES-GCM │
└─────────────────┴──────────────────────┴───────────────────────────────┘
  │  base64 String back over the channel
  ▼
base64Decode → Uint8List → stored in KeyWrap.encryptedKey (re-base64'd into JSON)
```

Note the double base64 (F-12): the Dart layer base64-encodes before handing to native, and `KeyWrap.toJson`
base64-encodes the ciphertext again for JSON storage. The first one is pure overhead — every backend accepts
and returns strings, so the plugin's channel contract forces it. A `Uint8List` channel type would remove it.

### 3.3 Uniform surface

All three backends expose: `configure`, `getTPMStatus`, `getBiometryStatus`, `generateKey`, `encrypt`,
`decrypt`, `deleteKey`, `isKeyValid`. Errors are normalised to `BiometricCipherExceptionCode` and then to
`BiometricExceptionType` in `lib/security/biometric_cipher_provider.dart`. The abstraction is clean; the
problem is that identical-looking calls have materially different security properties underneath.

---

## 4. Platform deep dive

### 4.1 iOS / macOS — Secure Enclave ECIES

**Files:** `darwin/Classes/Managers/SecureEnclaveManager.swift`,
`darwin/Classes/Managers/AuthenticationManager.swift`, `darwin/Classes/Services/KeychainService.swift`

#### Key generation (`SecureEnclaveManager.swift:59–107`)

```swift
kSecAttrKeyType:       kSecAttrKeyTypeECSECPrimeRandom
kSecAttrKeySizeInBits: 256                              // P-256 — the only size the SE supports
kSecAttrTokenID:       kSecAttrTokenIDSecureEnclave
kSecAttrIsPermanent:   true
kSecAttrApplicationTag: "com.adguard.tpm.secureEnclavePrivateKey.<tag>"
kSecAttrAccessControl: <see below>
```

Access control (`AuthenticationManager.swift:31–57`):

```swift
protection: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
flags:      [.privateKeyUsage, .biometryCurrentSet]        // or .userPresence if no biometry
```

**This is the correct configuration and the strongest of the three platforms.**

- `.biometryCurrentSet` — the key is destroyed by the OS the moment the biometric enrollment set changes.
  Adding a fingerprint or re-enrolling Face ID permanently invalidates the key. This is exactly the property
  you want, and it is enforced by the OS, not by application code.
- `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — never leaves the device, never restored from backup.
- The private key is generated inside and never leaves the Secure Enclave. The app only ever holds a `SecKey`
  *reference*.

#### Encryption (`SecureEnclaveManager.swift:132–158`)

```swift
let publicKey = SecKeyCopyPublicKey(privateKey)
let algorithm: SecKeyAlgorithm = .eciesEncryptionCofactorX963SHA256AESGCM
SecKeyCreateEncryptedData(publicKey, algorithm, data)
```

**Encryption requires no biometric prompt.** Retrieving a `SecKey` reference from the keychain does not
trigger the access-control policy — only *using the private key* does. `SecKeyCopyPublicKey` derives the
public half from that reference. So encryption is a pure public-key operation.

This is a genuinely good property and it is the whole point of a hybrid design: you can re-wrap the master key
(e.g. on password change) without prompting the user. Android and Windows cannot do this — see §5.

#### Decryption (`SecureEnclaveManager.swift:160–208`)

`SecKeyCreateDecryptedData` triggers the Secure Enclave, which enforces `.biometryCurrentSet` and shows the
system Face ID / Touch ID prompt. The error handling here is careful and well-considered — it distinguishes
user cancellation, permanent invalidation, and authentication failure, and it has a documented fallback for
keys predating enrollment tracking.

#### Findings

**F-8 — Legacy ECIES variant [Low-Medium].** `SecKey.h` for this exact constant says:

> **Legacy** ECIES encryption or decryption, use
> `kSecKeyAlgorithmECIESEncryptionCofactorVariableIVX963SHA256AESGCM` in new code.

The difference is the IV. The legacy variant uses an **all-zero 16-byte IV**; the modern variant derives a
random 16-byte IV as the second half of the KDF output.

*Is the all-zero IV a vulnerability here?* **No, not as used.** GCM nonce reuse is catastrophic only when the
same (key, nonce) pair encrypts different plaintexts. Here the AES key is derived from a *fresh ephemeral*
ECDH keypair on every call, so every message has a unique key and the constant IV is harmless. This is why
Apple shipped it at all.

*Should it still be changed?* Yes, on principle — Apple deprecated it, it is one refactor away from being
dangerous if anyone ever caches the derived key, and the modern variant additionally binds the shared secret
as authenticated data. But it is a hygiene fix, not an incident. It is also **format-breaking**: existing
`KeyWrap` blobs would not decrypt. Any migration needs a version byte (see §7.4).

**AES-128, not AES-256 [inherent constraint, worth documenting].** Because the Secure Enclave only supports
256-bit ECC, `SecKey.h`'s "128bit for EC keys <=256bit" rule means ECIES on the Secure Enclave *always* gives
AES-128-GCM. There is no parameter to change this. So the biometric wrap of the AES-256 master key is
protected by a 128-bit symmetric key. 128-bit is not broken and is not an urgent problem, but it is a real
asymmetry between the password path (AES-256) and the biometric path (AES-128) that is documented nowhere.
Escaping it requires abandoning `SecKeyCreateEncryptedData` for a manual ECDH — which is the one legitimate
residual scope in AW-321 (§7.3).

**F-7 — Throwaway Secure Enclave keygen on every operation [Medium].**
`BiometricCipherPlugin.swift` calls `isSecureEnclaveSupported()` at lines 131, 185, 219, 270 — i.e. as a guard
on `generateKey`, `deleteKey`, `encrypt`, and `decrypt`. And `isSecureEnclaveSupported()`
(`SecureEnclaveManager.swift:33–56`) implements the probe by **actually generating a real P-256 key in the
Secure Enclave** (with `kSecAttrIsPermanent: false`) and checking it is non-nil.

Every single crypto call therefore burns a Secure Enclave key generation plus an `LAContext.canEvaluatePolicy`
round-trip. Secure Enclave keygen is on the order of tens of milliseconds. **[needs device verification]** for
exact cost, but the pattern is clearly wrong regardless: the answer is a device capability that cannot change
during a process lifetime. Cache it in a `lazy var` or a one-shot `Bool?`.

**F-9 — Enrollment state in `UserDefaults` [Low-Medium].** `saveEnrollmentState` /`hasEnrollmentChanged`
(`SecureEnclaveManager.swift:275–299`) persist `LAContext.evaluatedPolicyDomainState` into `UserDefaults`
keyed by `com.adguard.tpm.enrollmentState.<base64 tag>`.

The intent is documented and legitimate — the comment at `isKeyValid` explains that on macOS an invalidated
Secure Enclave key can linger in the keychain as `errSecInteractionNotAllowed`, indistinguishable from a valid
one. So this is a real workaround for a real platform wart.

But `UserDefaults` is the wrong store for a security signal:
- It is a plist in the app container — not protected, and modifiable by anything with container access
  (trivially so on a jailbroken device or an unsandboxed macOS build).
- Clearing app data resets it, after which `hasEnrollmentChanged` returns `false` for a key that *was*
  invalidated, and `isKeyValid` reports `true` incorrectly.
- Deleting the entry is a downgrade: an attacker who can write the current domain state suppresses the
  invalidation signal.

The impact is bounded — the Secure Enclave itself still refuses to decrypt with an invalidated key, so this
can only cause a *wrong error message*, not an actual bypass. Still, the keychain (with
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`) is the right home for it.

Note also that `evaluatedPolicyDomainState` is documented by Apple as opaque and *not* guaranteed to change
only on enrollment changes; Apple explicitly warns against relying on it for security decisions. As a
best-effort UX signal it is fine, which is what it is used for here.

---

### 4.2 Android — Keystore symmetric AES-GCM

**Files:** `android/…/repositories/SecureRepositoryImpl.kt`, `…/services/SecureServiceImpl.kt`,
`…/repositories/AuthenticationRepositoryImpl.kt`

#### Design

Purely symmetric. An AES-GCM key is generated in the AndroidKeyStore, StrongBox-backed where available, gated
on `setUserAuthenticationRequired(true)` with a **zero** auth timeout — meaning fresh biometric authentication
for every single operation. The `Cipher` is passed into `BiometricPrompt.CryptoObject`, so the Keystore only
releases the operation after the biometric succeeds. This is the canonical Android pattern and it is
implemented correctly.

Ciphertext layout: `base64( IV(12) ‖ ciphertext ‖ GCM tag(16) )`, with the IV generated by the Keystore
(`setRandomizedEncryptionRequired(true)` forbids caller-supplied IVs). Correct.

#### Findings

**F-3 — AES key size defaults to 128 bits [Medium].**

`SecureRepositoryImpl.kt:34`:

```kotlin
val keyGenerator = KeyGenerator.getInstance(
    KeyProperties.KEY_ALGORITHM_AES, SecureObjects.ANDROID_KEYSTORE
)
```

`setKeySize()` is never called anywhere in the package (verified by grep). The AndroidKeyStore AES generator
defaults to **128 bits**. So, exactly as on Darwin but here entirely avoidable, a 256-bit master key is wrapped
under a 128-bit key.

*Fix:* `keyGenParameterSpecBuilder.setKeySize(256)`. One line. Format-compatible for new keys (AES-GCM
ciphertext layout is unchanged), but existing keys keep their 128-bit size — so it needs either a re-enrollment
prompt or acceptance that old installs stay at 128. Given biometrics can be re-enrolled cheaply (the master key
is recoverable from the password wrap), forcing re-enrollment is viable.

**F-4 — `getTPMStatus()` is a stub [Medium].**

`SecureServiceImpl.kt:13`:

```kotlin
override fun getTPMStatus(): TPMStatus = TPMStatus.SUPPORTED
```

Android unconditionally claims hardware-backed key storage. It is then used as a gate in `checkCryptoStatus()`
(line 65) and, higher up, in `MFALocker.setupBiometry` (`lib/locker/mfa_locker.dart:347`) which refuses to
enable biometrics unless `tpmStatus == supported`. On Android that gate is vacuous.

This matters: AndroidKeyStore keys are **not guaranteed** to be hardware-backed. On devices without a TEE, or
with a broken/emulated keymaster, keys can be software-backed — the master key wrap would then be protected by
a key sitting in the same memory the app runs in, while the app reports "TPM supported" to the user.

*Fix:* query the actual security level.
- API 23+: `KeyFactory.getKeySpec(key, KeyInfo::class.java).isInsideSecureHardware`
- API 31+: `KeyInfo.getSecurityLevel()` → distinguishes `SECURITY_LEVEL_STRONGBOX` /
  `SECURITY_LEVEL_TRUSTED_ENVIRONMENT` / `SECURITY_LEVEL_SOFTWARE`

Map StrongBox/TEE → `SUPPORTED`, software → `UNSUPPORTED`. This is the Android analogue of what Darwin's
`isSecureEnclaveSupported()` and Windows' `GetWindowsTpmVersion()` already do honestly.

**F-5 — minSdk 23 vs API 28 requirement [Medium].**

`android/build.gradle` sets `minSdk = 23`. But `generateKey` is annotated `@RequiresApi(Build.VERSION_CODES.P)`
(API 28) — and `@RequiresApi` is a **lint annotation with no runtime effect**. At `SecureRepositoryImpl.kt:44`:

```kotlin
keyGenParameterSpecBuilder.setIsStrongBoxBacked(isStrongBoxAvailable())
```

`setIsStrongBoxBacked` was added in API 28. `isStrongBoxAvailable()` correctly returns `false` below API 28 —
but the *setter itself* is still invoked unconditionally, so on API 23–27 this throws `NoSuchMethodError` at
runtime. Nothing in `SecureServiceImpl.generateKey` or the plugin gates on API level.

*Fix:* wrap the call in `if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P)`, and either raise the plugin's
`minSdk` to 28 or make `getTPMStatus()` report unsupported below 28 (which F-4's fix would do naturally, since
`KeyInfo` is available from 23 but StrongBox is not).

**[needs device verification]** — the actual exception type may differ by ART version, but the missing-method
condition is unambiguous from the API levels.

**F-10 — Unreachable device-credential fallback [Low-Medium].**

`SecureRepositoryImpl.kt:47–56` chooses the authenticator type at key-generation time:

```kotlin
if (biometricManager.canAuthenticate(BIOMETRIC_STRONG) == BIOMETRIC_SUCCESS) {
    ...setUserAuthenticationParameters(0, AUTH_BIOMETRIC_STRONG)
} else {
    ...setUserAuthenticationParameters(0, AUTH_DEVICE_CREDENTIAL)
}
```

But two things make the `else` branch dead-or-broken:

1. `SecureServiceImpl.checkCryptoStatus()` (line 64) requires
   `authenticateService.getBiometryStatus() == BiometricStatus.SUPPORTED` before `generateKey` is even reached
   — and that status is derived from the same `canAuthenticate(BIOMETRIC_STRONG)`. So the `else` branch is
   essentially unreachable.
2. If it *were* reached, the key would require `AUTH_DEVICE_CREDENTIAL`, but the prompt in
   `AuthenticationRepositoryImpl.kt` hardcodes `.setAllowedAuthenticators(BIOMETRIC_STRONG)` — a mismatch that
   would fail at `CryptoObject` authentication time.

Either remove the dead branch or implement device-credential support end-to-end. Leaving it is a trap for the
next maintainer.

**Legacy API path, API < 30 [Low, flagged for review].** `SecureRepositoryImpl.kt:57–60` uses
`setUserAuthenticationValidityDurationSeconds(0)` on API < 30. The documented contract for that method is that
**`-1`** means "authentication required for every use"; `0` is a zero-second validity window. On current AOSP
this is normalised into `setUserAuthenticationParameters(0, AUTH_BIOMETRIC_STRONG or AUTH_DEVICE_CREDENTIAL)`,
which behaves as auth-per-use — but on older platform versions the value routed into the timeout-based branch
with a 0-second window instead. **[needs device verification on API 28–29]**. Passing `-1` is the documented,
unambiguous way to express the intent and costs nothing.

**`isKeyValid` correctness [Low].** `SecureRepositoryImpl.kt:150–164` catches only
`KeyPermanentlyInvalidatedException`; any other exception from `Cipher.init` propagates to the caller. The Dart
side (`BioCipherFunc._checkKeyValidity`) does catch broadly and maps to `KeyValidityStatus.unknown`, so the
blast radius is contained — but the native contract is "returns Boolean" and it can throw.

---

### 4.3 Windows — Hello signature as key material

**Files:** `windows/biometric_cipher_service.cpp`, `windows/winrt_encrypt_repository_impl.cpp`,
`windows/windows_hello_repository_impl.cpp`, `windows/windows_tpm_repository_impl.cpp`

#### Design

This is the outlier and it deserves the most attention.

```
configData.dataToSign               // static string, default "locker_authentication_request"
  → UTF-16LE bytes
  → KeyCredential.RequestSignAsync(...)          // Windows Hello prompt; TPM-backed RSA key
  → signature (IBuffer)
  → SHA-256(signature)                           // 32 bytes
  → SymmetricKeyAlgorithmProvider(AesGcm).CreateSymmetricKey(hash)
  → EncryptAndAuthenticate(key, UTF16LE(plaintext), random 12-byte nonce, /*AAD*/ nullptr)
  → base64( nonce(12) ‖ ciphertext ‖ tag(16) )
```

The default `dataToSign` comes from `lib/security/models/biometric_config.dart`:

```dart
final windowsDataToSign = windowsAuthData ?? 'locker_authentication_request';
```

#### F-2 — Undocumented dependency on signature determinism [High]

The entire scheme only works if `RequestSignAsync` returns **byte-identical output for identical input,
forever**. Nothing in the code, the comments, or the docs states this requirement.

It happens to hold today because Windows Hello's `KeyCredentialManager` uses RSA with PKCS#1 v1.5 padding,
which is deterministic. But this is an implementation detail of the platform, not a contract Microsoft
guarantees. If Windows ever migrates those credentials to RSA-PSS or ECDSA — both of which are randomised, both
of which are what a modern platform would move to — then `SHA-256(signature)` yields a different AES key on
every call and **every existing vault becomes permanently undecryptable via the biometric path.**

The data is not lost (the password wrap still works), but every Windows user's biometric enrollment silently
breaks, with no migration path and no way to detect it in advance.

This is the strongest argument in the whole analysis for *some* work in this area — just not the work AW-321
describes.

*Mitigations, cheapest first:*
1. **Document the assumption** loudly in the code and in `SECURITY.md`. Zero cost, immediate value.
2. **Store a verifier.** On enrollment, persist `SHA-256(derived_key ‖ salt)` alongside the wrap. On unlock,
   re-derive and compare before attempting decryption — turns a silent, confusing failure into a clear
   "biometric enrollment must be redone" state.
3. **Stop deriving the key from the signature.** Use Hello as *authentication* only, and hold the actual wrap
   key in DPAPI-NG / CNG with a TPM-bound, Hello-gated key. Larger change; see §7.3.

#### F-1 — Bare SHA-256 as a KDF, over a static input [High]

`winrt_encrypt_repository_impl.cpp:20–29`:

```cpp
auto sha256Hash = sha256Provider.HashData(signature);
auto aesKey = aesProvider.CreateSymmetricKey(sha256Hash);
```

Several distinct problems:

- **No KDF.** A raw hash is not a key-derivation function. There is no salt, no `info`/context string, no
  domain separation, no iteration. HKDF-SHA256 (`Windows.Security.Cryptography.Core` offers
  `KeyDerivationAlgorithmNames.Sp800108CtrHmacSha256`) is the right primitive and is available on the platform.
- **Static input → static key.** `dataToSign` is a fixed constant, so for a given credential the derived AES key
  is the same on every single operation, for the lifetime of the enrollment. It is a long-lived static key
  wearing a costume.
- **The key exists in the app's address space.** Unlike Darwin (private key never leaves the Secure Enclave) and
  Android (key never leaves the Keystore; only a `Cipher` handle crosses the boundary), on Windows the raw
  32-byte AES key is materialised in user-mode memory as a `CryptographicKey`. Anything that can read the
  process — a debugger, a memory-scraping malware sample, a crash dump uploaded to a symbol server — recovers
  a key that decrypts the vault **forever**, with no biometric prompt ever again.
- **No key rotation possible.** Because the key is a pure function of (credential, static string), you cannot
  rotate it without deleting and re-creating the Hello credential.

The TPM check in `GetTPMStatusAsync` (`biometric_cipher_service.cpp:19–43`) is honest about the TPM's presence,
but is **decorative with respect to the encryption**: the Hello credential may be TPM-backed, yet the AES key
that actually protects the master key is derived in software and lives in RAM. A user reading "TPM: supported"
would reasonably infer a hardware guarantee that does not extend to the data.

**Net assessment:** the Windows backend provides *authentication* (you must pass Hello to get the key the first
time in a process) but much weaker *key protection* than the other two platforms. The security boundary is the
process, not the TPM.

#### F-6 — Weak invalidation semantics [Medium]

`WindowsHelloRepositoryImpl::IsKeyValidAsync` (line 123) returns `true` whenever the credential opens
successfully. Windows Hello `KeyCredential`s are **not** invalidated when the user enrolls a new fingerprint or
face. Contrast:

| Platform | New biometric enrolled → key invalidated? |
|---|---|
| iOS / macOS | **Yes** — enforced by the OS via `.biometryCurrentSet` |
| Android | **Yes** — enforced by Keystore via `setUserAuthenticationRequired` + `AUTH_BIOMETRIC_STRONG` |
| Windows | **No** |

Additionally, Windows Hello treats a **PIN** as a first-class Hello credential. On a machine configured with
Hello PIN, `RequestSignAsync` is satisfied by typing the PIN — no biometric involved. So on Windows, "biometric
unlock" may in practice be "PIN unlock", which is a materially different threat model from Face ID / a
fingerprint, and the API surface gives the calling app no way to tell.

This should at minimum be documented in `SECURITY.md`, which currently says only that "biometric authentication
delegates to platform-specific secure enclaves (TPM/Secure Enclave)" — accurate for Darwin and Android,
misleading for Windows.

#### F-11 — Foreground-window manipulation [Low]

`windows_hello_repository_impl.cpp:57–70, 81–93, 105–117` — every Hello call is wrapped in:

```cpp
AllowSetForegroundWindow(ASFW_ANY);
HHOOK hook = SetWindowsHookEx(WH_CBT, [](...) {
    if (nCode == HCBT_ACTIVATE || nCode == HCBT_CREATEWND) AllowSetForegroundWindow(ASFW_ANY);
    return CallNextHookEx(nullptr, nCode, wParam, lParam);
}, nullptr, GetCurrentThreadId());
```

This is a UX workaround to stop the Hello dialog appearing behind the Flutter window — an understandable and
common hack. Two concerns:

- `ASFW_ANY` grants foreground-setting rights to **any** process, not just the Hello broker, for the duration.
  `AllowSetForegroundWindow(GetCurrentProcessId())` or targeting the specific broker PID would be tighter.
- The hook is thread-local (`GetCurrentThreadId()`), so the blast radius is small, but it is unhooked only on
  the success path — if `RequestSignAsync` throws, `UnhookWindowsHookEx` is skipped and the hook leaks. An RAII
  guard would fix both the leak and the readability.

The three copies of this block should be factored into one helper.

#### F-12 / F-14 — Encoding and AAD [Low]

- `ConvertStringToBinary(data, BinaryStringEncoding::Utf16LE)` doubles the plaintext size. Since the Dart layer
  always sends base64 (ASCII), this is pure waste — and it makes Windows ciphertexts structurally incompatible
  with the other platforms' UTF-8 handling. Harmless today (blobs never cross devices), fragile if that ever
  changes.
- `EncryptAndAuthenticate(key, dataToEncrypt, nonce, nullptr)` passes no additional authenticated data. Binding
  the `tag` and a format version into the AAD would prevent cross-tag ciphertext substitution and give a clean
  hook for the versioned-format migration in §7.4.

#### Minor

- `EncryptAsync` throws `"Data to sign is empty"` (`biometric_cipher_service.cpp:78`) when the real condition is
  "plugin not configured". Copy-paste error; misleading in logs.
- `windows_tpm_repository_impl.cpp:41` reconstructs a `std::wstring` from `cbPlatformType / sizeof(wchar_t)`
  bytes, which may include the trailing NUL in the string; `ParsePlatformType`'s `find` still works, so it is
  cosmetic.
- `catch (const std::exception)` (line 46) catches by value without binding a name — works, but should be
  `catch (const std::exception&)`.

---

## 5. Cross-platform comparison

| Property | iOS / macOS | Android | Windows |
|---|---|---|---|
| **Scheme** | ECIES: ephemeral ECDH P-256 → X9.63-KDF-SHA256 → AES-GCM | AES-GCM in AndroidKeyStore | Hello RSA signature → SHA-256 → AES-GCM |
| **Asymmetric + symmetric?** | **Yes** | No (symmetric only) | Partly (signature is asymmetric; wrap key is symmetric) |
| **Symmetric strength** | AES-128 *(forced by P-256 SE)* | **AES-128** *(default; should be 256)* | AES-256 |
| **Where the key lives** | Secure Enclave, never extractable | TEE/StrongBox, never extractable | **Process memory** |
| **Encrypt needs biometrics?** | **No** (public-key op) | Yes | Yes |
| **Decrypt needs biometrics?** | Yes | Yes | Yes (or Hello PIN) |
| **Per-op auth enforced by** | Secure Enclave | Keystore + `CryptoObject` | Application logic |
| **Invalidated on re-enrollment** | **Yes** (`.biometryCurrentSet`) | **Yes** | **No** |
| **PIN accepted as "biometric"** | No | No (`BIOMETRIC_STRONG` only) | **Yes** |
| **Hardware backing verified** | Yes (real SE probe) | **No** (hardcoded `SUPPORTED`) | TPM checked, but unrelated to the wrap key |
| **IV / nonce** | All-zero, safe (per-message ephemeral key) | Keystore-generated random 12B | Random 12B |
| **AAD bound** | Ephemeral pubkey (by the algorithm) | No | No |
| **Key rotation possible** | Yes (delete + regenerate) | Yes | Only by deleting the Hello credential |

**The single most important row is "Encrypt needs biometrics?"** — and it is the row that most directly answers
AW-321. On Darwin, the hybrid design lets the app re-wrap the master key without any user interaction, because
encryption only needs the public key. Android and Windows must prompt for a biometric just to *store* something.
That asymmetry is not a bug on Darwin; it is the payoff of the design the ticket was asking for, already banked.

---

## 6. What is done well

Worth recording, because the report is otherwise a list of problems:

- **Layering.** The repository/service/manager split is consistent across all three native platforms, and the
  Dart platform-interface boundary is clean. Errors are normalised through a single mapping
  (`biometric_cipher_provider.dart`) rather than leaking platform codes upward.
- **Key wrapping over direct encryption.** Wrapping one master key per factor, rather than encrypting data with
  the biometric key directly, is the right architecture. It keeps payloads tiny, makes factors independent, and
  makes teardown/rotation cheap.
- **Darwin error handling.** The `decrypt` path (`SecureEnclaveManager.swift:160–208`) carefully distinguishes
  cancellation, permanent invalidation, and auth failure, and handles keys created before enrollment tracking
  existed. That is real, hard-won operational detail.
- **The `BioCipherFunc` fallback** (`lib/security/models/bio_cipher_func.dart:40–58`) — re-checking key validity
  when a platform reports a generic failure instead of `keyInvalidated` — is a pragmatic answer to genuinely
  inconsistent platform behaviour, and it is commented as such.
- **Android's `CryptoObject` usage** is the textbook-correct pattern: the Keystore, not the app, decides whether
  the biometric succeeded.
- **Test coverage exists at the native level** — `SecureEnclaveManagerTests.swift` (603 lines),
  `biometric_cipher_service_test.cpp` (358), `AuthenticationRepositoryTest.kt` (252), plus instrumented and
  integration tests. That is unusually good for a Flutter plugin.

---

## 7. Verdict on AW-321

### 7.1 Should the ticket be pursued as written?

**No.** Three independent reasons:

1. **It is already done.** `.eciesEncryptionCofactorX963SHA256AESGCM` *is* asymmetric + symmetric cryptography
   on the Secure Enclave. Apple's own header describes it as ECDH key agreement feeding AES-GCM. Implementing
   "a version with a combination of asymmetric and symmetric cryptography" would produce what already ships.

2. **The premise appears to be outdated.** The ticket was filed 2024-12-03 with a P4 priority and a due date of
   2025-05-30 that has long passed. Its PR was **declined**. The `feature/AW-321-ios-crypto` branch has
   **zero commits** relative to `master`. Meanwhile the Darwin implementation has been substantially reworked
   since — enrollment tracking, `isKeyValid`, macOS-specific handling, `keyInvalidated` states — all landed
   through other tickets (AW-2526, AW-2662, AW-3071). The ticket is a fossil of a design question that the
   codebase answered by other means.

3. **Darwin is the healthiest of the three backends.** Spending the effort there has the lowest marginal return.
   The two High-severity findings in this report are both on Windows; the actionable Medium ones are mostly on
   Android. Re-opening AW-321 would direct work at the platform that needs it least.

### 7.2 Is the underlying instinct wrong?

No — and this is worth saying plainly, because the ticket's author was pointing at something real. A hybrid
asymmetric/symmetric design *is* the right shape for this problem, for a specific reason: **it lets you encrypt
without authenticating.** Only the public half is needed to wrap a new master key, so re-wrapping on password
change, key rotation, or vault migration needs no biometric prompt. Android and Windows both prompt on
`encrypt` today, which is a worse user experience and forces a Face ID / Hello dialog into flows that
conceptually do not need one.

So the correct reading of AW-321 is not "bring hybrid crypto to iOS" — it is **"the hybrid model iOS already
has is the one the other platforms should adopt."** That is a genuinely useful conclusion, and it inverts the
ticket.

### 7.3 The residual scope worth keeping

Two things inside the ticket's orbit are real and are *not* covered by the current implementation:

**(a) AES-256 wrapping on Darwin via manual ECDH.** As established in §4.1, `SecKeyCreateEncryptedData` on a
P-256 Secure Enclave key can only ever give AES-128. If a 256-bit biometric wrap is wanted (to match the
password path), the only route is to stop using the convenience API and do it by hand:

```
SecKeyCopyKeyExchangeResult(privateKey,
    .ecdhKeyExchangeCofactorX963SHA256, ephemeralPublicKey, params)
  → shared secret
  → HKDF-SHA256(secret, salt, info: "locker.bio.v2" ‖ tag)
  → AES-256-GCM(random 96-bit nonce, AAD = version ‖ tag)
```

This is more code and more responsibility (you now own the nonce and the KDF), and it should only be done if
the 128-vs-256 asymmetry is judged to matter. **My assessment: it does not currently justify the risk.**
AES-128 is not a practical weakness, and hand-rolled crypto trades a well-audited Apple implementation for one
that must be reviewed from scratch. Record the asymmetry in the docs and revisit only if a compliance
requirement forces it.

**(b) Windows key protection.** This is the one that should actually be built. Replace
`SHA-256(Hello signature)` with a wrap key that never leaves hardware — a CNG/DPAPI-NG key in the Microsoft
Platform Crypto Provider, gated on Hello, using Hello for *authentication* rather than as *key material*. That
eliminates F-1 and F-2 together and brings Windows in line with the other two platforms' "key never enters the
process" property.

Neither of these is "implement iOS/macOS with hybrid crypto". Both deserve their own tickets with their own
acceptance criteria.

### 7.4 If a format change does happen

Any of the changes that alter ciphertext layout — the `VariableIV` migration (F-8), manual ECDH (§7.3a), the
Windows rework (§7.3b), Android's `setKeySize(256)` — breaks existing `KeyWrap` blobs. Do this once, not four
times:

- Prefix ciphertexts with a **version byte**, and dispatch on it in `decrypt`.
- On successful unlock with an old-format wrap, transparently re-wrap to the new format and persist. The master
  key is already in hand at that moment, so this needs no extra prompt.
- Keep old-format decryption for at least two release cycles.
- Because the password wrap is an independent recovery path, the worst case for a user who skips the migration
  window is "re-enroll biometrics", not "lose data".

---

## 8. Recommendations

Ordered by value-to-effort, not by severity.

### Immediate — documentation only, no code risk

| # | Action | Addresses |
|---|---|---|
| R-1 | Document in `SECURITY.md` that the three platforms have **different** security properties — specifically that on Windows the wrap key exists in process memory, that a Hello **PIN** satisfies "biometric", and that Windows credentials survive biometric re-enrollment | F-1, F-6 |
| R-2 | Add a code comment at `winrt_encrypt_repository_impl.cpp:20` stating the determinism requirement on `RequestSignAsync` explicitly, so nobody "modernises" it unaware | F-2 |
| R-3 | Document the AES-128 wrap (both Darwin-inherent and Android-accidental) against the AES-256 master key | F-3 |

### Short-term — small, contained fixes

| # | Action | Addresses |
|---|---|---|
| R-4 | `setKeySize(256)` on the Android key generator | F-3 |
| R-5 | Guard `setIsStrongBoxBacked` behind an API-28 check; raise plugin `minSdk` or gate `getTPMStatus` | F-5 |
| R-6 | Implement a real `getTPMStatus()` on Android via `KeyInfo.isInsideSecureHardware` / `getSecurityLevel()` | F-4 |
| R-7 | Cache `isSecureEnclaveSupported()` — it currently generates a Secure Enclave key on every crypto call | F-7 |
| R-8 | Move Darwin enrollment state from `UserDefaults` to the keychain (`…WhenUnlockedThisDeviceOnly`) | F-9 |
| R-9 | Remove or complete the Android device-credential branch | F-10 |
| R-10 | Use `-1` rather than `0` for `setUserAuthenticationValidityDurationSeconds` | Android API<30 |
| R-11 | RAII-wrap the Windows hook (currently leaks on exception) and factor the three copies into one helper; narrow `ASFW_ANY` | F-11 |
| R-12 | Check `_configured` in `BiometricCipher.encrypt` as `decrypt` already does | F-13 |
| R-13 | Add a Windows derived-key verifier (`SHA-256(key ‖ salt)`) so a determinism break surfaces as a clear error | F-2 |

### Medium-term — needs a ticket each

| # | Action | Addresses |
|---|---|---|
| R-14 | **Rework the Windows key protection** to a TPM-bound CNG/DPAPI-NG key gated on Hello, using Hello for authentication rather than key derivation | F-1, F-2 |
| R-15 | Introduce a **versioned ciphertext format** with AAD binding (version ‖ tag) across all platforms, plus transparent re-wrap on unlock | F-8, F-14, enables everything above |
| R-16 | Migrate Darwin to `.eciesEncryptionCofactorVariableIVX963SHA256AESGCM`, riding on R-15 | F-8 |
| R-17 | Evaluate bringing the "encrypt without prompting" property to Android (a Keystore EC key + ECDH, mirroring the Darwin model) — this is the useful inversion of AW-321 | §7.2 |

### Ticket disposition

- **AW-321 → close** as *already implemented / obsolete*, citing §7.1. Link this document.
- **Open new:** "Windows biometric wrap key must not live in process memory" — P2, carries F-1 and F-2.
- **Open new:** "Android: hardware-backing verification and AES-256 wrap key" — P3, carries F-3, F-4, F-5.
- **Open new:** "Versioned biometric ciphertext format" — P3, prerequisite for R-16.
- Route R-7, R-8, R-11, R-12 through ordinary maintenance.

---

## 9. Open questions for the team

1. **Is the 128-bit biometric wrap acceptable?** It is not a practical weakness, but if any compliance regime
   requires 256-bit throughout, that changes the calculus on §7.3(a) considerably.
2. **Is Windows a first-class target for this library, or best-effort?** The answer determines whether R-14 is
   a P2 or a "document and accept". The declined AW-321 PR and the P4 priority suggest the latter, but
   `AW-3071 fix mfa locker windows` in recent history suggests Windows is being actively maintained.
3. **What does `feature/AW-3216-poc-keychain-bio` conclude?** That branch (in-window biometrics on macOS via
   `LocalAuthenticationView`, plus `resetAuthorizedContext` across layers) touches the same Darwin subsystem and
   its findings — particularly the *"SE-key/Xcode wall"* noted in commit `3407f48` — likely bear directly on any
   further Darwin work. It was not analysed here.
4. **Is there an appetite for a format migration at all?** Several recommendations queue behind R-15. If the
   answer is no, the list collapses to documentation plus the Android one-liners.

---

## Appendix A — Primary sources

- Apple `Security.framework` `SecKey.h`, from
  `/Applications/Xcode.app/…/MacOSX26.5.sdk/System/Library/Frameworks/Security.framework/Headers/SecKey.h`,
  lines 1152–1157 (legacy variant) and 1205–1210 (`VariableIV` variant). Quoted verbatim in §1.1 and §4.1.
- `packages/biometric_cipher/darwin/Classes/Managers/SecureEnclaveManager.swift`
- `packages/biometric_cipher/darwin/Classes/Managers/AuthenticationManager.swift`
- `packages/biometric_cipher/android/src/main/kotlin/com/adguard/cryptowallet/biometric_cipher/repositories/SecureRepositoryImpl.kt`
- `packages/biometric_cipher/android/src/main/kotlin/com/adguard/cryptowallet/biometric_cipher/services/SecureServiceImpl.kt`
- `packages/biometric_cipher/windows/winrt_encrypt_repository_impl.cpp`
- `packages/biometric_cipher/windows/windows_hello_repository_impl.cpp`
- `packages/biometric_cipher/windows/biometric_cipher_service.cpp`
- `lib/security/biometric_cipher_provider.dart`, `lib/security/models/bio_cipher_func.dart`,
  `lib/security/models/biometric_config.dart`
- `lib/storage/encrypted_storage_impl.dart`, `lib/storage/models/data/key_wrap.dart`

## Appendix B — Confidence notes

Everything in §4 and §5 is derived from reading the source and the platform headers. The following would
benefit from confirmation on real hardware before being acted on:

- **F-5** — the exact failure mode on API 23–27 (`NoSuchMethodError` vs. a verifier-time failure).
- **F-7** — the measured cost per Secure Enclave keygen, to size the win from caching.
- **Android API < 30 timeout semantics** — whether `0` behaves as auth-per-use on API 28–29 in practice.
- **F-2** — whether current Windows builds still return deterministic signatures across reboots and Hello
  re-authentication, which is the assumption the whole Windows backend rests on.
