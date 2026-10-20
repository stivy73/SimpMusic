#!/usr/bin/env python3
"""Package the actual shared sources needed to rebuild the macOS app, without caches or credentials."""
from pathlib import Path
import zipfile

root = Path(__file__).resolve().parents[2]
destination = root / "deliveries/NoteNarrate-macOS-0.1.0-sources.zip"
paths = [
    root / "LICENSE",
    root / "macPrototype",
    root / "iosPrototype/Sources",
    root / "iosPrototype/Tests",
    root / "iosPrototype/Package.swift",
    root / "iosPrototype/Vendor/YouTubeSDK",
    root / "iosPrototype/ThirdPartyNotices.txt",
    root / "iosPrototype/PrivacyInfo.xcprivacy",
]
destination.parent.mkdir(exist_ok=True)
with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED) as archive:
    for path in paths:
        for item in ([path] if path.is_file() else path.rglob("*")):
            if not item.is_file():
                continue
            if any(part in {".build", ".git", "xcuserdata", "DerivedData"} for part in item.parts):
                continue
            if item.name == ".DS_Store":
                continue
            archive.write(item, "NoteNarrate/" + str(item.relative_to(root)))
print(destination)
