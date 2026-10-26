# iOS animated lyrics and audio recovery — 0.12.1 (32)

- Animated word progress follows actual media time; scrolling follows active lines,
  pauses for user browsing and resumes explicitly. Timing is never fabricated.
- WEB_REMIX account/public responses support local s/n decoding and retain exact
  signed query bytes. Decoder registry receives only public metadata requests.
- Validate AAC at start, 1 MiB and tail; HLS checks audio rendition and segment
  access. Same-occurrence AVPlayer recovery preserves seek, pause and TTS intent.
- Sanitized account/public diagnostics remain current even if resolution fails.
- 231 core tests and five simulator UI checks passed; a public live source ran
  for 98 seconds without stalls. Another public CDN source remains rejected.
  Live Premium phone/CarPlay proof is separate;
  see CARPLAY.md. No public App Store submission; testers remain manual.

---

# iOS player/album parity and CarPlay audit — 0.12.0 (31)

| Area | Implementation | Validation |
|---|---|---|
| Player menu | Artwork/title; local liked songs; existing account playlist picker; Play next and Add queue; artist chooser; real album/artist catalogue fallback; radio; native sharing | UI menu/playlist/queue and artist routing; account writes remain in the existing confirmed transport |
| Album | Large artwork, title/artist/year, Play/Pause, shuffle, validated album download, numbered track rows with durations and the same song menu; description, queue/share actions | Live Tracy Chapman 1988 album: 11 tracks, 2175 seconds, artwork; UI track selection, shuffle, verified local offline files |
| Album favourites | Persistent local metadata and Library collection with existing list/grid/sort/index tools | Favourite/unfavourite and relaunch UI proof; Codable metadata round-trip |
| Shared CarPlay data | Complete authenticated album pages, own track shelves only, artwork/album context, all artist IDs, exact occurrence index | Header and track decoding, pagination, repeated token/failure rejection, unrelated carousel exclusion tests |
| CarPlay audit | Existing tab/search/player/queue/media commands reviewed; artist Radio action preserved after data/page changes | Initial eight simulator scenarios passed; candidate streaming/minimization and rejected-presentation confirmation passed. Actual external-display templates were source-reviewed, not driven in Simulator.app |

199 core tests passed. Four new UI scenarios passed across the initial and final
confirmation runs. The live playback/lyrics regression also passed after fixing
an obsolete test assumption about missing lyrics in the next recording. A live
YouTube startup timeout occurred before the rejected-presentation test reached
CarPlay; that cancellation scenario was confirmed with a validated local file.
Physical narration audibility and Premium CDN continuity remain deferred.
No new backend, login, provider key, entitlement or external dependency.
All app/extension targets use 0.12.0 (31). Apple distribution IPA gate passed,
including CarPlay/Siri and app/extension App Groups. Internal TestFlight upload
succeeded on 26 October 2026 at 10:09 Europe/Rome; Apple reported package
processing, export exited 0. Source `ac7fe9ff` verified on both personal branches.
Tester assignment manual; no public App Store submission.

---

# iOS parity: points 27 and 35 — 0.11.0 (30)

| Point | Implementation | Validation |
|---|---|---|
| 27 | iOS Share extension: YouTube/Music video and playlist links; editable title/artist search text including Now Playing; bounded shared inbox, cold launch receipt, exact video metadata/play/queue | Parser, malformed URL, atomic persistence/bounds tests; actual share sheet and extension UI scenarios |
| 35 | Per-collection list/grid; natural title/artist/reverse/original sorting; accented/numeric/non-Latin alphabet index; persistent choices; offline status/actions preserved | Sorting/index/preference tests; actual alphabet jump and relaunch, collection isolation, offline regression |

Use Condividi → NoteNarrate → Aggiungi a NoteNarrate, then open the app. Pending
items are also under Library → Ricevuti. Only sanitized catalogue IDs/search text
enter the existing App Group, without source tracking URLs or credentials.
Unsupported service links need title/artist text or manual editing. A Share extension
cannot guarantee launching its containing app; no unsupported launch API is used.

