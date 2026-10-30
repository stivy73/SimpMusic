# NoteNarrate iOS 0.13.4 (40) — radio Your Love e avvio audio

A live progressive probe resolved the exact reference Your Love / Frankie Knuckles:
7 verified songs at 12.75 seconds, 42 at 78.46 seconds. A final single-result queue
was not reproduced on this Mac; device history/session/model can differ.
Code review found that selecting an early track in the current radio cancelled its
background fill. That path now preserves completion; new queues/radios/accounts
still cancel the old request. iPhone and CarPlay show completion progress (X/50).
Catalogue matching now accepts trailing mix/edit/version/remaster labels and checks
actual structured artist credits; exact versions are preferred, wrong artists/live
versions/semantic subtitle mismatches remain rejected. History folds mix labels to
avoid repeating alternate releases of a composition.

33 focused discovery/Gemini tests passed, including real house catalogue examples.
Release device compilation passed with signing disabled. A simulator UI regression
case for track switching was added but cannot run while simulator runtimes remain
unavailable. Release and Debug device compilation passed without signing. These changes are
not yet in TestFlight. Includes the audio-startup optimizations of candidate 39.
Apple API access and Team Admin key creation were explicitly authorized. The key
was saved in the owner-only Downloads/api.txt, preserving its existing content.
Scripts/AppleAPI.py reads only the marked Apple section and supplies a temporary
private-key file to Xcode; no credentials or identifiers are committed to Git.
API cloud signing passed for archives 39 and 40 without an Xcode account session.
Build 40 upload succeeded via API on 30 October 2026 at 14:33 Europe/Rome.
The API workflow also reads TestFlight state without browser login; build 38 was
verified VALID / IN_BETA_TESTING in Stivy73. Build 40 is now VALID /
IN_BETA_TESTING, assigned via API to both Team interno and Stivy73. Existing
Gmail and company testers retained; no new users or automatic distribution added.
No physical Duo or vehicle test is claimed for build 40.

# NoteNarrate iOS 0.13.3 (39)

Avvio audio: blocchi iniziali di 128 KiB invece di 512 KiB; cache in RAM ancora
limitata a 4 MiB (32 blocchi), lettura anticipata e retry invariati. Il primo buffer
preferito passa da 30 a 5 secondi e torna a 30 quando AVPlayer inizia a riprodurre.
Controlli CDN oltre 1 MiB e a fine brano in parallelo, senza rimuoverli; anche i
segmenti HLS iniziale, oltre il minuto e finale vengono verificati in parallelo.
La correzione della durata e la protezione contro il silenzio finale restano attive.

Validation: all 32 targeted audio/range/recovery tests passed after the final
early-failure cancellation adjustment. Xcode 27.2 RC archive succeeded; app and all
extensions are 0.13.3 (39). Distribution export is blocked: Xcode reports No Accounts
and no distribution signing certificate for team 63W2ZKR3Z7. No build 39 upload
was attempted; build 38 remains the latest available until account sign-in.
A dedicated concurrent transport test verifies overlapping boundary/tail checks.
The live Oceanic Delta Waves probe was rejected by anonymous YouTube source
resolution, so no startup timing or >95-second playback result is claimed.
Simulator UI tests could not start: installed simulator runtimes/devices are
unavailable. No runtime was downloaded or phone connection changed. Physical Duo
startup/continuity validation is required. SDK 27.2, deployment target iOS 17.

# NoteNarrate iOS 0.13.2 (38)

Radio progressiva: prima generazione di 8 proposte, pubblicazione dei primi risultati
verificati e completamento in background fino a 50 brani complessivi con il riferimento.
Nessuna motivazione non visualizzata richiesta a Gemini. I brani si aggiungono senza
riavviare il player; nuove radio o cambi di account annullano il lavoro precedente.
Le rimozioni manuali non vengono annullate dagli aggiornamenti successivi. In caso di
fallimento della generazione successiva, i brani già disponibili restano utilizzabili.
Restano deduplicazione e verifica di titolo/artista nel catalogo, senza ID inventati.

Validation: 19 focused core/request tests and 2 simulator UI tests passed. The UI
fixture proves an initial 7-song queue before delayed completion to 50, preserving
the current track; the failure fixture preserves the original queue.
A real anonymous catalogue/Gemini probe produced 4 playable new songs at 10.41 s,
48 total at 61.13 s, without duplicate identities. Results/time vary by model/network;
this is not a device or CarPlay vehicle measurement. The queue can remain shorter
when no more verified candidates are found. SDK 27.2 / Xcode 27.2 RC (27B48), iOS 17.
Release archive and IPA signature/profile checks passed, including CarPlay and all
extensions. Upload succeeded on 29 October 2026 at 22:48 Europe/Rome. Apple
processing completed; build 38 is Testing in Stivy73 (2 testers: Gmail and company
account). No physical Duo/vehicle test for this build. Source commit d00254bb.

