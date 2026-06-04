#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

scripts/secret-scan.sh

swift build -c release

swift test

# Generate the (gitignored) device secrets file so the demo target compiles even
# on a fresh checkout. With no .env this writes an empty map.
scripts/iwa-env.sh gen-device

xcodebuild \
  -project Examples/iWADemo/iWADemo.xcodeproj \
  -scheme iWADemo \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build

git diff --check
