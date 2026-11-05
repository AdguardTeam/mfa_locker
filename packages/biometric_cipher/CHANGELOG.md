# Changelog

All notable changes to this plugin are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-11-05

Breaking while the package is pre-1.0, where a minor bump is the signal.

### Breaking

- Removed the native Windows implementation and the `windows` platform declaration; the plugin
  ships for Android, iOS and macOS only.
- Removed `ConfigData.windowsDataToSign` — constructor parameter, `fromMap` entry and `toMap` entry.
- Raised the minimum deployment targets to iOS 15.0 and macOS 12.0 in the shared Darwin podspec
  that both Apple platforms build against.

### Added

- `isBiometricCipherSupported` — a predicate telling callers whether the plugin has a native
  implementation on the current platform.

### Changed

- Package `description` now names Secure Enclave and Android Keystore and no longer advertises
  Windows.
