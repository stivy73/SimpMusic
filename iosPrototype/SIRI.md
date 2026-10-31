# Siri in NoteNarrate

Build 0.14.0 (42) adds App Shortcuts to the existing SiriKit media integration.
Install the update and open NoteNarrate once. Select a song, sign into YouTube
Music as needed, and configure Gemini for interpretation and radio. Siri must be
enabled on the device; its availability on the lock screen follows system settings.

## Italian phrases

- «Spiegami questa canzone con NoteNarrate»
- «Leggi il significato della canzone con NoteNarrate»
- «Crea una radio da questo brano con NoteNarrate»
- «Avvia la radio del brano con NoteNarrate»
- «Riprendi la musica con NoteNarrate» / «Riprendi NoteNarrate»
- «Metti in pausa NoteNarrate»
- «Prossimo brano con NoteNarrate»

The same actions appear in Apple's Shortcuts app without creating a shortcut by
hand. English trigger phrases are localized in en.lproj/AppShortcuts.strings.
Resume explicitly stops pending/active narration and plays the current song;
pause stops narration without resuming music. Repeating Explain during narration
or preparation reports that work is already active. Interpretation keeps music
playing during preparation and hands audio over when narration is ready, using
the same background path as the CarPlay narration button. Radio always requests
a fresh Gemini radio and fills its queue progressively, up to 50 songs.

## Existing media requests

SiriKit handles requests such as «Riproduci Fast Car di Tracy Chapman su
NoteNarrate», plus song/album/artist resolution, shuffle and repeat. This release
adds explicit custom action phrases; it does not replace Apple's media resolution.
Likes, liked-song collections and sleep-timer App Shortcuts are not added in 42.

## Validation

Six core tests cover missing current song, cloud configuration, loading audio,
repeat narration and local controls while narrating. Xcode metadata extraction
registers five AudioPlaybackIntent actions and eight localized phrase templates.
Run `python3 Scripts/CheckSiriMetadata.py <exported.ipa>` to verify the packaged
metadata, both phrase locales and absence of a foreground-UI requirement.

Device acceptance remains necessary: speak the phrases with Siri, verify playback
and spoken interpretation on iPhone/CarPlay, then test after backgrounding, locking
and a cold launch. Package metadata does not prove Siri recognition or vehicle audio.
The app must have a current/restored song for contextual actions; otherwise Siri
reports that a song must first be selected. Network preparation errors remain in
the existing app/CarPlay diagnostics after Siri acknowledges starting the request.
