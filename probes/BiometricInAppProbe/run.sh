#!/bin/bash
# Builds and runs the probe.
#
# IMPORTANT (verified on-device 2026-08-14):
#   * `swift run` (unsigned) shows the in-window LocalAuthenticationView and the
#     Touch ID request + sensor work — this is the core answer of AW-3216.
#   * Creating a Secure Enclave key needs the `keychain-access-groups`
#     entitlement, which is a RESTRICTED entitlement: it is only honored under
#     an Xcode-signed build with a provisioning profile. Manually signing via
#     codesign makes macOS reject the app ("restricted entitlements … validation
#     failed", RBS Code 5 / SIGKILL 137), and without it key creation fails with
#     -34018. So the "reuse LAContext → no second prompt" step must run in a real
#     Xcode-signed target (mfa_locker plugin / app build), not this terminal one.
#
# Two modes:
#   ./run.sh          -> unsigned `swift run` (in-window biometric works; SE key
#                        step will report -34018)
#   ./run.sh xcode    -> hint to build this target under Xcode instead.
set -euo pipefail
cd "$(dirname "$0")"

if [ "${1:-}" = "xcode" ]; then
  echo "The Secure Enclave key step requires an Xcode-signed build." >&2
  echo "Suggested: open this package in Xcode, create an app target with an" >&2
  echo "entitlements file containing keychain-access-groups, then Run." >&2
  echo "Also see README.md → 'Why the SE-key step needs Xcode'." >&2
  exit 0
fi

swift run


