"""Check the embedded watchOS companion in a built iPhone .app (no credentials)."""
import json
import plistlib
import sys
from pathlib import Path

def check(path):
    app = Path(path)
    phone = plistlib.loads((app / 'Info.plist').read_bytes())
    watches = list((app / 'Watch').glob('*.app'))
    assert len(watches) == 1, 'Expected one embedded Watch app'
    watch = watches[0]
    info = plistlib.loads((watch / 'Info.plist').read_bytes())
    assert phone['CFBundleIdentifier'] == 'com.stivy.simpmusic.prototype'
    assert info['CFBundleIdentifier'] == phone['CFBundleIdentifier'] + '.watchapp'
    assert info['WKCompanionAppBundleIdentifier'] == phone['CFBundleIdentifier']
    assert info['WKApplication'] is True
    assert info['WKRunsIndependentlyOfCompanionApp'] is False
    for key in ['CFBundleShortVersionString', 'CFBundleVersion']:
        assert info[key] == phone[key], 'Phone/Watch version mismatch'
    assert info['UIDeviceFamily'] == [4]
    assert info['DTSDKName'] in ['watchos27.2', 'watchsimulator27.2']
    assert (watch / info['CFBundleExecutable']).is_file()
    assert (watch / 'Assets.car').is_file(), 'Watch icon assets missing'
    return {'bundle': info['CFBundleIdentifier'], 'companion': info['WKCompanionAppBundleIdentifier'],
            'version': info['CFBundleShortVersionString'], 'build': info['CFBundleVersion'],
            'sdk': info['DTSDKName'], 'minimum_watchos': info['MinimumOSVersion'],
            'embedded': True, 'independent': False}

if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit('Usage: CheckWatchCompanion.py <built-iPhone.app>')
    print(json.dumps(check(sys.argv[1]), indent=2))
