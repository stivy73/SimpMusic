#!/bin/zsh
set -euo pipefail
TASK_MAC_ROOT="${0:A:h:h}"
TASK_MAC_BUILD="${NOTENARRATE_BUILD_DIR:-/tmp/notenarrate-mac-release}"
TASK_MAC_IDENTITY="${NOTENARRATE_SIGNING_IDENTITY:-Apple Development: Michele Stival (64A9DQLN43)}"
cd "$TASK_MAC_ROOT"
xcodebuild -project NoteNarrateMac.xcodeproj -scheme NoteNarrateMac \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$TASK_MAC_BUILD" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$TASK_MAC_IDENTITY" build
TASK_MAC_APP="$TASK_MAC_BUILD/Build/Products/Release/NoteNarrate.app"
codesign --verify --deep --strict "$TASK_MAC_APP"
mkdir -p ../deliveries
TASK_MAC_ZIP="$TASK_MAC_ROOT/../deliveries/NoteNarrate-macOS-0.1.0-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent "$TASK_MAC_APP" "$TASK_MAC_ZIP"
shasum -a 256 "$TASK_MAC_ZIP"
