#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
swift build --package-path "$ROOT/macos" --product PhoneCheck
BIN="$(swift build --package-path "$ROOT/macos" --show-bin-path)"
APP="$ROOT/macos/build/PhoneCheckLocalChecks.app"
mkdir -p "$APP/Contents/MacOS"
swiftc -D DEBUG -parse-as-library -swift-version 5 -target "$(uname -m)-apple-macos14.0" \
    -I "$BIN" "$BIN/PhoneCheckCore.o" \
    "$ROOT/macos/Sources/PhoneCheck/Companion.swift" \
    "$ROOT"/macos/Sources/PhoneCheck/Cloud*.swift \
    "$ROOT/macos/Sources/PhoneCheck/BrowserGoogleLogin.swift" \
    "$ROOT/macos/Sources/PhoneCheck/NotificationAlerts.swift" \
    "$ROOT/macos/Sources/PhoneCheck/PreviewDiagnostics.swift" \
    "$ROOT/macos/Sources/PhoneCheck/NotificationCommandController.swift" \
    "$ROOT/macos/Sources/PhoneCheck/Credentials.swift" \
    "$ROOT/macos/Sources/PhoneCheck/Transport.swift" \
    "$ROOT/tests/local/UnsignedLocalChecks.swift" \
    -o "$APP/Contents/MacOS/PhoneCheckLocalChecks"
python3 - "$ROOT/macos/Info.plist" "$APP/Contents/Info.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'rb') as source: info = plistlib.load(source)
info.update(CFBundleIdentifier='dev.phonecheck.mac.localchecks', CFBundleExecutable='PhoneCheckLocalChecks', CFBundleName='Phone Check Local Checks')
with open(sys.argv[2], 'wb') as target: plistlib.dump(info, target)
PY
codesign --force --sign - "$APP"
"$APP/Contents/MacOS/PhoneCheckLocalChecks" "$@"