# NoteNarrate iOS 0.13.1 (37)

La radio Gemini prepara una coda iniziale di 50 brani, incluso il brano di riferimento.
Richiede fino a 50 proposte per generazione, verifica i risultati reali su YouTube Music,
esclude duplicati e ascolti recenti e tenta fino a tre generazioni per sostituire brani
non disponibili. Le ricerche nel catalogo sono limitate a sei in parallelo. Se il
catalogo non offre abbastanza risultati verificabili, la coda può essere più corta.

Validation: 17 focused Gemini request/radio tests passed. Full core suite encountered
local audio fixture errors and a PCM test process crash; not reported as passing.
App-side MusicModel syntax check passed. Release archive and final IPA passed
CheckCarPlayIPA.py: all bundles 0.13.1 (37), distribution signature, CarPlay,
Siri, Widgets/App Group and Share extension verified. Apple TestFlight upload succeeded on 29 October 2026 at 22:16 Europe/Rome;
processing completed and the build is Testing in internal group Stivy73 (2 testers:
stivy73@gmail.com and michele.stival@archetipi-digitali.it). Device installation
and actual vehicle behavior remain unverified for this build.
SDK 27.2, Xcode 27.2 RC (27B48), minimum iOS 17 unchanged.

# NoteNarrate iOS 0.13.0 (36)

- CarPlay album pages have in-list Next/Previous items; root tabs no longer rely
  on hidden navigation-bar buttons to reach albums after the twelfth item.
- A single YouTube Music liked-song collection replaces local favourites. All
  song hearts write confirmed account likes; album hearts like all album tracks.
  Legacy songs and all tracks from legacy favourite albums import idempotently.
  Pending local selections survive errors/cancellation and bind to the first
  importing account. Library exposes a retry; no unlike is sent by migration.
- Song radio and song-based autoplay use a fresh Gemini generation every time,
  with current-queue/recent-proposal exclusions and real catalogue verification.
  A bounded 200-track history persists across relaunches; alternate IDs/remasters
  are deduplicated. Errors preserve the current queue; no repetitive fallback.
  Explicit artist radio retains its existing YouTube Music path.
- Narration playback gain is 1.3 with sample peak bounds, for cloud streaming,
  existing cached PCM and native system speech. Music/system volume is untouched.
  Native speech now renders through the same PCM output and completion lifecycle.

All app/extension targets: 0.13.0 (36), SDK 27.2 via Xcode 27.2 RC (27B48);
minimum iOS 17 retained. 245 core tests passed. Two real Gemini radio generations
returned 5 and 4 catalogue-verified new tracks, with no cross-request duplicates
(14.62 s and 19.68 s). Nine unique UI scenarios passed on the Duo simulator,
including real CPListItem paging handlers and back from the final partial page,
legacy import, unified likes, album bulk likes, successful/failed radio and both
narration outputs. An old radio test used a removed menu; updated and passed in
the final four-case confirmation run. Final archive and distribution IPA checks
passed for version/build, CarPlay/Siri, Widgets/Share and signatures.
IPA SHA256: `259134aa2998bdaa8bf1a19cf56f718b4038d4d14bc5e32477ebcc7b0b8e83af`.
Matching source `04c871ad` verified on personal dev/feature branches.
Internal TestFlight upload succeeded on 29 October 2026 at 20:55 Europe/Rome,
`Upload succeeded`, `EXPORT SUCCEEDED`, exit 0. App Store Connect independently
completed processing and shows 0.13.0 (36) Ready to Test. No group assigned at
verification; assignment remains manual.
Vehicle rendering/loudness and actual user-account migration remain device checks.
Internal TestFlight delivery only; tester assignment manual.

---

# NoteNarrate iOS 0.12.4 (35)

Replaces full-height portrait CarPlay cards with native album row elements and
square, aspect-preserving artwork. Row capacity follows the platform limit rather
than forcing two cards into a small column. Album tracks remain numbered lists.

Narration publishes a distinct nonseekable Now Playing identity. On completion or
cancellation, music restores its finite duration, actual position and playback rate.
Linear music progress is extrapolated by the system, without periodic metadata resets.

