#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

DEVICE_ID="${DEVICE_ID:-$(idevice_id -l 2>/dev/null | head -n1)}"
# Fallback: when libimobiledevice (idevice_id) doesn't see the device but CoreDevice
# does, take the identifier devicectl reports. devicectl install/launch accept it; the
# build uses a generic iOS destination so it doesn't depend on a specific id.
if [ -z "${DEVICE_ID}" ]; then
  DEVICE_ID="$(/usr/bin/xcrun devicectl list devices 2>/dev/null \
    | grep -iE 'available|connected' \
    | grep -oE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' \
    | head -n1)"
fi
BUNDLE_ID="${BUNDLE_ID:-com.mstevens843.iWADemo}"
PROJECT="Examples/iWADemo/iWADemo.xcodeproj"
SCHEME="iWADemo"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT/Examples/iWADemo/build/DeviceDerivedData}"
APP_PATH="${APP_PATH:-$DERIVED_DATA_PATH/Build/Products/Debug-iphoneos/iWADemo.app}"

usage() {
  cat <<EOF
Usage: scripts/iwademo-device.sh <command>

Commands:
  list            List CoreDevice devices.
  pair            Pair the configured iPhone for Xcode/CoreDevice.
  check           Show Xcode destinations for the demo scheme.
  build           Build iWADemo for the configured iPhone.
  install         Uninstall old app if present, then install the built .app.
  reinstall       Build, uninstall old app if present, then install.
  launch          Launch the installed app.
  launch-console  Launch the app attached to stdout/stderr.
  logs            Launch the app + tail filtered [iWA] logs via devicectl (attached).

For a detached, auto-UDID stream (the adb-logcat analog), use: scripts/ios-logs.sh
DEVICE_ID is auto-detected from the connected device; override it to target a specific one.

Environment overrides:
  DEVICE_ID=${DEVICE_ID:-<auto-detected>}
  BUNDLE_ID=$BUNDLE_ID
  DERIVED_DATA_PATH=$DERIVED_DATA_PATH
  APP_PATH=$APP_PATH
EOF
}

xcodebuild_demo() {
  # Generic iOS destination: build a device-generic signed .app (then devicectl
  # installs it to the specific DEVICE_ID). Decouples the build from whichever
  # device-id form is available (hardware UDID vs CoreDevice identifier).
  /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Debug \
    -destination "generic/platform=iOS" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -allowProvisioningUpdates \
    "$@"
}

build_app() {
  # Bake the gitignored root .env into the demo before building so on-device
  # runs (where ProcessInfo.environment is empty) get SOLANA_RPC_URL /
  # WALLETCONNECT_PROJECT_ID. No-op-safe when .env is absent (writes empty map).
  "$ROOT/scripts/iwa-env.sh" gen-device
  xcodebuild_demo build
}

install_app() {
  if [[ ! -d "$APP_PATH" ]]; then
    echo "App not found at $APP_PATH. Run: scripts/iwademo-device.sh build" >&2
    exit 1
  fi

  DEVELOPER_DIR="$DEVELOPER_DIR" /usr/bin/xcrun devicectl device uninstall app \
    --device "$DEVICE_ID" \
    "$BUNDLE_ID" || true

  DEVELOPER_DIR="$DEVELOPER_DIR" /usr/bin/xcrun devicectl device install app \
    --device "$DEVICE_ID" \
    "$APP_PATH"
}

launch_app() {
  DEVELOPER_DIR="$DEVELOPER_DIR" /usr/bin/xcrun devicectl device process launch \
    --terminate-existing \
    --device "$DEVICE_ID" \
    "$BUNDLE_ID"
}

launch_console() {
  DEVELOPER_DIR="$DEVELOPER_DIR" /usr/bin/xcrun devicectl device process launch \
    --terminate-existing \
    --console \
    --device "$DEVICE_ID" \
    "$BUNDLE_ID"
}

# Every [iWA] component tag + every STEP_FAIL variant, across all 4 wallets.
IWA_LOG_FILTER='\[iWA\]|WalletAdapterClient|WalletAdapter |WalletProvider|WalletResponseDecoder|InstalledWalletDetector|WalletPickerModel|WalletAdapterServiceConfiguration|KeychainWalletAdapterStateStore|WalletConnectSolanaClient|SimulatorMockWallet|DemoTransactionBuilder|STEP_FAIL'

tail_logs() {
  launch_console 2>&1 | grep --line-buffered -E "$IWA_LOG_FILTER"
}

command="${1:-}"

# Commands that drive a specific device need a resolved DEVICE_ID. Auto-detection
# (above) covers the common case; fail clearly when nothing is connected.
case "$command" in
  ""|help|-h|--help|list|check) ;;
  *)
    if [ -z "${DEVICE_ID}" ]; then
      echo "error: no iOS device detected. Connect the iPhone over USB, unlock it, tap Trust," >&2
      echo "       install libimobiledevice ('brew install libimobiledevice'), or set" >&2
      echo "       DEVICE_ID=<udid> explicitly. List devices: scripts/iwademo-device.sh list" >&2
      exit 1
    fi
    ;;
esac

case "$command" in
  list)
    DEVELOPER_DIR="$DEVELOPER_DIR" /usr/bin/xcrun devicectl list devices \
      --timeout 30 \
      --columns '*'
    ;;
  pair)
    DEVELOPER_DIR="$DEVELOPER_DIR" /usr/bin/xcrun devicectl manage pair \
      --device "$DEVICE_ID" \
      --timeout 60
    ;;
  check)
    /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
      -showdestinations \
      -project "$PROJECT" \
      -scheme "$SCHEME"
    ;;
  build)
    build_app
    ;;
  install)
    install_app
    ;;
  reinstall)
    build_app
    install_app
    ;;
  launch)
    launch_app
    ;;
  launch-console)
    launch_console
    ;;
  logs)
    tail_logs
    ;;
  ""|help|-h|--help)
    usage
    ;;
  *)
    echo "Unknown command: $command" >&2
    usage >&2
    exit 2
    ;;
esac
