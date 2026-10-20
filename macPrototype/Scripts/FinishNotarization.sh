#!/bin/sh
# Finalize an already submitted archive. Does not upload another submission.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
archive=${1:?Pass the already submitted xcarchive}
final="$root/../deliveries/NoteNarrate-macOS-0.1.0-universal-notarized.zip"
[ ! -e "$final" ] || { printf 'Final package already exists.\n' >&2; exit 1; }
staging=$(mktemp -d /tmp/notenarrate-notarized.XXXXXX)
xcodebuild -exportNotarizedApp -archivePath "$archive" -exportPath "$staging/export"
app="$staging/export/NoteNarrate.app"
sh "$root/Scripts/CheckNotarized.sh" "$app"
mkdir -p "$root/../deliveries" "$staging/package"
ditto "$app" "$staging/package/NoteNarrate.app"
cp "$root/ISTRUZIONI.txt" "$staging/package/ISTRUZIONI.txt"
ditto -c -k --sequesterRsrc "$staging/package" "$staging/NoteNarrate.zip"
unzip -tq "$staging/NoteNarrate.zip"
ditto -x -k "$staging/NoteNarrate.zip" "$staging/extracted"
sh "$root/Scripts/CheckNotarized.sh" "$staging/extracted/NoteNarrate.app"
mv "$staging/NoteNarrate.zip" "$final"
shasum -a 256 "$final" > "$final.sha256"
printf 'VERIFIED PACKAGE: %s\nExported app: %s\n' "$final" "$app"
