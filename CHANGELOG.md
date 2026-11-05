# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2026-11-05

Major, because compatibility with `1.x` is broken on three axes at once — one of them cannot be
expressed by the version number alone, so all three are listed here rather than only in the pull
request that shipped them.

### Breaking

- Removed `BiometricConfig.windowsAuthData`. Callers that passed it no longer compile, and the
  plugin no longer receives `windowsDataToSign`.
- Dropped Windows from `biometric_cipher`. Windows apps keep password-only storage, but every call
  that needs the plugin now throws `BiometricException(notAvailable)`: `configureBiometricCipher`,
  `setupBiometry` and `BioCipherFunc.encrypt`/`decrypt`. Guard the startup call with
  `isBiometricCipherSupported` or catch the exception; `determineBiometricState` reports
  `BiometricState.tpmUnsupported` instead of throwing.
- Raised the minimum deployment targets to iOS 15.0 and macOS 12.0 in the plugin's shared Darwin
  podspec and both example apps; apps below them can no longer resolve the pod.

### Added

- `isBiometricCipherSupported` — the platform predicate the plugin owns, re-exported from
  `package:locker/locker.dart`, so callers can branch without depending on `biometric_cipher`
  directly.

### Changed

- `MFALocker.configureBiometricCipher` and `BioCipherFunc.encrypt`/`decrypt` throw
  `BiometricExceptionType.notAvailable` on a platform without a plugin implementation, instead of
  failing on the missing method-channel handler.
- `MFALocker.determineBiometricState` answers `BiometricState.tpmUnsupported` there instead of
  querying the native side.
- `biometric_cipher` 0.0.1 → 0.1.0 (pre-1.0, where a minor bump carries the breaking signal).
