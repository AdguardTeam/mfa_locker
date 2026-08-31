# TPM Raw Key Create/Delete Increment — Design

Date: 2026-08-31
Status: Approved (user-approved design, pre-implementation)
Scope: Increment to the TPM Support POC (`docs/superpowers/specs/2026-08-31-tpm-support-poc-design.md`). Same POC constraints apply: Windows only, exercised from `packages/biometric_cipher/example`, no changes to the root `locker` library or the `example/` demo app.

## Motivation

POC verification exposed a usability gap: the app can create/delete Windows Hello credentials (`generateKey`/`deleteKey`), but those live in the non-enumerable NGC store. The store that `listKeys` enumerates (user-scope CNG keys in the Microsoft Platform Crypto Provider) can be listed but not created or deleted from the app. This increment adds raw TPM key create/delete so the full lifecycle of the enumerated store is demonstrable in the example app.

Scope is create + delete only. Encrypt/decrypt stays on the Windows Hello path. Raw keys are never used for crypto in this POC.

## Design

### 1. Native C++ layer

- `include/biometric_cipher/common/memory_deallocation.h`: add `NCryptKeyHandleFree` — RAII wrapper for `NCRYPT_KEY_HANDLE` (closed with `NCryptFreeObject`), mirroring the existing `NCryptHandleFree`.
- `NCryptWrapper` (+ `NCryptWrapperImpl`, + `MockNCryptWrapper`):
  - `CreatePersistedKey(NCryptHandleFree const& providerHandle, NCryptKeyHandleFree& keyHandle, LPCWSTR pszAlgId, LPCWSTR pszName, DWORD dwLegacyKeySpec, DWORD dwFlags)` → `NCryptCreatePersistedKey`
  - `OpenKey(NCryptHandleFree const& providerHandle, NCryptKeyHandleFree& keyHandle, LPCWSTR pszName, DWORD dwLegacyKeySpec, DWORD dwFlags)` → `NCryptOpenKey`
  - `DeleteKey(NCryptKeyHandleFree const& keyHandle)` → `NCryptDeleteKey`
- `WindowsTpmRepository` (+ impl):
  - `void CreateTpmKey(const std::string& name) const` — opens the Platform Crypto Provider, creates a persisted RSA key (`NCRYPT_RSA_ALGORITHM`, user scope, `dwFlags = 0` so the key is persisted immediately; no elevation required for user-scope keys — verified experimentally on the target machine). `NTE_EXISTS` → throw `hresult_error(error_key_already_exists, ...)`; provider-open failure → `error_tpm_unsupported`; other failures → a TPM-family error via the existing `CheckStatus` pattern.
  - `void DeleteTpmKey(const std::string& name) const` — opens the provider, opens the key by name, deletes it. `NTE_NO_KEY` (from open or delete) → throw `hresult_error(error_key_not_found, ...)`.
- Unit tests in `windows/test/windows_tpm_repository_test.cpp` via `MockNCryptWrapper`: create success, create NTE_EXISTS → keyAlreadyExists error, delete success (open + delete sequence, `FreeBuffer` not involved; key handle released by RAII), delete NTE_NO_KEY → keyNotFound error.

### 2. Service + method channel

- `BiometricCipherService`: `void CreateTpmKey(const std::string& name) const` and `void DeleteTpmKey(const std::string& name) const` — synchronous pass-throughs to the repository. This follows the plan's documented deviation precedent (`ListKeys()`): WinRT `IAsyncOperation`/`IAsyncAction` is not needed for plain-void NCrypt calls.
- `MethodName`: add `kCreateTpmKey`, `kDeleteTpmKey` with channel names `createTpmKey`, `deleteTpmKey`.
- `ArgumentName`: add `kName` ("name") for the key-name argument.
- `BiometricCipherPlugin`: two new dispatch cases and handlers following the existing `kDeleteKey` pattern — parse `name` argument, call service, `result->Success(NULL)`; on `hresult_error`, `result->Error(GetErrorCodeString(hr), message)`.
- Error HRESULTs reuse existing constants already mapped by `error_codes.cpp` and the Dart exception-code table: `error_key_already_exists` → `KEY_ALREADY_EXISTS`, `error_key_not_found` → `KEY_NOT_FOUND`, `error_tpm_unsupported` → `TPM_UNSUPPORTED`.

### 3. Dart layer

- Platform interface + method channel + `BiometricCipher`:
  - `Future<void> createTpmKey({required String name})`
  - `Future<void> deleteTpmKey({required String name})`
  - Empty-name validation throws `BiometricCipherException(invalidArgument)` (existing validation style); `PlatformException` mapped via the existing `_mapPlatformException`.
- Mock platform: track created TPM key names in a list; `createTpmKey` throws `keyAlreadyExists` on duplicates; `deleteTpmKey` throws `keyNotFound` for unknown names; exposes the list for assertions.
- Tests: create success, create duplicate → `keyAlreadyExists`, delete success, delete missing → `keyNotFound`, empty-name validation for both.

### 4. Example app UI

In `example/lib/tpm_screen.dart`, adjacent to "List TPM keys":
- "Create TPM key" button — key name from the existing tag text field; success snackbar on create; error snackbar on failure
- "Delete TPM key" button — same input; success/error snackbars
- Handlers follow the existing `_onDeleteKeyPressed` pattern (empty-input validation, try/catch, `context.mounted` guard)

## Error behavior

| Case | Result |
|---|---|
| Create with existing key name | `BiometricCipherException(keyAlreadyExists)` |
| Delete with missing key name | `BiometricCipherException(keyNotFound)` |
| Empty key name | `BiometricCipherException(invalidArgument)` |
| No TPM / storage provider failure | `BiometricCipherException(tpmUnsupported)` |

## Verification

- Native suite: new repository tests + service tests (mock-based), full suite green, `/W4 /WX` clean
- Dart: `fvm flutter test` (new + existing tests), analyzer `--fatal-warnings --fatal-infos` zero findings
- Manual GUI run: Create TPM key → press List TPM keys → name appears; Delete TPM key → press List TPM keys → gone; duplicate create → error snackbar; delete missing → error snackbar

## Out of scope

- Encrypt/decrypt with raw TPM keys (RSA/NCryptEncrypt/NCryptDecrypt) — Windows Hello path remains the crypto mechanism
- Machine-scope key operations (require elevation)
- Other platforms
