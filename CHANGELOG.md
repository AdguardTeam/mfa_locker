# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2026-11-05

This release contains three breaking changes relative to `1.x`.

### Breaking

- Removed `BiometricConfig.windowsAuthData`. Callers that passed it no longer compile.
- Windows is no longer a supported biometric platform: every call that needs the plugin
  (`configureBiometricCipher`, `setupBiometry`, `BioCipherFunc.encrypt`/`decrypt`) throws
  `BiometricException(notAvailable)`, and `determineBiometricState` reports
  `BiometricState.tpmUnsupported`. Guard with `isBiometricCipherSupported` or catch the exception.
- Requires iOS 15.0 / macOS 12.0 (raised in `biometric_cipher` 0.1.0); apps below them can no longer
  resolve the pod.

### Added

- `isBiometricCipherSupported` — the platform predicate the plugin owns, re-exported from
  `package:locker/locker.dart`, so callers can branch without depending on `biometric_cipher`
  directly.

### Changed

- `biometric_cipher` 0.0.1 → 0.1.0 (pre-1.0, where a minor bump carries the breaking signal).