Display controls are in the collection toolbar; the alphabet uses the current title
or artist sort. It does not reorder server data or album tracks. Physical CarPlay
narration/Premium CDN tests remain separate. 189 core tests passed. Four unique UI scenarios passed across final/confirmation
runs; the confirmation run passed both collection/relaunch and actual text share
with cold launch. Direct URL share and offline regression also passed. An initial
UI selector failure was corrected to use share-sheet cells/menu labels; the index
retry exposes off-screen letters before querying hittability.
Release archive and shared Mac compilation succeeded. Distribution signatures,
CarPlay/Siri/WidgetKit and Share App Group profiles verified. Internal TestFlight
upload succeeded on 26 October 2026 at 09:14 Europe/Rome; Apple reported package
processing, export exited 0. Source `a50a3e51` on both personal branches; testers manual.

---

# iOS parity: points 20, 22, 23, 25 — 0.10.0 (29)

| Point | Implementation | Validation |
|---|---|---|
| 20 | WidgetKit Player (play/pause/next), Playlist shortcuts, actual listening statistics; App Group display snapshots and strict deep links | Shared-state/route tests; embedded extension and interactive app intents; distribution signature gate checks both App Group profiles |
| 22 | Dedicated Charts with country, Podcasts with show search and playable episodes, account-personalized Mix | Real IT/global chart and podcast catalog probes; country/account/pagination tests and simulator navigation |
| 23 | Confirmed YouTube artist follow/unfollow; opt-in release monitoring, local inbox and iOS alerts | Baseline/dedup/account/persistence/failure tests; simulator baseline and subsequent-new-release scenario |
| 25 | Gemini music recommendations using the existing key, optional current-track seed, Italian reasons, real catalog resolution, play/queue/private playlist actions | Structured-response transport and matching/cancellation tests; simulator generation-to-player flow |

Validation: **179 core tests passed** and three final simulator scenarios passed:
dedicated discovery/AI-to-player; release baseline/new notice; actual Home widget
pause/play against the retained native player. Public catalog probe: IT Charts
43 items, global 42; Podcasts 30 items and 23 on continuation (server-dependent).
Live Gemini probe: 8 structured suggestions in 17.59 s, 7 verified catalog matches.

Delivery: Apple distribution signatures/profiles verified for CarPlay Audio, Siri
and the shared app/widget App Group. App and extensions match 0.10.0 (29).
Internal TestFlight upload succeeded on 26 October 2026 at 08:19 Europe/Rome;
Apple reported package processing, export exited 0. Release source `4357622a`
is on both personal GitHub branches. Tester assignment remains manual.

Also corrects the Apple ITMS-90626 Siri vocabulary warning reported for build 25:
Base/Italian/English example phrases for every declared media intent in the main
app bundle; exported-IPA validation covers the locale/intent matrix.

Use **Home → Esplora** or **Impostazioni → Scopri**. Widgets are added from the
iOS Home screen. Open Library → Playlist to populate the playlist widget.
New-release notifications are opt-in; the first successful check of each artist
seeds a baseline without historical notifications. iOS schedules background checks
opportunistically (requested no sooner than six hours), with foreground catch-up
and an explicit Check now action. No server push service or fixed schedule is promised.

Widgets share display metadata and compressed cover files only, never API keys,
cookies or signed streaming URLs. Interactive media actions use AudioPlaybackIntent
in the app process. Timeline refreshes remain under iOS control.

Podcasts use YouTube Music's live Home chip and its multi-row episode renderer.
Mix requires the confirmed account. AI never supplies playable video IDs; unresolved
recommendations stay visible and cannot enter a queue or playlist. Only the request
and explicitly selected reference metadata are sent to Gemini.

No changes to Android, account multi-switching (21), Spotify playlist import (24),
or the physical-car/Duo tests (1–2). Live Premium CDN continuity and physical CarPlay
voice audibility remain deferred. No public App Store submission; testers manual.

Build, upload and source commit status are recorded in README and RELEASE_NOTES.

