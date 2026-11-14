"""Verify embedded dynamic frameworks are discoverable by dyld, not just signed."""
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile
import zipfile


def verify_app(app):
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    executable = app / info['CFBundleExecutable']
    environment = os.environ.copy()
    environment['DEVELOPER_DIR'] = '/Applications/Xcode-27.2.app/Contents/Developer'
    def otool(*args):
        return subprocess.check_output(['/usr/bin/xcrun', 'otool', *args], env=environment, text=True)
    paths = re.findall(r'cmd LC_RPATH\s+cmdsize \d+\s+path ([^\n]+) \(offset', otool('-l', str(executable)))
    references = []
    for binary in [executable, *app.glob('*.debug.dylib')]:
        references += re.findall(r'^\s+(@rpath/\S+) \(compatibility', otool('-L', str(binary)), re.M)
    embedded = [ref for ref in references if '.framework/' in ref]
    remote_extensions = list((app / 'Extensions').glob('*.appex'))
    if remote_extensions:
        assert len(remote_extensions) == 1, 'Unexpected remote extension count'
        extension = remote_extensions[0]
        extension_info = plistlib.loads((extension / 'Info.plist').read_bytes())
        assert extension_info['CFBundleIdentifier'] == info['CFBundleIdentifier'] + '.castnowplaying'
        assert extension_info['EXAppExtensionAttributes']['EXExtensionPointIdentifier'] == 'com.apple.nowplaying.remote-media'
        assert extension_info['MinimumOSVersion'] == '27.0'
        assert extension_info['CFBundleVersion'] == info['CFBundleVersion']
        assert 'GoogleCast.framework' not in otool('-L', str(extension / extension_info['CFBundleExecutable'])), 'Cast SDK must not load in the extension'
        weak = False
        for binary in [executable, *app.glob('*.debug.dylib')]:
            for command in otool('-l', str(binary)).split('Load command'):
                if '/NowPlaying.framework/NowPlaying ' in command:
                    assert 'LC_LOAD_WEAK_DYLIB' in command, 'NowPlaying must be weak-linked for older iPhones'
                    weak = True
        assert weak, 'Missing weak NowPlaying dependency'
    if embedded and '@executable_path/Frameworks' not in paths:
        raise ValueError('Missing @executable_path/Frameworks in app LC_RPATH: embedded frameworks cannot load')
    for ref in embedded:
        assert (app / 'Frameworks' / ref.removeprefix('@rpath/')).is_file(), 'Missing embedded dependency: ' + ref
    return {'bundle': info['CFBundleIdentifier'], 'version': info['CFBundleShortVersionString'],
            'build': info['CFBundleVersion'], 'runpaths': list(dict.fromkeys(paths)),
            'embedded_dependencies': list(dict.fromkeys(embedded)), 'dyld_paths_verified': True,
            'cast_remote_extension_verified': bool(remote_extensions)}


def verify(path):
    path = Path(path)
    if path.suffix != '.ipa':
        return verify_app(path)
    with tempfile.TemporaryDirectory(prefix='notenarrate-dyld-') as folder:
        with zipfile.ZipFile(path) as archive:
            root = Path(folder).resolve()
            assert all((root / name).resolve().is_relative_to(root) for name in archive.namelist())
            archive.extractall(root)
        apps = list((root / 'Payload').glob('*.app'))
        assert len(apps) == 1
        return verify_app(apps[0])


if __name__ == '__main__':
    try:
        print(json.dumps(verify(sys.argv[1]), indent=2))
    except (ValueError, AssertionError) as error:
        sys.exit(str(error))
