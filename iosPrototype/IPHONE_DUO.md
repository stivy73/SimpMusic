# NoteNarrate iOS: iPhone Duo

## 0.12.2 (33) — native controls, Back and edge swipe

The root and retained player no longer clip their native navigation containers.
On Duo, the system draws tab/toolbar controls in a safe-area region outside the
content bounds; the old clipping hid them even though the app used native bars.
Artwork alone remains clipped. The player is retained and minimizes with the
existing animation, so navigation does not replace its media session.

The player reads `toolbarVerticalEdge` inside NavigationStack. In a vertical bar,
Back uses cancellation-action placement, Library stays a separate destination,
and lyrics, interpretation and queue use symbol actions. Native overflow keeps
song options, account-like and optional video accessible. Axis and compression
preferences preserve the most useful controls; the inner portrait layout retains
normal horizontal controls. No device-model or orientation check decides this.

The iOS player also supports an interactive swipe from the leading 20 pt edge.
It mirrors for right-to-left layout, cancels short gestures and minimizes to the
previous screen when completed. The touch region excludes the content's sliders;
vertical lyric scrolling and sheet gestures retain their own behavior. Motion
preferences and the accessibility escape action are respected.

Song-options Close clears the exact presenting item in the player or album,
rather than relying solely on an environment dismiss action. Its symbol uses
the system cancellation position. Nested album navigation remains open when
closing that album's track menu. Seek changes made outside touch-edit sessions
(including accessibility adjustments) now apply immediately rather than being lost.

### Validation on 26 October 2026

- Duo simulator: native side alignment/reachability, Back returning to the previous
  tab, lyrics and queue sheets, minimization with ongoing local audio passed.
- Duo simulator: completed edge swipe, cancelled short swipe, seek control and
  retained playback/position passed. The first seek check exposed an accessibility
  adjustment that did not reach the player; this is corrected in the final source.
- Duo simulator: Close, reopen and a nested album's track-menu Close passed,
  including a rotation before closing the nested sheet.
- iPhone 18 Pro simulator, iOS 27.0: karaoke/follow/seek and minimization across
  tabs passed with horizontal controls.
- Signed development build 0.12.2 (33) installed on the connected Duo, iOS 27.1.
  Physical Home in landscape now shows native side controls; the inner portrait
  player shows artwork, Back and the horizontal controls.
- Final physical-device functional test passed: opens the actual song menu,
  closes it, returns to the mini-player with Back, reopens the player and completes
  the edge swipe. Playback state is preserved. This test uses the existing account
  and session; it does not install fixtures or start new audio.
- The final signed app was explicitly installed before the physical test; merely
  activating an existing process can leave an older binary running. All four app/
  extension bundles are 0.12.2 (33), built with `iphoneos27.1`; signature check passed.

These UI checks do not establish live Premium CDN continuity or CarPlay audibility,
nor certify every hinge angle, Split View size or accessibility configuration.
Latest internal TestFlight upload remains 0.12.1 (32); this is direct device delivery.

Local evidence: `/tmp/notenarrate33-duo-ui.xcresult` (side bars/minimization),
`/tmp/notenarrate33-duo-close-swipe.xcresult` (edge swipe/seek passed; an initial
native-overflow test selector was corrected), `/tmp/notenarrate33-duo-close-confirm.xcresult`
(menu close and nested album), `/tmp/notenarrate33-iphone-ui.xcresult` (horizontal
iPhone), `/tmp/notenarrate33-physical-final.xcresult` (one physical test passed).
Final device app: `/tmp/NoteNarrate33-Duo/Build/Products/Debug-iphoneos/StivySimpMusic.app`.

The separate local Mac target could not complete an additional build because it
does not register pre-existing shared AlbumScreen/SongOptionsSheet/player-decoder
sources. That target is not part of this iOS delivery; no Mac package was produced.

Apple guidance: [Raise the bar with iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111462/),
[Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo).

## Original adaptation — 0.7.0 (21)

The same app adapts to the available window rather than identifying a device by
screen size, idiom or orientation. Built with the iOS 27.1 SDK; iOS 17 remains the
minimum supported version. The existing player, queue, account and narration
models remain shared across layout changes. No new API key or login is required.

## Interface

- Native TabView accessory for the mini-player on iOS 26.1 and newer. The system
  controls bar placement on Duo; older systems keep the existing per-tab inset.
- On sufficiently wide iOS 27.1 windows, a native ArrangementView separates the
  current player and lyrics, adapting its panes to reserved fold regions. On
  narrow windows the player retains its lyric toggle and all actions.
- Player content measures its own available pane. Two-column media/controls need
  enough width and height; short or narrow windows use scrolling content.
- Main album artwork fits without cropping. Decorative backgrounds alone extend
  outside safe areas. Artwork, text and controls retain their proper insets.
- Title and actions can wrap into two rows; action targets are at least 44 pt.
  Native toolbar items provide both symbols and titles for vertical presentation.
- The library uses flexible columns and prefers even counts when more than two
  columns fit. It does not assume that regular size class means iPad.
- The Mac embedded WebKit player stays in its original stable view hierarchy.

## Apple audit

| Area | Result |
| --- | --- |
| Launch screen | Generated by the existing build setting |
| iPad orientations | All four declared |
| Full-screen opt-out | Not present |
| Main screen, idiom and orientation layout checks | None in App/Core |
| Hidden player offset | Uses the retained container height, not global insets |
| Scene lifecycle | SwiftUI scenes and existing CarPlay scene configuration retained |
| UIApplication background tasks and open URL | Preserved; these are not geometry APIs |

Files reviewed and updated: StivyApp.swift, HomeView.swift and LibraryView.swift.
The native media and interpretation services are unchanged. UI regression coverage
checks lyrics, queue access, rotation and mini-player playback continuity.

## Sources

- [Apple: Prepare your app for iPhone Duo](https://developer.apple.com/iphone-duo/prepare/)
- [Apple: Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo)
- [Apple: ArrangementView](https://developer.apple.com/documentation/swiftui/arrangementview)
- Apple Xcode app-resizability skill, exported using xcrun agent skills export.

Simulator evidence and remaining limitations are recorded separately before release.
A successful build is not proof of all device poses or real CarPlay behavior.


## Validation — 22 October 2026

- Official iOS 27.1 runtime installed; dedicated iPhone Duo simulator booted
  and build 21 launched. Screenshot and accessibility hierarchy confirm native
  vertical tabs. Simulator UI tests verify native speech pause/resume and music
  continuity through minimizing, changing tabs and reopening the player.
- Release archive and shared Mac build succeeded. Apple-signed IPA passed
  signature, version, bundle, Team and CarPlay provisioning checks.
- Android interpretation prompt and all ten Home filter parameters remain identical.
- Device Hub UI automation timed out. Fold-angle/pose, external-display transitions
  and physical Duo/CarPlay audio are not yet verified. The lyric/rotation test is
  passed after adapting the test selectors to native vertical tabs and the
  runtime menu accessibility. Lyrics and queue access survive rotation and
  closing/reopening the player. Initial selector failures were not app crashes.