The same authenticated Dreams stream reported 258 s in source metadata but 515.588 s
in AVFoundation on the physical Duo. Native playback now bounds inconsistent padded
container durations to the exact source length plus 0.25 s and retains that duration
for crossfade and Now Playing. Each audio loader gets a unique internal asset URL.
This is a duration correction, not amplitude-based silence removal.

236 core tests and two targeted Duo simulator UI cases passed: finite music clock
restoration after narration and queue advance without waiting for a 120-second
silent tail in a controlled native audio fixture. Release archive and distribution
IPA verified, including CarPlay, Siri, Widgets and Share. All targets use 0.12.4 (35).
Final physical CarPlay rendering/audibility and phone playback remain to be tested.
Source `ad52e20a` pushed and verified on both personal GitHub branches.
Internal TestFlight upload succeeded on 26 October 2026 at 20:37 Europe/Rome:
`Upload succeeded`, `EXPORT SUCCEEDED`, exit 0. App Store Connect independently
completed processing and shows version 0.12.4 build 35 Ready to Test. No group
assigned at verification; tester assignment remains manual.

IPA: `deliveries/NoteNarrate-iOS-0.12.4-build35-CarPlayTiming.ipa`.
SHA256: `1f5b683d36966031689371ac37eda6ef61be19a21dddd25a68cb7295789bc827`.

---

# NoteNarrate iOS 0.12.3 (34)

The player's ellipsis opens the song-options sheet directly in both native Duo
side bars and horizontal layouts. YouTube Music like/unlike is inside that sheet,
next to local likes; it is no longer a separate player/header/overflow action.
Removes Show video from the iOS player and song-options sheet.

Save settings returns to the main Home after successful persistence and resets
any Home navigation history while retaining the music session. A persistence
error keeps Settings open with its existing error message.
All app/extension targets use 0.12.3 (34). Direct development delivery completed;
the same Release source has also been uploaded to internal TestFlight.
Signed build installed and version confirmed on the physical Duo. Functional
checks passed for direct options, account-like placement, no video, Close/Back/
swipe and Save returning Home with existing settings. Targeted simulator cases
passed on Duo and iPhone 18 Pro; see IPHONE_DUO.md for logs and test-runner limits.

Release archive and exported IPA verified: Apple distribution signing, CarPlay
Audio, Siri and example phrases, Widgets/Share App Groups. Matching source
`69e6b283` verified on personal `dev` and `feature/youtube-library-albums`.
IPA: `deliveries/NoteNarrate-iOS-0.12.3-build34-DuoMenuSettings.ipa`.
SHA256: `a190c050b99eba9d949e2dc2c4c3c65a00b3cccf1ba1794f38f3e8817d2af6d4`.
Internal TestFlight upload succeeded on 26 October 2026 at 16:30 (Europe/Rome):
`Upload succeeded`, `EXPORT SUCCEEDED`, exit 0. App Store Connect independently
completed processing and shows version 0.12.3 build 34 Ready to Test. No group
is assigned at verification; assignment to Team interno remains manual.

---

# NoteNarrate iOS 0.12.2 (33)

Restores native Duo navigation and player toolbars by removing clipping from the
retained navigation containers. Uses Apple's vertical toolbar edge, item axis and
compression policies instead of identifying a device by model or orientation.
Back has cancellation-action placement and returns to the previous tab. Library,
lyrics, interpretation and queue use the system side bar in vertical layouts;
additional song actions/video are available from the native overflow menu.
Horizontal layouts retain the existing inline player actions.

Adds an interactive leading-edge swipe to minimize the retained player, respecting
layout direction and Reduce Motion. Short gestures cancel. Sliders and lyric
scrolling remain independent; playback, position and queue are retained.
Song-options Close clears its presenting item in both player and album, and
uses a symbol in the system cancellation position. Accessibility seek adjustments
outside touch-edit sessions now reach the player immediately.
Development delivery to the connected Duo; no new TestFlight upload in this change.
Physical-device UI test passed for song-menu Close, Back and edge-swipe dismissal,
with the existing account/session and preserved playback state. Simulator checks
passed for side-bar geometry, lyrics/queue access, nested album-menu Close after
rotation, seek/short-swipe cancellation and audio continuity through minimization.
See IPHONE_DUO.md for actual validation and remaining physical-device limits.

---

# NoteNarrate iOS 0.12.1 (32)

