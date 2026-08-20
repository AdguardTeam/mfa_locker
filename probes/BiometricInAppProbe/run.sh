#!/bin/bash
# Builds and runs the BiometricInAppProbe (AW-3216).
#
# Two run modes:
#
#   1) ./run.sh              -> Terminal "lite mode" (`swift run`).
#      The in-window LocalAuthenticationView works and the Touch ID sensor
#      responds (the core AW-3216 answer). Because the bare binary is unsigned
#      it cannot create a Secure Enclave key, so the probe enters LITE MODE and
#      tells you to use mode 2 for the full "no second prompt" check.
#
#   2) ./run.sh app          -> Build & launch via Xcode (full mode).
#      `open` the checked-in BiometricInAppProbe.xcodeproj, pick your Team in
#      "Signing & Capabilities" (Automatic signing), press Run. The Xcode build
#      is provisioning-signed, which is what permits the keychain-access-groups
#      RESTRICTED entitlement -> Secure Enclave key creation works -> the
#      full LAContext-reuse/decrypt check can complete.
#
#   ./run.sh gen-project     -> (re)generate the .xcodeproj from project.yml
#      (requires `brew install xcodegen`). Committed .xcodeproj means other
#      devs do NOT need xcodegen — only Xcode.
set -euo pipefail
cd "$(dirname "$0")"

case "${1:-}" in
  app)
    if [ ! -d BiometricInAppProbe.xcodeproj ]; then
      echo "Missing BiometricInAppProbe.xcodeproj — run ./run.sh gen-project first." >&2
      exit 1
    fi
    echo "Opening BiometricInAppProbe.xcodeproj in Xcode…" >&2
    echo "  → Select your Team in 'Signing & Capabilities' (Automatic signing)" >&2
    echo "  → Press Run (⌘R)" >&2
    open BiometricInAppProbe.xcodeproj
    ;;
  gen-project)
    command -v xcodegen >/dev/null 2>&1 || { echo "xcodegen not found — brew install xcodegen" >&2; exit 1; }
    xcodegen generate
    ;;
  *)
    echo "Lite mode: swift run (in-window biometric works; SE-key step reports lite mode)." >&2
    echo "For the full check: ./run.sh app" >&2
    swift run
    ;;
esac


