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
