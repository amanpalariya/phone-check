#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
swift build --package-path "$ROOT/macos" --product PhoneCheck
BIN="$(swift build --package-path "$ROOT/macos" --show-bin-path)"
APP="$ROOT/macos/build/PhoneCheckProductCapture.app"
mkdir -p "$APP/Contents/MacOS"
swiftc -D DEBUG -D PHONECHECK_VISUAL_TEST -parse-as-library -swift-version 5 -I "$BIN" "$BIN/PhoneCheckCore.o" "$ROOT"/macos/Sources/PhoneCheck/*.swift "$ROOT/website/scripts/CaptureMac.swift" -o "$APP/Contents/MacOS/ProductCapture"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleExecutable</key><string>ProductCapture</string><key>CFBundleIdentifier</key><string>dev.phonecheck.product-capture</string><key>CFBundleName</key><string>Phone Check Product Capture</string><key>NSPrincipalClass</key><string>NSApplication</string></dict></plist>
PLIST
codesign --force --sign - "$APP"
"$APP/Contents/MacOS/ProductCapture" --product-capture --hover --assets "$ROOT/website/assets/brands"
