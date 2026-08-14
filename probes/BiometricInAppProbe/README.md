# BiometricInAppProbe — AW-3216

Standalone SwiftUI harness that verifies the central question of AW-3216:
**can the macOS Touch ID request be rendered INSIDE the app window** (like
Keychain Access), with the authorized `LAContext` reused so the Secure-Enclave
key operation does not show a second system prompt?

## Why this exists

The Flutter PoC (classic `SecKeyCreateDecryptedData` / `evaluateAccessControl`)
always shows the macOS **system** Touch ID sheet on macOS — there is no public
API to draw that prompt inside Flutter's own window for the classic `SecKey`
path. Apple's newer **`LocalAuthenticationView`** (macOS 13+) renders the
authentication interface inside the app's own SwiftUI window and explicitly
supports reusing an existing `LAContext`. This probe proves that behaviour on
real hardware.

## Requirements

- macOS 13+ (built/tested on macOS 15).
- A Mac with an enrolled Touch ID sensor (for the biometric success path).
- Xcode Command Line Tools (Swift toolchain).

## Build & run

```sh
cd probes/BiometricInAppProbe
./run.sh        # == swift run
```

The window **"BiometricInAppProbe — AW-3216"** opens with a **"Continue with
Touch ID" control inside the window**, a "Use Password…" fallback button, and
a status area. Status lines are also echoed to stderr, so the probe can be
observed from a terminal.

> ⚠️ The **Secure Enclave key step cannot complete in this terminal build** —
> see "Why the SE-key step needs Xcode" below.

### Why the SE-key step needs Xcode

Verified on-device (2026-08-14):

- `LocalAuthenticationView` renders the Touch ID request **inside the app
  window** and the sensor works — touching it produces the in-window success
  checkmark. This confirms the core answer of AW-3216 (no separate system
  window; in-app biometric).
- Creating a Secure Enclave key requires the `keychain-access-groups`
  entitlement; without it key creation fails with `-34018` (errSecMissing
  Entitlement).
- `keychain-access-groups` is a **restricted** entitlement: it is only honored
  under an Xcode build signed through a provisioning profile. Hand-signing via
  `codesign` makes macOS reject the app ("Code has restricted entitlements, but
  the validation of its code signature failed" — RBS Code 5 / POSIX 153 / SIG
  KILL 137); signing without it leaves `-34018`.
- Therefore the final step — reuse the authorized `LAContext` for the SE-key
  operation and confirm **no second prompt** — must run in a real Xcode-signed
  target (the mfa_locker plugin or the adguard-wallet app build), not in this
  bare-terminal Swift package.

## What to observe (checklist)

1. **In-window UI** — the Touch ID control renders inside the app window, NOT
   as a separate system window/dialog. ✅ confirmed.
2. **In-window listening** — touching the sensor (while the in-window control is
   active) authorizes and the status turns to
   `✅ LocalAuthenticationView succeeded → reusing context for decrypt…`. ✅
   confirmed (incl. headless run).
3. **SE key created** — only in an Xcode-signed build: status shows
   `✅ Secure Enclave key created; sample encrypted.`
4. **No second prompt** — after the in-window authorization, a second system
   prompt must NOT appear; the flow goes straight to
   `🎉 SUCCESS — decrypted in-app with reused LAContext, no second prompt`.
   (Pending — requires the Xcode-signed build.)
5. **Fallback** — pressing "Use Password…" exercises `deviceOwnerAuthentication`;
   authorizing decrypts with the same shared context.
6. **Cancel** — canceling Touch ID reports a failure in the status area; the
   app remains usable (no crash, no stuck state).

## How the test works

- `ProbeModel` creates a throwaway **Secure Enclave** key
  (`SecAccessControl` with `.privateKeyUsage + .biometryCurrentSet`) and
  encrypts a sample string with the public key. The private key can only be
  used after biometric authorization.
- A single **shared `LAContext`** is passed to `LocalAuthenticationView`
  (so the in-window request authorizes exactly that context) and then reused
  as `kSecUseAuthenticationContext` for `SecItemCopyMatching` +
  `SecKeyCreateDecryptedData`.
- The status area reports every step, so the check "same context suppresses the
  second prompt" is observable in plain text.

## Important notes

- This is a **verification harness only** — it is intentionally NOT wired into
  the shippable `mfa_locker` package nor into `adguard-wallet`.
- A positive result = green light to build the follow-up: an mfa_locker
  `evaluateBiometricPolicy`/LocalAuthenticationView integration (macOS 13+)
  plus an adguard-wallet bridge (SwiftUI platform view). A negative result
  (a second prompt still appears / LAV still shows a system window) is
  documented as the outcome with alternatives.
- The key is deleted on each run (`SecItemDelete`) so the test is deterministic.
