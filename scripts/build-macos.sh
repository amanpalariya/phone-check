#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
swift build --package-path "$ROOT/macos" -c "$CONFIGURATION" --product PhoneCheck
BIN="$(swift build --package-path "$ROOT/macos" -c "$CONFIGURATION" --show-bin-path)"
APP="$ROOT/macos/build/Phone Check.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/PhoneCheck" "$APP/Contents/MacOS/PhoneCheck"
cp "$ROOT/macos/Resources/PhoneCheck.icns" "$APP/Contents/Resources/PhoneCheck.icns"
cp "$ROOT/macos/Info.plist" "$APP/Contents/Info.plist"
# Set SIGNING_IDENTITY to an Apple Development / Developer ID identity for reliable
# local-network privacy and persistent Keychain access. Ad hoc signing is local-only.
IDENTITY="${SIGNING_IDENTITY:--}"
codesign --force --sign "$IDENTITY" --entitlements "$ROOT/macos/PhoneCheck.entitlements" "$APP"
printf '%s\n' "$APP"
