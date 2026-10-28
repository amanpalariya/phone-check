#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
swift build --package-path "$ROOT/macos" --product PhoneCheck
BIN="$(swift build --package-path "$ROOT/macos" --show-bin-path)"
APP="$ROOT/macos/build/PhoneCheckMaterialReview.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/macos/Resources/PhoneCheck.icns" "$APP/Contents/Resources/PhoneCheck.icns"
swiftc -parse-as-library -swift-version 5 -D PHONECHECK_VISUAL_TEST -target "$(uname -m)-apple-macos14.0" \
    -I "$BIN" "$BIN/PhoneCheckCore.o" \
    "$ROOT"/macos/Sources/PhoneCheck/*.swift "$ROOT/tests/ui/MacMaterialReview.swift" "$ROOT/tests/ui/MacTestbedChecks.swift" \
    -o "$APP/Contents/MacOS/PhoneCheckMaterialReview"
python3 - "$ROOT/macos/Info.plist" "$APP/Contents/Info.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'rb') as f: info = plistlib.load(f)
info.update(CFBundleIdentifier='dev.phonecheck.mac.visual', CFBundleExecutable='PhoneCheckMaterialReview', CFBundleName='Phone Check Material Review', CFBundleDisplayName='Phone Check Material Review', LSUIElement=False)
with open(sys.argv[2], 'wb') as f: plistlib.dump(info, f)
PY
codesign --force --sign - "$APP"
