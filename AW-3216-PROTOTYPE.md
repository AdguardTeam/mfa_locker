# AW-3216 — in-window biometric (macOS) prototype

Branch `feature/AW-3216-poc-keychain-bio`. Adds the in-window
`LocalAuthenticationView` flow to `biometric_cipher`:

- `BiometricInAppView` platform view (macOS 13+): hosts `LocalAuthenticationView`
  inside the app window; on success stores the authorized `LAContext` on
  `SecureEnclaveManager` (`setAuthorizedContext`) and emits `onSuccess` to Dart;
  on cancel/error resets it (`resetAuthorizedContext`) and emits `onFailure`.
- `SecureEnclaveManager`: `setAuthorizedContext`/`resetAuthorizedContext`
  (macOS-gated), reusing the existing `evaluatedContext` so the master-key
  wrap unwrap does not show a second prompt.
- Dart: `BiometricInAppView` widget + `resetAuthorizedContext` through
  `BiometricCipher`/platform-interface/method-channel and locker
  `BiometricCipherProvider`/`SecurityProvider`.

## Build / verify

```sh
cd packages/biometric_cipher/example && flutter build macos --debug
```

Requires macOS 13+, Touch ID, and dev signing with `keychain-access-groups`
(ad-hoc/unsigned fails to persist SE keys with `-34018`).

## Integration & docs

- App integration: `adguard-wallet` branch
  `feature/AW-3216-keychain-like-biometric-macos`
  (lock screen, AuthBloc, unlock mixin; docs in `specs/.current/AW-3216/`).
- Analysis/plan/report/effort: see the docs in that branch (and originally in the
  AW-3216 spike repo).
