"""Verify compiled Siri actions and both phrase locales in an exported .app or IPA."""
import json
import plistlib
import sys
import zipfile
from pathlib import Path

EXPECTED = {
    'ExplainCurrentSongIntent', 'CreateSongRadioIntent', 'ResumeNoteNarrateIntent',
    'PauseNoteNarrateIntent', 'NextNoteNarrateSongIntent',
}

def verify(path):
    if path.suffix == '.ipa':
        archive = zipfile.ZipFile(path)
        prefix = next(name.rsplit('/', 1)[0] + '/' for name in archive.namelist()
                      if name.startswith('Payload/') and name.count('/') == 2
                      and name.endswith('/Info.plist'))
        read = lambda name: archive.read(prefix + name)
    else:
        read = lambda name: (path / name).read_bytes()
    data = json.loads(read('Metadata.appintents/extract.actionsdata'))
    actions = data['actions']
    shortcuts = {item['actionIdentifier']: item for item in data['autoShortcuts']}
    assert EXPECTED <= actions.keys(), 'Missing compiled Siri actions'
    assert EXPECTED <= shortcuts.keys(), 'Missing registered App Shortcuts'
    for name in EXPECTED:
        action = actions[name]
        assert not action['openAppWhenRun'], 'Siri action unexpectedly requires foreground UI'
        assert 'com.apple.link.systemProtocol.AudioStarting' in action['systemProtocols'], name
    phrases = {phrase['key'] for name in EXPECTED
               for phrase in shortcuts[name]['phraseTemplates']}
    for locale in ('it', 'en'):
        strings = plistlib.loads(read(locale + '.lproj/AppShortcuts.strings'))
        assert phrases <= strings.keys(), 'Missing phrase localization: ' + locale
        for phrase in phrases:
            assert strings[phrase].strip() and '${applicationName}' in strings[phrase], locale
    # Release exports strip the intermediate YAML and retain compiled NLU data.
    for locale in ('it', 'en'):
        assert read(locale + '.lproj/nlu.appintents/nlu.lzfse'), 'Missing compiled Siri locale'
    return {'siri_actions': sorted(EXPECTED), 'shortcuts_verified': len(EXPECTED),
            'localized_phrases': len(phrases), 'locales': ['it', 'en'],
            'audio_playback_intents': True, 'foreground_not_required': True}

if __name__ == '__main__':
    print(json.dumps(verify(Path(sys.argv[1])), indent=2))