Adds animated word fill and line following driven by actual playback time, without
increasing the global player publication rate. Manual browsing suspends following;
Follow lyrics and tapping a line resume it. Word-level timing requires real Enhanced
LRC/TTML timestamps. Line-only/plain lyrics are not assigned fabricated word timing;
Reduce Motion uses immediate highlighting and nonanimated positioning.

Adds local WEB_REMIX s/n decoding based on the Android Faraday registry and the
public YouTube player, with cached public metadata and a disposable network-disabled
WebKit worker. No account cookies, video IDs or media URLs are sent to the registry.
Signed query bytes are preserved when constructing CDN Range requests. Both account
and public AAC candidates must pass beginning, 1 MiB boundary and tail validation;
HLS validates the actual audio playlist and early/post-minute/final segment prefixes.
A prefix-only stream is not accepted as a complete playable source.

Native playback can recover twice per queue occurrence after CDN rejection, item
failure or a measured stall, excluding failed sources and preserving position and
pause/narration intent. Diagnosis now records sanitized account and public stages
rather than retaining the previous track's status when source resolution fails.

231 core tests and five simulator scenarios passed: karaoke/manual follow/seek, real AVPlayer item
replacement and position restoration, synchronized lyrics/sleep timer, minimization,
and streaming TTS interruption/completion with music resumption. The latter use
validated local audio fixtures and do not establish live CDN or vehicle behavior.
Live public AVPlayer probe: 98.0 seconds of progress, zero stalled samples, all
3,449,447 AAC bytes readable. Another public track still rejects CDN access after
1 MiB and is rejected by validation; no universal playback claim. Premium phone
continuity and CarPlay audibility still require physical verification.
All targets use 0.12.1 (32); distribution remains internal TestFlight, testers manual.

Release archive and exported IPA verified: distribution signatures/profiles,
CarPlay Audio, Siri/vocabulary, Widgets and Share App Groups. Source `bfea9a9e`
pushed and verified on both personal branches. IPA SHA256:
`70e1ec9938f5e38e36df18942cbbcf02a936be98593f1328451477b0c9138775`.
Internal TestFlight upload succeeded on 26 October 2026 at 13:57 (Europe/Rome)
using the Archetipi Digitali team. Xcode confirmed `Upload succeeded` and
`EXPORT SUCCEEDED`; Apple reported that the uploaded package was processing.
Tester availability is not yet verified; group assignment remains manual and
no public App Store submission was performed.

---

# NoteNarrate iOS 0.12.0 (31)

Adds the Android-like player action sheet: local likes, playlist picker, Play next,
Add to queue, artists, album, radio and sharing, with artwork/title and accessible
icons. Existing download/account-like/manual-lyrics/video actions remain available.
All credited artists retain their catalogue IDs; old tracks without IDs use a
filtered catalogue lookup instead of guessed destinations.

Replaces the basic album song list with a large-artwork page, title/artist/year,
Play/Pause, shuffle, complete album download, optional description, duration/count,
numbered tracks and per-track menus. Local album favourites persist and appear in
Library. Album queue and share actions are available from its menu.

Phone and CarPlay use the same authenticated complete album loader, excluding
recommendation carousels and preserving album metadata, track order and repeated
occurrences. Fixes the CarPlay artist Radio action being overwritten by rendering
or pagination. No audio-pipeline, AI prompt, API key or entitlement changes.

199 core tests passed, four new UI scenarios passed, plus player/lyrics and CarPlay
regression checks. Public catalogue proof: Tracy Chapman (1988), 11 tracks,
2175 seconds and artwork. Vehicle audibility and Premium playback beyond a minute
remain separate physical tests; no claim of resolution. Template UI source review
is distinguished from iPhone simulator tests in CARPLAY.md.
All targets use 0.12.0 (31). Apple distribution signatures/profiles verified:
CarPlay Audio, Siri/vocabulary, Widgets and Share App Group. Internal TestFlight
upload succeeded on 26 October 2026 at 10:09 Europe/Rome (package processing,
EXPORT SUCCEEDED, exit 0). Matching source `ac7fe9ff` pushed and verified on both
personal branches. Tester assignment manual; no public App Store submission.
Local IPA SHA256: 90b0033d9972645e42b857762ff3043e0fbd0cccc506f4aa0d0d87a77633633f.

---

# NoteNarrate iOS 0.11.0 (30)

