#!/usr/bin/env bash
#
# Stream iWADemo [iWA] logs from a connected iPhone, adb-logcat style.
# The iOS analog of:  adb logcat -c && adb logcat | grep -E "[Tags]"
#
# The device is auto-detected — you never type a UDID.
# Requires libimobiledevice:  brew install libimobiledevice
#
# Usage:
#   ./scripts/ios-logs.sh                  # all [iWA] logs (default filter)
#   ./scripts/ios-logs.sh <UDID>           # target a specific device
#   IWA_LOG_FILTER='\[iWA\]|InstalledWalletDetector|WalletConnectSolanaClient|STEP_FAIL' \
#     ./scripts/ios-logs.sh                # narrow to specific components
#
# See docs/device-logging.md for the full workflow + decoder ring.

set -uo pipefail

if ! command -v idevicesyslog >/dev/null 2>&1; then
  echo "error: idevicesyslog not found. Install it with:  brew install libimobiledevice" >&2
  exit 1
fi

UDID="${1:-$(idevice_id -l 2>/dev/null | head -n1)}"
if [ -z "${UDID}" ]; then
  echo "error: no connected iOS device found. Connect over USB, unlock, and tap Trust, then retry." >&2
  exit 1
fi

# Default matches both the "[iWA]" and "[iWA Demo]" prefixes.
FILTER="${IWA_LOG_FILTER:-\\[iWA}"

echo "Streaming iWA logs from device ${UDID} (Ctrl+C to stop)…" >&2
echo "Filter: ${FILTER}" >&2
echo "Tip: reproduce the flow now (open picker → connect → sign → approve)." >&2
echo "Launch the app and look for the STEP_0_BOOT line — that confirms you're on the" >&2
echo "fresh build. No [iWA] lines at all? Rebuild + reinstall first (idevicesyslog only" >&2
echo "sees the INSTALLED build):  scripts/iwademo-device.sh reinstall" >&2
echo "----------------------------------------------------------------" >&2

# --line-buffered keeps the stream flowing line-by-line through the pipe.
idevicesyslog -u "${UDID}" | grep --line-buffered -E "${FILTER}"
