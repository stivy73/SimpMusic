# NoteNarrate iOS 0.7.1 (22)

CarPlay now has a Search tab with Songs, Artists and Albums server-side filters.
It follows the last search submitted on the phone; audio-entitled apps cannot use
Apple's navigation-only keyboard search template. Changing filters keeps the query.
Results retain their real content type and browse IDs; song selection plays that
result, while albums and artists open their own content. Now Playing adds album
and artist icon buttons. Known IDs navigate directly; older items without IDs
use a typed lookup rather than inventing an album or artist identifier.

Automatic narration now uses one interpretation request, with a 25-second network
timeout, and reads the complete returned answer without a second length-only
rewrite. The Italian 900-character prompt is unchanged. This removes a potential
conflict between two 90-second generation requests and the 45-second preparation
watchdog. It does not establish that every prior vehicle failure had that cause.

Validation: 90 core tests and two background CarPlay narration UI tests passed
(native voice and PCM streaming fixtures, with music resuming afterward). Live
Google test: interpretation 4.5 seconds, complete TTS response 14.25 seconds,
57.36 seconds of PCM received. These server/fixture tests do not verify physical
vehicle audibility. Typed live search returned songs, artists and albums. Release
archive, Mac build and Apple-signed CarPlay IPA checks passed.

The separate YouTube CDN HTTP 403 beyond 1 MiB is not fixed by this narration
change. Vehicle playback and Premium-account transport remain open validation.
No App Store submission or public release is requested.

Apple upload completed on 24 October 2026: Upload succeeded, package processing.
Build 22 is internal TestFlight only; tester assignment remains manual.

# NoteNarrate iOS 0.7.0 (21)

Adaptive iPhone Duo interface using Apple's iOS 27.1 SDK, native tab accessory
and ArrangementView. Player controls use available pane geometry; artwork fits
without cropping, action targets are at least 44 pt and album columns flex.
iOS 17 compatibility and the stable Mac playback hierarchy are preserved.

Three targeted Duo simulator UI checks passed: native speech pause/resume,
mini-player playback across tabs, and lyrics/player state across rotation.
Release archive, Mac build and Apple-signed IPA verification passed, including
CarPlay entitlement in the signature and provisioning profile. The existing
Store draft remains on build 20. Fold poses and real-vehicle behavior still need
hardware validation; simulator build success alone does not establish these.

Apple upload completed on 22 October 2026 at 15:34 Europe/Rome: Upload succeeded;
package processing. Internal TestFlight only; tester assignment remains manual.
No Store submission or public release.

# NoteNarrate iOS 0.6.2 (20)

Build 20 uses the same functional code as build 19 and enables App Store Connect
distribution so it can be linked to the draft product page. No App Review submission
or automatic public release is requested.

CarPlay: narration starts independently of the popup completion callback; system
Now Playing remains active during narration. Album tracks use numbered lists and
the album catalogue uses larger artwork cards. A bounded in-memory range buffer
prefetches music, and media resolution first tries the connected YouTube account.

Validation for the unchanged code: 87 core tests and 6 simulator UI tests passed.
Release archive, Apple signing and the CarPlay IPA verification passed for build 20.
Real-car audibility and sustained playback with the Premium account still require
vehicle testing. Anonymous playback reproduced a CDN HTTP 403 beyond 1 MiB; buffering
alone does not resolve that restriction.

The Italian Store page is a draft with manual release. Privacy, age rating, content
rights, screenshots and reviewer access remain separate steps before submission.

Apple processing completed on 21 October 2026. Build 20 was selected and saved
on the Italian 0.6.2 Store draft. Reload confirmed the build association and the
NoteNarrate icon in the app header. Status remains Prepare for Submission, with
manual release; no review submission or public release was performed.
