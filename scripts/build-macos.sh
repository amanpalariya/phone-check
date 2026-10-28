#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
MINIMUM_MACOS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$ROOT/macos/Info.plist")"
# This command-line toolchain otherwise records the deployment target as the SDK
# version, causing AppKit to select its pre-Liquid-Glass compatibility appearance.
# Record the SDK actually used for compilation, retaining the older runtime floor.
swift build --package-path "$ROOT/macos" -c "$CONFIGURATION" --product PhoneCheck \
    --sdk "$SDK_PATH" \
    -Xlinker -platform_version -Xlinker macos -Xlinker "$MINIMUM_MACOS" -Xlinker "$SDK_VERSION"
BIN="$(swift build --package-path "$ROOT/macos" -c "$CONFIGURATION" --show-bin-path)"
APP="$ROOT/macos/build/Phone Check.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/PhoneCheck" "$APP/Contents/MacOS/PhoneCheck"
# Catch regressions in the binary's linked-on-or-after appearance metadata.
xcrun vtool -show-build "$APP/Contents/MacOS/PhoneCheck" | python3 -c '
import re, sys
actual = re.search(r"^\s*sdk\s+(\S+)", sys.stdin.read(), re.M)
normalize = lambda value: tuple(int(part) for part in value.split(".")[:2])
if actual is None or normalize(actual.group(1)) != normalize(sys.argv[1]):
    raise SystemExit("Built executable SDK does not match the selected macOS SDK")
' "$SDK_VERSION"
cp "$ROOT/macos/Resources/PhoneCheck.icns" "$APP/Contents/Resources/PhoneCheck.icns"
cp "$ROOT/macos/Info.plist" "$APP/Contents/Info.plist"
# Set SIGNING_IDENTITY to an Apple Development / Developer ID identity for reliable
# local-network privacy and persistent Keychain access. Ad hoc signing is local-only.
IDENTITY="${SIGNING_IDENTITY:--}"
codesign --force --sign "$IDENTITY" --entitlements "$ROOT/macos/PhoneCheck.entitlements" "$APP"
printf '%s\n' "$APP"
