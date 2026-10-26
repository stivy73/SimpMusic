"""Verify the exported Apple-signed IPA, including CarPlay in both signatures.

Run on macOS outside a restricted filesystem sandbox. No credentials are read.
"""

import hashlib
import json
import plistlib
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path


def require(condition, message):
    if not condition:
        raise ValueError(message)


def verify(ipa):
    with tempfile.TemporaryDirectory(prefix="notenarrate-carplay-check-") as folder:
        root = Path(folder).resolve()
        with zipfile.ZipFile(ipa) as archive:
            require(archive.testzip() is None, "IPA ZIP integrity failed")
            for member in archive.infolist():
                require(
                    (root / member.filename).resolve().is_relative_to(root),
                    "Invalid path in IPA",
                )
            archive.extractall(root)
        apps = list((root / "Payload").glob("*.app"))
        require(len(apps) == 1, "Expected one app in IPA")
        app = apps[0]
        info = plistlib.loads((app / "Info.plist").read_bytes())
        result = subprocess.run(
            ["codesign", "-d", "--entitlements", ":-", str(app)],
            capture_output=True,
            check=True,
        )
        raw = result.stdout
        start = raw.find(b"<?xml")
        require(start >= 0, "Signed entitlements are unavailable")
        signed = plistlib.loads(raw[start:])
        profile = plistlib.loads(
            subprocess.check_output(
                ["security", "cms", "-D", "-i", str(app / "embedded.mobileprovision")]
            )
        )
        bundle = "com.stivy.simpmusic.prototype"
        team = "63W2ZKR3Z7"
        require(info["CFBundleIdentifier"] == bundle, "Unexpected Bundle ID")
        require(profile["TeamIdentifier"] == [team], "Unexpected Apple Team")
        for name, entitlements in (
            ("signature", signed),
            ("profile", profile["Entitlements"]),
        ):
            require(
                entitlements.get("com.apple.developer.carplay-audio") is True,
                f"CarPlay missing from {name}",
            )
            require(
                entitlements.get("application-identifier") == f"{team}.{bundle}",
                f"Unexpected app identifier in {name}",
            )
            require(
                entitlements.get("get-task-allow") is False,
                f"Distribution entitlement invalid in {name}",
            )
        voice = "INPlayMediaIntent" in info.get("INIntentsSupported", [])
        if voice:
            require(signed.get("com.apple.developer.siri") is True, "Siri missing from app signature")
            require(profile["Entitlements"].get("com.apple.developer.siri") is True, "Siri missing from app profile")
            extensions = list((app / "PlugIns").glob("*.appex"))
            by_id = {plistlib.loads((value / "Info.plist").read_bytes())["CFBundleIdentifier"]: value for value in extensions}
            require(set(by_id) == {bundle + ".MediaIntents", bundle + ".Widgets", bundle + ".Share"}, "Expected Siri, WidgetKit and Share extensions")
            extension = by_id[bundle + ".MediaIntents"]
            extension_info = plistlib.loads((extension / "Info.plist").read_bytes())
            require(extension_info["CFBundleIdentifier"] == bundle + ".MediaIntents", "Unexpected extension ID")
            attributes = extension_info["NSExtension"]["NSExtensionAttributes"]
            require("INPlayMediaIntent" in attributes["IntentsSupported"], "Media intent missing from extension")
            require(extension_info["CFBundleVersion"] == info["CFBundleVersion"], "Extension build mismatch")
            extension_profile = plistlib.loads(subprocess.check_output(
                ["security", "cms", "-D", "-i", str(extension / "embedded.mobileprovision")]))
            require(extension_profile["Entitlements"].get("com.apple.developer.siri") is True,
                    "Siri missing from extension profile")
            require(extension_profile["TeamIdentifier"] == [team], "Unexpected extension Team")
            extension_sign = subprocess.run(["codesign", "-d", "--entitlements", ":-", str(extension)],
                                            capture_output=True, check=True).stdout
            extension_entitlements = plistlib.loads(extension_sign[extension_sign.find(b"<?xml"):])
            require(extension_entitlements.get("com.apple.developer.siri") is True,
                    "Siri missing from extension signature")
            widget = by_id[bundle + ".Widgets"]
            widget_info = plistlib.loads((widget / "Info.plist").read_bytes())
            require(widget_info["NSExtension"]["NSExtensionPointIdentifier"] == "com.apple.widgetkit-extension", "Widget extension type mismatch")
            for field in ("CFBundleShortVersionString", "CFBundleVersion"):
                require(widget_info[field] == info[field] == extension_info[field], "App/extension version mismatch")
            widget_profile = plistlib.loads(subprocess.check_output(["security", "cms", "-D", "-i", str(widget / "embedded.mobileprovision")]))
            widget_sign = subprocess.run(["codesign", "-d", "--entitlements", ":-", str(widget)], capture_output=True, check=True).stdout
            widget_entitlements = plistlib.loads(widget_sign[widget_sign.find(b"<?xml"):])
            group = "group.com.stivy.simpmusic.prototype"
            for name, value in (("app signature", signed), ("app profile", profile["Entitlements"]), ("widget signature", widget_entitlements), ("widget profile", widget_profile["Entitlements"])):
                require(group in value.get("com.apple.security.application-groups", []), "App Group missing from " + name)
            require(widget_profile["TeamIdentifier"] == [team], "Unexpected Widget Team")
            require(widget_entitlements.get("application-identifier") == f"{team}.{bundle}.Widgets", "Unexpected Widget app identifier")
            require(widget_entitlements.get("get-task-allow") is False, "Widget must use distribution signing")
            share = by_id[bundle + ".Share"]
            share_info = plistlib.loads((share / "Info.plist").read_bytes())
            share_extension = share_info["NSExtension"]
            require(share_extension["NSExtensionPointIdentifier"] == "com.apple.share-services", "Share extension type mismatch")
            activation = share_extension["NSExtensionAttributes"]["NSExtensionActivationRule"]
            require(activation.get("NSExtensionActivationSupportsText") is True, "Share must accept text")
            require(activation.get("NSExtensionActivationSupportsWebURLWithMaxCount") == 1, "Share must accept a web URL")
            require("UIBackgroundModes" not in share_info, "Share must not declare background playback")
            share_profile = plistlib.loads(subprocess.check_output(["security", "cms", "-D", "-i", str(share / "embedded.mobileprovision")]))
            share_sign = subprocess.run(["codesign", "-d", "--entitlements", ":-", str(share)], capture_output=True, check=True).stdout
            share_entitlements = plistlib.loads(share_sign[share_sign.find(b"<?xml"):])
            for name, value in (("share signature", share_entitlements), ("share profile", share_profile["Entitlements"])):
                require(group in value.get("com.apple.security.application-groups", []), "App Group missing from " + name)
                require(value.get("application-identifier") == f"{team}.{bundle}.Share", "Unexpected Share identifier")
                require(value.get("get-task-allow") is False, "Share must use distribution signing")
            require(share_profile["TeamIdentifier"] == [team], "Unexpected Share Team")
            for field in ("CFBundleShortVersionString", "CFBundleVersion"):
                require(share_info[field] == info[field], "Share version/build mismatch")
            required_intents = set(attributes["IntentsSupported"])
            for locale in ("Base", "it", "en"):
                vocabulary = app / (locale + ".lproj") / "AppIntentVocabulary.plist"
                require(vocabulary.exists(), "Siri vocabulary missing for " + locale)
                phrases = plistlib.loads(vocabulary.read_bytes()).get("IntentPhrases", [])
                covered = {entry.get("IntentName") for entry in phrases
                           if any(isinstance(text, str) and "NoteNarrate" in text
                                  for text in entry.get("IntentExamples", []))}
                require(required_intents <= covered, "Missing Siri example phrases for " + locale)
            require(not list(extension.rglob("AppIntentVocabulary.plist")), "Siri vocabulary belongs to main app only")
        scenes = info["UIApplicationSceneManifest"]["UISceneConfigurations"]
        carplay = scenes.get("CPTemplateApplicationSceneSessionRoleApplication", [])
        require(
            any(scene.get("UISceneClassName") == "CPTemplateApplicationScene"
                and scene.get("UISceneDelegateClassName", "").endswith(".CarPlayScene")
                for scene in carplay),
            "CarPlay scene configuration missing",
        )
        require("audio" in info.get("UIBackgroundModes", []), "Background audio missing")
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
        return {
            "app": info["CFBundleDisplayName"],
            "version": info["CFBundleShortVersionString"],
            "build": info["CFBundleVersion"],
            "bundle": bundle,
            "team": team,
            "signature_carplay": True,
            "profile_carplay": True,
            "codesign_verified": True,
            "siri_media_extension_verified": voice,
            "widget_app_group_verified": voice,
            "siri_example_phrases_verified": voice,
            "share_extension_verified": voice,
            "sha256": hashlib.sha256(ipa.read_bytes()).hexdigest(),
        }


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("Usage: python3 Scripts/CheckCarPlayIPA.py <exported.ipa>")
    try:
        print(json.dumps(verify(Path(sys.argv[1])), indent=2))
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        sys.exit(f"CarPlay IPA verification failed: {error}")