Ports parity points 27 and 35. A native iOS Share extension accepts YouTube/YouTube
Music links and song search text, including Android-compatible Now Playing formats.
Preview/edit before saving; validated requests are stored atomically in a bounded
App Group inbox. Opening NoteNarrate presents the newest pending item; Library →
Received keeps the other requests available. Video links resolve exact catalogue
IDs with title/artwork, and can be played or queued; text opens typed song search.
Share extensions cannot guarantee launching the containing app, so the UI explains
the explicit open-app step. No responder-chain/private-API launch workaround.

Library albums, saved/liked songs, playlists, followed artists, local favourites
and offline downloads support per-collection list/grid, natural title/artist order,
reverse order and an alphabet jump bar. Choices persist locally. Remote collections
and album track order are not mutated. Existing download states/actions are retained.

All iOS targets use 0.11.0 (30). 189 core tests passed; four unique UI scenarios
passed (list/index/relaunch, actual text share/cold launch/search, actual URL
share/exact-track player, offline/verse-image regression). YouTube metadata HTTP
200 verified live. Release archive and shared Mac build succeeded.
Apple distribution signing verified, including CarPlay Audio, Siri, WidgetKit and
the Share extension with its App Group. Internal TestFlight upload succeeded on
26 October 2026 at 09:14 Europe/Rome: Upload succeeded, package processing,
EXPORT SUCCEEDED, exit 0. Source a50a3e51 pushed/verified on both personal branches.
Tester assignment manual. No public App Store submission.
Exported IPA SHA256: 852eb6cd9b70e47dc1b5d5436d25ce1c1bafbb72d071ee26e78bf08486919823.

---

# NoteNarrate iOS 0.10.0 (29)

Implements parity points 20, 22, 23 and 25: three WidgetKit widgets (interactive
player, playlist shortcuts, actual listening insights) with shared display-only
App Group snapshots; dedicated country-filtered Charts, current Podcasts Home
filter/show search/episode renderer and authenticated personal Mix; confirmed
YouTube artist subscriptions plus opt-in release polling, baseline/deduplication,
account-scoped inbox and local notifications; Gemini music recommendations using
the existing key with optional current-track context, Italian explanations and
verified YouTube Music catalog matches before play/queue/private-playlist actions.

No historical-alert burst on first sync. Background refresh is opportunistic, not
server push or an exact six-hour promise. Widget timelines are system-budgeted.
No keys/cookies/signed media URLs enter the App Group. Unresolved AI suggestions
are not playable. Android prompt/Home/search filters stay unchanged. Points 21
and 24 are not included. Physical Duo/CarPlay narration/CDN testing remains deferred.

Adds localized AppIntentVocabulary.plist in the main app only (Base/it/en), with
examples for both declared Siri media intents. The final IPA gate checks every
intent/locale to address ITMS-90626 reported by Apple on 0.8.1 (25).

179 core tests and three final simulator scenarios passed, including actual Home
widget pause/play and release baseline/new notice. Real IT/global Charts and
Podcast episode continuation verified. Live Gemini: 8 structured suggestions,
7 verified catalog matches; unresolved candidates remain excluded from playback.
Release archive and shared Mac compilation succeeded. Apple distribution signing
verified: CarPlay Audio, Siri, localized phrases and App Group in both app/widget
signatures and profiles. App and both extensions match 0.10.0 (29).
Uploaded to Apple on 26 October 2026 at 08:19 Europe/Rome: Upload succeeded,
package processing, EXPORT SUCCEEDED, exit 0. Source 4357622a pushed and verified
on both personal branches. Exported IPA SHA256:
005df0b7445db2e09615d7a72e24e01ab338c2e1d2f06e877c246bedc569d267.
Internal TestFlight only, manual testers, no public submission.

---

# NoteNarrate iOS 0.9.0 (28)

Implements iOS parity points 10–19: persistent AAC music downloads with background
transfers, quota and full-file verification; offline collection and CarPlay access;
line/word LRC and TTML lyrics, timing offset and seek; sleep timer; paused queue/order/
position restoration; separate Wi-Fi/cellular/download AAC quality preferences;
ten-band PCM EQ, presets, AutoEq catalog/import, headroom, delay and reverb; opt-in
0–12 second two-deck crossfade and DJ gain/filter sweeps; alternative lyrics providers,
local romanization, line-aligned cached Gemini translation and verse image sharing;
actual local listening history/rankings and monthly/yearly shareable recaps.

