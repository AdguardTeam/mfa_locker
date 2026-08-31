# TPM Support POC for `biometric_cipher` — Design

Date: 2026-08-31
Status: Approved (user-approved design, pre-implementation)
Scope: Proof of concept. New functionality must work on Windows when exercised from `packages/biometric_cipher/example`. Cross-platform parity, publishing, and production hardening are out of scope.

## Goal

Add TPM support to the `biometric_cipher` plugin so that the following functions are available and demonstrable from the plugin's example app on Windows:

1. Detect TPM presence and version
2. Create and delete keys within the TPM
3. Retrieve a full list of available TPM keys
4. Encrypt and decrypt data using TPM keys (Base64 wire format)
5. Universal function: string → check TPM presence + version → create key if missing → encrypt → Base64
6. Reverse function: Base64 → check TPM version → error if key missing → decrypt → string

## Current State (analysis findings)

The Windows plugin already implements most primitives across three layers
(C++ service → method channel → Dart API):

| Function | Status | Location |
|---|---|---|
| TPM presence + version >= 2 gate | Exists | `WindowsTpmRepositoryImpl::GetWindowsTpmVersion()` parses `TPM-Version:x.y` from `NCRYPT_PCP_PLATFORM_TYPE_PROPERTY`; `getTPMStatus()` returns a `TPMStatus` enum. The actual version number is computed but discarded |
| Key create/delete | Exists | `generateKey(tag)` / `deleteKey(tag)` — TPM-backed Windows Hello credentials (`KeyCredentialManager`) |
| Encrypt/decrypt → Base64 | Exists | `encrypt` / `decrypt` — Windows Hello signs challenge, SHA-256 → AES key → AES-GCM; output is Base64 |
| Key validity | Exists | `isKeyValid(tag)` |
| Full key list | Missing | No `NCryptEnumKeys` usage anywhere in git history (verified via `git log -S` across all commits); it was never implemented or removed |
| Universal functions | Missing | The pieces exist, but callers must orchestrate them manually (see `example/lib/tpm_screen.dart`) |

Important constraint: `encrypt`/`decrypt` require `configure()` to have been
called first (the native layer needs `windowsDataToSign` to derive the AES key).
The example app already calls `configure` in `initState`,
so this requirement is satisfied by the demo harness and will be documented on
the new API.

## Key-Listing Feasibility (answered)

**Partially feasible.** `NCryptEnumKeys` over the Microsoft Platform Crypto
Provider enumerates all TPM-resident keys for the current user. This is a real,
complete list and we will implement it. Caveats that are inherent to the
Windows API:

- The list includes keys created by Windows itself and by other applications;
  there is no per-app ownership metadata.
- Windows Hello–created keys appear under system-generated opaque container
  names — not the tags passed to `generateKey` — so list entries cannot be
  mapped back to this plugin's tags.
- The enumeration covers only the Platform Crypto Provider (TPM-backed keys),
  not software-stored keys from other providers.

Conclusion: a truthful "full list of TPM keys" is possible but is diagnostic in
nature. That is acceptable for this POC.

## Design

### 1. Native C++ layer (`packages/biometric_cipher/windows`)

- `NCryptWrapper` (`include/biometric_cipher/wrappers/ncrypt_wrapper.h`):
  add `EnumKeys(...)` wrapping `NCryptEnumKeys` — caller loops until
  `NTE_NO_MORE_ITEMS`, using `NCryptFreeBuffer` for cleanup. Follows the
  existing wrapper pattern (`OpenStorageProvider`, `GetProperty`) so tests can
  mock it.
- `WindowsTpmRepository` / `WindowsTpmRepositoryImpl`:
  - No change needed for version detection: `GetWindowsTpmVersion()` already exists and returns the parsed major version as `int`. Today only `BiometricCipherService` folds it into the `TPMStatus` enum; the new `GetTPMVersionAsync()` returns the raw value instead
  - `ListTpmKeys()` — new method: enumerate via `NCryptEnumKeys`; return `std::vector<KeyInfo>` (key name + algorithm identifier)
- `BiometricCipherService`:
  - `GetTPMVersionAsync()` → `int`
  - `ListKeysAsync()` → list of key info
- `MethodName` enum: add `kGetTPMVersion`, `kListKeys`.
- `BiometricCipherPlugin::HandleMethodCall`: two new cases following the existing pattern — invoke service, `result->Success(...)`; on `hresult_error`, `result->Error(GetErrorCodeString(hr), message)`.
- `Error codes`: reuse existing `error_tpm_unsupported` / `error_tpm_version` HRESULTs for failure paths of the new methods.
- Tests: extend `mock_ncrypt_wrapper.h` and the existing
  `windows_tpm_repository_test.cpp` with `EnumKeys` / `GetWindowsTpmVersion`
  cases following the Arrange-Act-Assert pattern.

### 2. Dart plugin layer (`packages/biometric_cipher/lib`)

New data model:

- `TpmKeyInfo` — `{ String name; String algorithm; }` (new file under
  `data/`, following one-type-per-file convention)

New platform interface + method channel methods:

- `getTPMVersion()` → `Future<int>` (channel: `getTPMVersion`)
- `listKeys()` → `Future<List<TpmKeyInfo>>` (channel: `listKeys`)

New `BiometricCipher` public API (orchestration over existing primitives,
implemented in `biometric_cipher.dart` with existing validation style):

- `getTpmVersion()` → `Future<int>` — delegates to platform interface
- `listKeys()` → `Future<List<TpmKeyInfo>>` — delegates to platform interface
- `encryptString({required String tag, required String data})` → `Future<String>`:
  1. `getTPMStatus()` — if not `TPMStatus.supported`, throw `BiometricCipherException(code: tpmUnsupported, …)`
  2. `isKeyValid(tag: tag)` — if `false`, `generateKey(tag: tag)`
  3. `encrypt(tag: tag, data: data)` → Base64 `String`
- `decryptString({required String tag, required String data})` → `Future<String>`:
  1. `getTPMStatus()` — if not `TPMStatus.supported`, throw `BiometricCipherException(code: tpmUnsupported, …)`
  2. `isKeyValid(tag: tag)` — if `false`, throw `BiometricCipherException(code: keyNotFound, …)` (spec: exit with an error when the key is missing — do NOT auto-create)
  3. `decrypt(tag: tag, data: data)` → `String`

Both universal functions reuse `encrypt`/`decrypt` and therefore require
`configure()` to have been called; this precondition is documented in their
doc comments.

### 3. Example app (`packages/biometric_cipher/example/lib/tpm_screen.dart`)

Extend the existing screen, following its current widget/handler style:

- "Check TPM version" button → displays the version number
- "List TPM keys" button → displays the count and the key names
- "Universal encrypt" button → takes the data text field, calls
  `encryptString`, displays the Base64 result
- "Universal decrypt" button → takes the Base64 result, calls
  `decryptString`, displays the recovered string

## Verification

- `fvm flutter analyze --fatal-warnings --fatal-infos --no-pub .` in `packages/biometric_cipher` (zero warnings, per repo AGENTS.md)
- `fvm flutter test` in `packages/biometric_cipher`
- Manual run of the example app on Windows; exercise all new buttons

## Out of Scope

- Android / iOS / macOS implementations of the new methods (they surface as missing-plugin errors there)
- Attributing listed TPM keys to this plugin's tags (infeasible; see feasibility section)
- Auto-configuring the plugin inside the universal functions
- Production hardening, versioning, publishing concerns
- Any changes to the root `locker` library or the `example/` demo app (`mfa_demo`)