---

# iOS parity work: points 10–19 — 0.9.0 (28)

User-authorized sequence after 0.8.3 (27). All ten features below are implemented.
Local validation does not certify physical Duo/CarPlay audio: points 1–2 remain
separate and deferred. Every TestFlight upload has matching source/version/build
on the personal GitHub branches; tester assignment stays manual.

| Point | Implementation | Evidence |
|---|---|---|
| 10 | Two background AAC downloads, Wi-Fi/quota settings, complete-file validation, offline library and CarPlay entry | Full/missing/truncated file, HTTP/range, duration and quota tests; native local file plays past 65 s while minimizing/reopening |
| 11 | LRC lines, enhanced LRC/TTML words, scrolling, offset, tap to seek | Parser/offset/word tests; simulator seek by lyric |
| 12 | Absolute-deadline timer or stop at track end; also stops narration | Deadline/end core tests; native short timer pauses audio |
| 13 | Queue UUIDs/order/shuffle/repeat/position restored paused, lazy stream loading | Round-trip/corruption tests; cold relaunch keeps queue and position paused |
| 14 | Separate AAC quality for Wi-Fi, cellular and downloads | Actual-source ordering tests; settings UI |
| 15 | Ten-band PCM EQ, presets/headroom, delay/reverb, AutoEq catalog and FixedBand import | Frequency/channel/impulse/profile tests; native tap processed frames; live 8,850-entry catalog and valid ten-band profile |
| 16 | Opt-in 0–12 s two-deck crossfade; DJ curve and high/low-pass sweeps | Equal-power and spectral tests; native early promotion counter and pause cancels outgoing audio |
| 17 | Additional lyrics providers, saved/manual LRC, romanization, cached Gemini line translation, verse PNG | Provider/TTML/translation tests; live SimpMusic 35 synchronized lines and Better Lyrics 31; verse-image UI |
| 18 | Local actual-playtime ledger, rankings, periods and deletion | Seeks/pauses/short tracks/persistence/empty-period tests; analytics UI |
| 19 | Monthly/yearly actual-data recaps, text/PNG sharing | Period tests; simulator recap image generated and visually inspected |

Validation: **163 core tests passed**. Android interpretation prompt, ten Home
filters and seven search filters are unchanged. Simulator scenarios cover native
local audio >65 s, minimize/reopen, crossfade/cancellation, lyrics seek + timer,
paused restoration, audio settings + recap, verse image + offline access. Search
pagination/queue regression passed. Local result bundle paths are in VERIFICATION.md.
Public catalog probe: `NetworkProbe --lyrics-catalog`, no credentials or lyric text
logged. Release archive/signature/upload status is in README and RELEASE_NOTES.

## Explicit boundaries

- Downloads require complete progressive AAC. HLS is streaming only; CDN 403/partial
  files never count as offline. Retry resolves a fresh URL and restarts the transfer.
- Effects process iOS music PCM, not video or narration. Some HLS variants do not
  expose a processing tap. Crossfade needs a prepared next queue item; otherwise
  ordinary advance remains. DJ provides volume/filter sweeps, not BPM/key matching.
- Word timing must exist in the provider/file. Gemini translates existing rows,
  never invents lyrics/timestamps. Spotify token transport requires personal valid
  web tokens in Keychain and has not been checked with a real Spotify account.
- Statistics start with this version's recorded playback. No inferred genres,
  invented listening history, remote import or backfilled Wrapped. Data stays local.
- Shared Mac compilation is verified, not Mac offline/DSP/crossfade runtime parity.
  Live Premium CDN continuity and narration audibility in a physical car remain the
  distinct Duo/CarPlay tests postponed by the user.

Delivery: Apple upload succeeded on 25 October 2026 at 22:35 Europe/Rome, package
processing, command exit 0. Source `9fea26af62a608a859f3be99f73cd9fd0655387b`
pushed and verified on personal `dev` and `feature/youtube-library-albums` before upload.
IPA Apple/CarPlay/Siri verification passed; tester assignment manual.