Preserves the Android interpretation prompt and Home/search server filters. No API
keys, cookies or signed streaming URLs enter session/download manifests or Git.
Background downloads verify byte count, audio packets/duration and final quota before
committing a playable file. An interrupted/rejected file is never certified offline.
HLS downloads and CDN 403 remediation are outside this implementation. DJ does not
perform beat matching; unknown/unready next streams retain ordinary track advance.
Spotify requires personal valid web tokens and has not been tested with a live account.
The shared Mac build is a compilation check, not Mac offline/DSP runtime proof.

163 core tests and six feature UI scenarios passed, plus the search pagination/queue
regression. Live public lyrics/AutoEq probe succeeded. Release iOS archive and shared
Mac compilation succeeded; exported IPA verifies Apple signature, CarPlay Audio and
Siri app/extension profiles. Uploaded to Apple on 25 October 2026 at 22:35 Europe/Rome:
Upload succeeded, package processing, export exit 0. Source commit 9fea26af was pushed
and verified on both personal fork branches before upload. Tester assignment remains
manual; no public App Store submission. Physical-car narration and long YouTube CDN playback remain
reserved for the separate Duo test, regardless of local-file simulator results.

---

# NoteNarrate iOS 0.8.3 (27)

Phone search parity (point 9): All plus songs, artists, albums, YouTube Music
playlists, community playlists, videos and podcast shows. Categories use the same
seven server filters as Android. All loads them concurrently and displays early
results without waiting for slower sources; per-category errors/retry preserve
successful sections. Each category supports full results and continuation pages.

Uses the confirmed account/visitor and search endpoint for every page, including
delegated accounts. Query/filter/account changes invalidate prior results and
pending continuations. Duplicate results and repeated tokens are handled. Native
navigation opens album, artist and playlist details; playable results share the
current queue/radio/like/playlist actions. Video stays opt-in in the existing player.
Local query history is limited to 20 and can be removed individually or cleared.
The phone search does not overwrite Siri/CarPlay queries or expand its vehicle filters.

The local SDK preserves filtered search shelf continuations beside server headers
without changing Home continuation rules. Podcast shows retain their browse IDs.
Anonymous live probe validates all seven categories and second pages for six of
them (artist query had 15 complete results). All seven Android filter params,
interpretation prompt and Home filter params remain identical. 142 core tests pass.
Three simulator UI scenarios passed: filter/pagination through an eight-item
playback queue, album/artist/playlist navigation, partial failure and history deletion.
A native category menu and automatic chip scrolling keep all filters reachable on
narrow displays. Release iOS archive and shared Mac compilation succeeded. Internal
TestFlight upload completed on 25 October 2026 at 21:16 Europe/Rome: Upload succeeded,
package processing, export exit 0. Build source: 2eb8818b, pushed to both personal
fork branches. Tester assignment remains manual; no App Store submission. Final
IPA verifies Apple signature and CarPlay Audio/Siri profiles for app and extension.
No live account mutation or physical-car audio claim is made by these search tests.

---

# NoteNarrate iOS 0.8.2 (26)

Radio and autoplay (iOS parity point 8): start a song radio from track/player
menus or an artist radio from its page and linked artist action. The authenticated
WEB_REMIX next transport preserves video/playlist/params/index, account identity
and continuation context. Artist radio uses the server's actual radio endpoint;
automix pointers follow Android's flow with bounded cycle protection.

Autoplay is enabled by default and can be changed in Settings, Queue or CarPlay.
The final manual track prefetches recommendations into a buffer. They are appended
only after the existing queue is consumed; repeat one/all takes precedence.
Queue entries and unavailable/duplicate suggestions are filtered. Requests are
cancelled/invalidated on context or account changes. A pause during delayed
preparation prevents playback from restarting. Explicit radio errors preserve
the current queue, and retry does not skip a song. iOS preparation has a bounded
background task. CarPlay exposes radio and autoplay in the shared queue and a
Radio action on artist pages, preserving the existing Now Playing buttons.

Live anonymous catalog probe: song radio 50 tracks, continuation 49 tracks,
artist radio 50 tracks. Core tests: 129 passed. Simulator UI scenarios cover
successful and rejected radio, continuation after the manual queue, disabled
autoplay and pause during a pending request. No physical-car/Premium-audio
runtime proof is implied; existing CDN/narration defects remain deferred.

Uploaded to Apple on 25 October 2026 at 20:47 Europe/Rome for internal TestFlight:
Upload succeeded, package processing, export exit 0. Build source: a3c6bbab.
Apple signature, CarPlay Audio and Siri profiles/signatures verified in app and
media intent extension. Tester assignment remains manual; no App Store submission.

---

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
