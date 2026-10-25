# NoteNarrate iOS 0.8.1 (25)

Uploaded to Apple on 25 October 2026 for internal TestFlight: Upload succeeded,
package processing. Tester assignment remains manual. Build source: 267fb837.

Playback queue editing: reorder by drag, remove by swipe/menu, Play next and
Add to queue from search, discovery, library, playlist tracks and player menu.
Queue occurrences have stable IDs, so repeated songs remain independently editable.
Edits to noncurrent items preserve playback and the current occurrence. Removing
the current entry selects its successor (or its predecessor at the end), preserving
paused intent. Removing the final entry cancels loading, stops audio/narration and
clears the player. The queue is session state, distinct from saved playlists.

Shuffle/repeat from build24 were checked first. Queue edits preserve shuffled
history without reshuffling; explicit drag order becomes the canonical order.
CarPlay has the system Up Next entry point and a paginated shared queue, with
Play, Play next and Remove actions. Its callback dispatches to the main actor.

Core validation: 121 tests passed, including duplicate occurrences, current-index
remapping, manual moves, mixed edits, append/play-next and repeat boundaries.
Four unique UI scenarios passed (five test executions across two runs), including
actual reorder geometry and final-entry removal. Apple signature and CarPlay/Siri
profiles verified; details in VERIFICATION.md.
Real vehicle audio/CDN defects remain outside this change as agreed with the user.

---

# NoteNarrate iOS 0.8.0 (24)

Uploaded to Apple on 25 October 2026 for internal TestFlight: Upload succeeded,
package processing. Tester assignment remains manual. Build source: bc23b4b1.

Library now includes remote saved songs, account likes, library playlists and
subscribed artists alongside saved albums. Collections follow every continuation,
deduplicate media IDs and reject repeated tokens or unrecognized media instead
of treating a partial result as a complete library. Account changes clear all
remote state and reject late responses, including reconnecting to the same account.

The player thumbs-up button and song context menus now rate songs on the confirmed
YouTube Music session, using the same authenticated like/like and like/removelike
endpoints as Android. UI changes follow server success; failed writes preserve
existing state and show an actionable error. Local favorites remain an independent
collection, accessible from the player menu; no local favorites are uploaded.
Saved library songs and liked songs also remain separate YouTube collections.

Validation: 114 core tests and four simulator UI tests passed. Apple signing,
CarPlay Audio and Siri profiles/signatures verified; see VERIFICATION.md. Network tests
validate delegated account/auth headers, correct mutation endpoints and rejected
HTTP-200 responses. UI tests use isolated debug fixtures, not a live Google account.
A real-account synchronization test on the user's Duo is still required.
No changes to music CDN playback or narration routing in this build.
Owned playlists support private creation, renaming, deletion with confirmation,
adding/removing songs and reordering exact playlist occurrences. Read-only lists
cannot be edited. Duplicate songs retain their setVideoId across pagination.
Shuffle and off/all/one repeat share one index-based sequence with the player,
queue, CarPlay and system remote commands. Manual Next differs from natural end
when repeating one song.

CarPlay search now originates through Siri media intents and an assistant cell,
with a background Intents extension and typed song/artist/album results. It no
longer depends on the phone's last query. The app keeps its Audio entitlement;
CPSearchTemplate is Navigation-only and no ungranted entitlement is spoofed.
Siri recognition, routing and live Google playlist writes require physical-device
validation. Follow/unfollow and further Android parity work are separate.

---

# NoteNarrate iOS 0.7.2 (23)

CarPlay keeps the current song playing while lyrics, interpretation and cloud
voice are prepared. It pauses music only when the first narration audio is
available (or immediately before native speech starts), then resumes afterward.
This avoids dropping active background music before asynchronous preparation.
No silent keepalive audio or extra background mode is introduced.

PCM playback waits for a valid output render clock before starting the player
node, with a bounded timeout/cancellation. iOS/macOS 27 use Apple's throwing
playAudio API instead of the legacy Objective-C exception path. Audio-session
interruptions and route disconnections now leave a specific voice diagnostic.

The diagnostics share includes version/build and the reason the authenticated
media source was rejected before public fallback. No cookies, keys or signed
URLs are included. This is necessary to diagnose the unresolved Premium path.

Validation: 90 core tests passed, including PCM playback. Native and streaming
CarPlay background UI checks passed; the streaming test adds a 20-second
preparation delay and asserts music continues while waiting for audio. These
checks do not establish physical-car audibility.

The music stop after approximately a minute remains unresolved: the anonymous
CDN source reproduced HTTP 403 beyond 1 MiB, including full-transfer attempts.
Alternative client probes required login or returned unplayable media. A live
Premium-account test was unavailable because the probe had no existing Keychain
access; no credential access permission was changed. A new vehicle diagnostic is
required to distinguish rejected login, malformed metadata and unavailable media.
Do not describe this build as a CDN fix. Existing interpretation prompt,
search filters and Duo layout are unchanged. No public Store release requested.

Apple upload completed on 24 October 2026: Upload succeeded, package processing.
Build 23 is internal TestFlight only; tester assignment remains manual.

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
