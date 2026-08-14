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

> **Use `./run.sh` (NOT `swift run`).** A plain `swift run` binary is unsigned
> and macOS refuses Secure Enclave key creation with
> **`errSecMissingEntitlement` (-34018)**. `run.sh` signs the binary with
> `Entitlements.plist` (keychain access-group) and then launches it.

```sh
cd probes/BiometricInAppProbe
./run.sh
```

If ad-hoc signing lacks permission, `run.sh` falls back to any **Apple
Development** identity in your keychain. If neither is available, unlock a
keychain containing an Apple Development certificate and retry.

You should see a standalone window titled **"BiometricInAppProbe — AW-3216"**
with a **"Continue with Touch ID"** control **inside the window**, a
"Use Password…" fallback button, and a status area.

## What to observe (checklist)

1. **In-window UI** — the Touch ID control renders inside the app window, NOT
   as a separate system window/dialog. **This part already works** — observed:
   touching the sensor produced the success checkmark inside the window.
2. **In-window listening** — touching the sensor (while the in-window control is
   active) authorizes and the status turns to
   `✅ LocalAuthenticationView succeeded → reusing context for decrypt…`.
3. **No second prompt** — after the in-window authorization, a second system
   prompt must NOT appear; the flow goes straight to
   `🎉 SUCCESS — decrypted in-app with reused LAContext, no second prompt`.
4. **Fallback** — pressing "Use Password…" exercises `deviceOwnerAuthentication`;
   authorizing decrypts with the same shared context.
5. **Cancel** — canceling Touch ID reports a failure in the status area; the
   app remains usable (no crash, no stuck state).
6. **Secure Enclave key created** (no `errSecMissingEntitlement`/-34018) —
   status shows `✅ Secure Enclave key created; sample encrypted.`

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
