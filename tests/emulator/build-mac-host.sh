#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
swift build --package-path "$ROOT/macos" --product PhoneCheck
BIN="$(swift build --package-path "$ROOT/macos" --show-bin-path)"
APP="$ROOT/macos/build/PhoneCheckE2E.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/macos/Resources/PhoneCheck.icns" "$APP/Contents/Resources/PhoneCheck.icns"
ARCH="$(uname -m)"
swiftc -D DEBUG -parse-as-library -swift-version 5 -target "$ARCH-apple-macos14.0" \
    -I "$BIN" "$BIN/PhoneCheckCore.o" \
    "$ROOT/macos/Sources/PhoneCheck/Companion.swift" \
    "$ROOT"/macos/Sources/PhoneCheck/Cloud*.swift \
    "$ROOT/macos/Sources/PhoneCheck/BrowserGoogleLogin.swift" \
    "$ROOT/macos/Sources/PhoneCheck/NotificationAlerts.swift" \
    "$ROOT/macos/Sources/PhoneCheck/PreviewDiagnostics.swift" \
    "$ROOT/macos/Sources/PhoneCheck/NotificationCommandController.swift" \
    "$ROOT/macos/Sources/PhoneCheck/Credentials.swift" \
    "$ROOT/macos/Sources/PhoneCheck/Transport.swift" \
    "$ROOT/tests/emulator/MacHost.swift" \
    -o "$APP/Contents/MacOS/PhoneCheckE2E"
python3 - "$ROOT/macos/Info.plist" "$APP/Contents/Info.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'rb') as f: info = plistlib.load(f)
info.update(CFBundleIdentifier='dev.phonecheck.mac.e2e', CFBundleExecutable='PhoneCheckE2E', CFBundleName='Phone Check Tests', CFBundleDisplayName='Phone Check Tests')
with open(sys.argv[2], 'wb') as f: plistlib.dump(info, f)
PY
codesign --force --sign - "$APP"
