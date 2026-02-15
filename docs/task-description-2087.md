# AW-2087: Add Error Code Mapping to secure_mnemonic

## Task Summary

- **Jira**: AW-2087
- **Type**: Task, Priority P2 (High)
- **Epic**: MFA Locker
- **PR**: #22 (`feature/AW-2087-errors-mapping` → `master`)
- **Author**: Mikhail Semenov
- **Scope**: Minor, Dart-only (no native code modified)
- **QA**: Testing not required

## Problem

The `_mapPluginError` method in `secure_mnemonic_provider.dart` maps errors from native platform code using unreliable string matching. Native platforms return inconsistent error strings (e.g. `key_not_found`, `key not found`, `KEY_NOT_FOUND`), making the mapping fragile and error-prone.

All platforms (Android, iOS/macOS, Windows) already use enum-based error codes in their native implementations, but the Dart side was not leveraging them.

## Solution

### What the task proposed

1. Create a `SecureMnemonicErrorCode` enum with standardized error codes
2. Create a `SecureMnemonicException` class wrapping the enum and a message
3. Update `MethodChannelSecureMnemonic` to parse `PlatformException` codes into the new exception type
4. Update the `locker` package to map exceptions by code instead of string

### What the PR actually did

The PR took a **Dart-only approach** — no native code was changed. Instead, it parses the existing platform error strings into a unified Dart exception model:

- Created `SecureMnemonicException` class with a `SecureMnemonicExceptionCode` enum
- Added parsing logic in `MethodChannelSecureMnemonic` to convert `PlatformException` instances into `SecureMnemonicException`
- Updated `secure_mnemonic_provider.dart` in the `locker` package to map by exception code instead of string matching
- Removed the old string-based `_mapPluginError` approach

**Key note**: Native code was NOT modified. The mapping from platform strings to enum codes happens entirely on the Dart side.

## New Classes

### `SecureMnemonicExceptionCode` (enum)

Standardized error codes representing all possible platform errors.

**Location**: `packages/secure_mnemonic/lib/data/secure_mnemonic_exception_code.dart`

### `SecureMnemonicException`

Exception class wrapping `SecureMnemonicExceptionCode` and an optional message, providing a typed alternative to raw `PlatformException`.

**Location**: `packages/secure_mnemonic/lib/data/secure_mnemonic_exception.dart`

## Files Modified

| File | Change |
|------|--------|
| `packages/secure_mnemonic/lib/data/secure_mnemonic_exception.dart` | **Added** — new exception class |
| `packages/secure_mnemonic/lib/data/secure_mnemonic_exception_code.dart` | **Added** — new exception code enum |
| `packages/secure_mnemonic/lib/secure_mnemonic_method_channel.dart` | Modified — parse `PlatformException` into `SecureMnemonicException` |
| `packages/secure_mnemonic/lib/secure_mnemonic.dart` | Modified — export new classes |
| `packages/secure_mnemonic/analysis_options.yaml` | Modified |
| `lib/security/secure_mnemonic_provider.dart` | Modified — map by exception code instead of string |
| `packages/secure_mnemonic/test/secure_mnemonic_test.dart` | Modified — updated tests |
| `packages/secure_mnemonic/test/mock_secure_mnemonic_platform.dart` | Modified — updated mock |

## PR Commits

1. `9e1982c` — added native exceptions parsing to dart exceptions
2. `4a3319c` — removed unused error code
3. `16ec8a9` — removed unneeded normalization

## Acceptance Criteria (from Jira)

1. All platform error codes use a standardized enum (`SecureMnemonicExceptionCode`)
2. `SecureMnemonicException` class wraps the enum code and message
3. `MethodChannelSecureMnemonic` parses `PlatformException` into typed exceptions
4. Error mapping in `locker` uses code-based matching instead of string-based
5. Old string-based `_mapPluginError` approach is removed
6. All existing tests pass
7. No regressions in biometric authentication flows
8. Documentation updated
