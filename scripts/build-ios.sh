#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "${SCRCPY_BUILD_LOCK_HELD:-0}" != 1 ]; then
    exec python3 scripts/with-build-lock.py bash scripts/build-ios.sh "$@"
fi
mode="${1:-simulator}"
case "$mode" in simulator|device|test) ;; *) echo 'Usage: scripts/build-ios.sh [simulator|device|test]' >&2; exit 2 ;; esac
python3 scripts/prepare-resources.py
if [ "$mode" = device ]; then scripts/build-crypto.sh iphoneos; else scripts/build-crypto.sh iphonesimulator; fi
if [ "$mode" = test ]; then scripts/build-crypto.sh macosx; fi
xcodegen generate
if [ "$mode" = test ]; then
    xcrun swift test
    : "${SCRCPY_SIMULATOR:?Set SCRCPY_SIMULATOR to an owned iOS simulator UUID}"
    xcodebuild -project Scrcpy.xcodeproj -scheme Scrcpy -configuration Debug \
        -destination "platform=iOS Simulator,id=$SCRCPY_SIMULATOR" \
        -derivedDataPath build/simulator -parallel-testing-enabled NO CODE_SIGN_IDENTITY=- test
elif [ "$mode" = simulator ]; then
    xcodebuild -project Scrcpy.xcodeproj -scheme Scrcpy -configuration Debug \
        -destination 'generic/platform=iOS Simulator' -derivedDataPath build/simulator CODE_SIGN_IDENTITY=- build
else
    xcodebuild -project Scrcpy.xcodeproj -scheme Scrcpy -configuration Release \
        -destination 'generic/platform=iOS' -archivePath build/Scrcpy.xcarchive CODE_SIGNING_ALLOWED=NO archive
    # This IPA needs the user's own provisioning and signature before installation.
    python3 - <<'PY'
from pathlib import Path
import zipfile
source = Path('build/Scrcpy.xcarchive/Products/Applications/Scrcpy.app')
with zipfile.ZipFile('build/Scrcpy-unsigned.ipa', 'w', zipfile.ZIP_DEFLATED) as archive:
    for file in sorted(source.rglob('*')):
        if file.is_file():
            archive.write(file, Path('Payload/Scrcpy.app') / file.relative_to(source))
print('Created build/Scrcpy-unsigned.ipa (requires signing).')
PY
fi
