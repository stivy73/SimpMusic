#!/usr/bin/env python3
"""Run Xcode with the owner's local Apple API credentials, never with secrets in Git.

Usage: AppleAPI.py --check
       AppleAPI.py -- -exportArchive ...
Only the marked Apple section of Downloads/api.txt is read. The private key is
materialized in a mode-600 temporary file for Xcode and removed when it exits.
"""

import argparse
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


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
    except (ValueError, OSError):
        # Do not echo exceptions, file contents, headers, tokens or private key data.
        print("Apple API setup failed: check the local marked section, file permissions and arguments", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
