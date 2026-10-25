# NoteNarrate local SDK changes

Source: https://github.com/atpugvaraa/YouTubeSDK
Revision: `fa9bd98bafe98cd8d0918d22382001d10cdbe375`.
Upstream MIT license and copyright are retained in LICENSE; a copy is included
in the app's ThirdPartyNotices.txt. LEGAL_NOTICE.md is preserved unchanged.

The app and Swift package reference this source directory, not a generated
checkout under DerivedData or .build. No remote SDK fork or push is required.

Changed files:

- `YouTubeMusic/Models/YouTubeMusicSection.swift`: normalize nested two-row
  album, playlist and artist renderers before reusing existing model parsers;
  normalize two-row songs through the existing responsive song parser.
  Preserve subtitle, header artwork and More browseId/params.
- `YouTubeMusic/Models/YouTubeMusicHomePage.swift`: add category sections
  without changing the existing initializer's default behavior.
- `YouTubeMusic/YouTubeMusicClient+DiscoveryDecoding.swift` (new): public decoding
  entrypoint for authenticated browse responses. Walk known page envelopes,
  preserve section order, select the active tab, distinguish page continuations
  from carousel continuations, and decode category navigation buttons.

The app's `YouTubeBrowse` owns networking, authentication and account identity,
shared with its existing read-only library transport. SDK networking is bypassed
for these endpoints, avoiding raw authenticated responses in SDK error logs.
No audio extraction, login or lyrics parser has been added or replaced.
Typed search also reuses this transport: the decoder recognizes search page
envelopes and responsive artist/album rows, preserving their browse IDs.

Architecture reference: SimpMusic Android HomeViewModel, HomeScreen,
HomeRepositoryImpl, HomeParser and kotlinYtmusicScraper MoodAndGenres.
Android mood parameters are checked by Scripts/CheckHomeFilters.py.
Focused decoder, state and transport tests live in iosPrototype/Tests.

Library additions (0.8.0): discovery decoding accepts grid continuations and
reloadContinuationItemsCommand envelopes. Optional strictItems decoding rejects
unknown library media instead of silently omitting it, with an explicit exception
for YouTube's Create playlist tile. Home decoding keeps its existing default.
Library endpoints and account writes remain in the app transport; no SDK secrets,
raw authenticated responses or new external dependencies are introduced.
