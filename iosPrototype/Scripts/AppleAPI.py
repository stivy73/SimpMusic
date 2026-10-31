#!/usr/bin/env python3
"""Run Xcode with the owner's local Apple API credentials, never with secrets in Git.

Usage: AppleAPI.py --check
       AppleAPI.py -- -exportArchive ...
Only the marked Apple section of Downloads/api.txt is read. The private key is
materialized in a mode-600 temporary file for Xcode and removed when it exits.
"""

import argparse
import json
import os
from pathlib import Path
import re
import ssl
import subprocess
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request


def testflight(key_path, key_id, issuer, app_id, version, group_name=None):
    if not app_id.isdigit() or not version.isdigit():
        raise ValueError("Invalid app or build identifier")
    environment = os.environ.copy()
    environment["DEVELOPER_DIR"] = "/Applications/Xcode-27.2.app/Contents/Developer"
    environment["CLANG_MODULE_CACHE_PATH"] = "/tmp/notenarrate-apple-token-cache"
    signer = Path(__file__).with_name("AppleAPIToken.swift")
    signed = subprocess.run(["/usr/bin/xcrun", "swift", str(signer), str(key_path), key_id, issuer],
                            capture_output=True, text=True, env=environment)
    if signed.returncode or len(signed.stdout.strip().split(".")) != 3:
        raise ValueError("Token signing failed")
    token = signed.stdout.strip()
    # python.org builds on macOS may have no default CA file. Use the installed
    # standard CA bundle while keeping certificate and hostname verification on.
    try:
        import certifi
        context = ssl.create_default_context(cafile=certifi.where())
    except ImportError:
        context = ssl.create_default_context()

    def request(path, payload=None):
        url = "https://api.appstoreconnect.apple.com/v1/" + path
        body = None if payload is None else json.dumps(payload).encode()
        req = urllib.request.Request(url, data=body, headers={
            "Authorization": "Bearer " + token, "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=45, context=context) as response:
                data = response.read()
                return json.loads(data) if data else {}
        except urllib.error.HTTPError as error:
            # Provider bodies/headers and bearer tokens must not enter diagnostics.
            code = "NON_JSON_RESPONSE"
            parameter = "UNKNOWN"
            try:
                errors = json.loads(error.read(65536)).get("errors", [])
                codes = [item.get("code", "") for item in errors]
                code = ",".join(value for value in codes if re.fullmatch(r"[A-Z0-9_.]+", value)) or "NO_ERROR_CODE"
                for item in errors:
                    value = item.get("source", {}).get("parameter")
                    if value in ("include", "filter[builds]", "filter[app]", "limit", "filter[version]"):
                        parameter = value
            except (ValueError, AttributeError):
                pass
            resource = path.split("?", 1)[0].split("/", 1)[0]
            raise ValueError("Apple API HTTP " + str(error.code) + " " + code + " " + resource + " " + parameter) from None

    query = urllib.parse.urlencode({"filter[app]": app_id, "filter[version]": version,
        "include": "preReleaseVersion,buildBetaDetail", "limit": "20"})
    response = request("builds?" + query)
    builds = response.get("data", [])
    if not builds:
        return {"app": app_id, "build": version, "processingState": "NOT_YET_VISIBLE"}
    if len(builds) != 1:
        raise ValueError("Build number is ambiguous")
    build = builds[0]
    attributes = build["attributes"]
    included = response.get("included", [])
    prerelease = next((x for x in included if x["type"] == "preReleaseVersions"), {})
    detail = next((x for x in included if x["type"] == "buildBetaDetails"), {})
    result = {"app": app_id, "build": version, "build_id": build["id"],
        "version": prerelease.get("attributes", {}).get("version"),
        "processingState": attributes.get("processingState"),
        "internalBuildState": detail.get("attributes", {}).get("internalBuildState")}
    group_query = urllib.parse.urlencode({"filter[app]": app_id, "limit": "200"})
    groups = request("betaGroups?" + group_query).get("data", [])
    if group_name:
        if result["processingState"] != "VALID":
            raise ValueError("Build is not ready for assignment")
        selected = [x for x in groups if x["attributes"].get("name") == group_name]
        if len(selected) != 1 or selected[0]["attributes"].get("isInternalGroup") is not True:
            raise ValueError("Expected one existing internal group for this app")
        group_id = selected[0]["id"]
        # Build-side linkage is Apple's current endpoint. Group-side POST can
        # time out while reads and this equivalent relationship update succeed.
        request("builds/" + build["id"] + "/relationships/betaGroups",
                {"data": [{"type": "betaGroups", "id": group_id}]})
    result["groups"] = []
    for group in groups:
        members = request("betaGroups/" + group["id"] + "/builds?limit=200").get("data", [])
        if any(item["id"] == build["id"] for item in members):
            result["groups"].append({"id": group["id"], "name": group["attributes"].get("name"),
                "internal": group["attributes"].get("isInternalGroup")})
    if group_name and not any(x["name"] == group_name and x["internal"] for x in result["groups"]):
        raise ValueError("Assignment not verified")
    return result


def credentials(path):
    if path.stat().st_mode & 0o077:
        raise ValueError("Credential file must be readable only by its owner (mode 600)")
    data = path.read_text()
    begin = "# BEGIN APP STORE CONNECT CODEX"
    end = "# END APP STORE CONNECT CODEX"
    if data.count(begin) != 1 or data.count(end) != 1:
        raise ValueError("Expected exactly one marked App Store Connect section")
    section = data.split(begin, 1)[1].split(end, 1)[0]
    key_id = re.search(r"^ASC_KEY_ID=([A-Z0-9]{10})$", section, re.M)
    issuer = re.search(r"^ASC_ISSUER_ID=([0-9a-fA-F-]{36})$", section, re.M)
    pem = re.search(r"-----BEGIN PRIVATE KEY-----\s+[A-Za-z0-9+/=\s]+-----END PRIVATE KEY-----", section)
    if not all((key_id, issuer, pem)):
        raise ValueError("The Apple section is incomplete")
    return key_id[1], issuer[1], pem[0] + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--credentials-file", type=Path,
                        default=Path(os.environ.get("ASC_CREDENTIALS_FILE", Path.home() / "Downloads/api.txt")))
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--testflight-status", nargs=2, metavar=("APP_ID", "BUILD"))
    parser.add_argument("--testflight-assign", nargs=3, metavar=("APP_ID", "BUILD", "INTERNAL_GROUP"))
    parser.add_argument("xcode_arguments", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    try:
        key_id, issuer, pem = credentials(args.credentials_file)
        with tempfile.TemporaryDirectory(prefix="notenarrate-apple-api-") as folder:
            key_path = Path(folder) / ("AuthKey_" + key_id + ".p8")
            descriptor = os.open(key_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(descriptor, "w") as stream:
                stream.write(pem)
            result = subprocess.run(["/usr/bin/openssl", "pkey", "-in", str(key_path),
                                     "-pubout", "-out", os.devnull], capture_output=True)
            if result.returncode:
                raise ValueError("Apple private key could not be parsed")
            if args.check:
                print("Apple API credentials loaded and validated; no secret values displayed")
                return 0
            if args.testflight_status or args.testflight_assign:
                values = args.testflight_assign or args.testflight_status
                print(json.dumps(testflight(key_path, key_id, issuer, *values), indent=2))
                return 0
            command = args.xcode_arguments
            if command and command[0] == "--":
                command = command[1:]
            if not command or any(value.startswith("-authenticationKey") for value in command):
                raise ValueError("Pass Xcode arguments after --, without authentication overrides")
            environment = os.environ.copy()
            environment["DEVELOPER_DIR"] = "/Applications/Xcode-27.2.app/Contents/Developer"
            authentication = ["-authenticationKeyPath", str(key_path),
                              "-authenticationKeyID", key_id, "-authenticationKeyIssuerID", issuer]
            if "-allowProvisioningUpdates" not in command:
                authentication.append("-allowProvisioningUpdates")
            return subprocess.run(["/usr/bin/xcrun", "xcodebuild", *command, *authentication],
                                  env=environment).returncode
    except (ValueError, OSError) as error:
        # Do not echo exceptions, file contents, headers, tokens or private key data.
        message = str(error)
        safe = (message if re.fullmatch(r"Apple API HTTP [0-9]{3} [A-Z0-9_.,]+ (?:apps|builds|betaGroups) [A-Za-z\[\]]+", message)
                or message in ("Token signing failed", "Build is not ready for assignment",
                              "Build number is ambiguous", "Assignment not verified",
                              "Expected one existing internal group for this app")
                else "check the local marked section, file permissions and arguments")
        category = type(error).__name__
        if isinstance(error, urllib.error.URLError):
            category += "/" + type(error.reason).__name__
        print("Apple API setup failed (" + category + "): " + safe, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
