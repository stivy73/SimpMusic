#!/bin/sh
set -eu
app=${1:?Pass the exported NoteNarrate.app path}
codesign --verify --deep --strict --all-architectures "$app"
archs=$(lipo -archs "$app/Contents/MacOS/NoteNarrate")
[ "$archs" = 'x86_64 arm64' ] || [ "$archs" = 'arm64 x86_64' ]
for arch in arm64 x86_64; do
  metadata=$(codesign -dv --verbose=4 --arch "$arch" "$app" 2>&1)
  printf '%s\n' "$metadata" | rg -q '^Authority=Developer ID Application: Archetipi Digitali srl \(63W2ZKR3Z7\)$'
  printf '%s\n' "$metadata" | rg -q 'flags=.*runtime'
  printf '%s\n' "$metadata" | rg -q '^Timestamp='
  codesign -d --entitlements :- --arch "$arch" "$app" 2>/dev/null | python3 -c 'import plistlib,sys; p=plistlib.loads(sys.stdin.buffer.read()); assert p.get("com.apple.security.app-sandbox") is True; assert p.get("com.apple.security.network.client") is True; assert not p.get("com.apple.security.get-task-allow", False)'
done
xcrun stapler validate "$app"
assessment=$(spctl --assess --type execute --verbose=2 "$app" 2>&1)
printf '%s\n' "$assessment"
printf '%s\n' "$assessment" | rg -q 'source=Notarized Developer ID'
printf 'PASS: Developer ID, hardened runtime, timestamp, universal arm64/x86_64, sandbox, ticket and Gatekeeper.\n'
