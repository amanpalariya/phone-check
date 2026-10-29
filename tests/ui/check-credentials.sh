#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CHECK_DIR="$(mktemp -d)"
trap 'rm -rf "$CHECK_DIR"' EXIT
APP="$CHECK_DIR/Checks.app"
mkdir -p "$APP/Contents/MacOS"
python3 - "$APP/Contents/Info.plist" <<'PY'
import plistlib, sys, uuid
with open(sys.argv[1], 'wb') as f:
    plistlib.dump(dict(CFBundleIdentifier='dev.phonecheck.credentials-checks.' + uuid.uuid4().hex,
                      CFBundleExecutable='Checks', CFBundlePackageType='APPL'), f)
PY
swiftc -D DEBUG -parse-as-library "$ROOT/macos/Sources/PhoneCheck/Credentials.swift" \
    "$ROOT/tests/ui/CredentialStorageChecks.swift" -o "$APP/Contents/MacOS/Checks"
# No Keychain read, write, or delete symbols may be linked into this storage path.
if nm -u "$APP/Contents/MacOS/Checks" | rg -q '_SecItem'; then
    echo 'Development credentials unexpectedly reference Keychain' >&2
    exit 1
fi
"$APP/Contents/MacOS/Checks" write
"$APP/Contents/MacOS/Checks" read
