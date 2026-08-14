#!/bin/bash
# Builds the probe and signs it with keychain entitlements.
#
# Why: a plain `swift run` binary is not signed with a keychain access-group
# entitlement, so macOS refuses Secure Enclave key creation with
# errSecMissingEntitlement (-34018). Re-signing with Entitlements.plist fixes it
# (ad-hoc identity is enough for local verification).
set -euo pipefail
cd "$(dirname "$0")"

swift build

BIN=".build/debug/BiometricInAppProbe"

# Ad-hoc signing with entitlements; falls back to any Apple Development identity.
if ! codesign --force --sign - --entitlements Entitlements.plist "$BIN" 2>/dev/null; then
  echo "Ad-hoc codesign failed; trying an Apple Development identity…" >&2
  IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null |
    awk '/Apple Development/ { print $2; exit }')
  if [ -n "$IDENTITY" ]; then
    codesign --force --sign "$IDENTITY" --entitlements Entitlements.plist "$BIN"
  else
    echo "ERROR: no signing identity available; Secure Enclave key creation will fail (-34018)." >&2
    echo "Install/unlock a keychain with an 'Apple Development' certificate and retry." >&2
    exit 1
  fi
fi

exec "$BIN"
