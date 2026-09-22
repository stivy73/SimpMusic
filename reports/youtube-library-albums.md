# YouTube Music library albums — implementation report

## Scope and checkout

Read-only remote album library support. Initial endpoint: `FEmusic_liked_albums`; continuation requests use the same InnerTube `browse` API and `WEB_REMIX`, with `setLogin = true`. No corpus-albums fallback, OAuth, remote library mutation, database membership simulation, tracking or analytics changes.

Local checkout: `/Users/stivy/Documents/ChatGPT/iOS/SimpMusic`.
Both SimpMusic and core use local branch `feature/youtube-library-albums`.
SimpMusic base: `ed2e9580` (`dev`); core base: `dbc1c9a` (the pinned submodule commit, also the fetched `multiplatform` tip).
The authenticated GitHub account was `stivy73`; its listed forks contained no SimpMusic or core fork. Both origins still point to `maxrave-dev`; `.gitmodules` is unchanged. No push, remote fork creation or PR was performed.

## Architecture decisions

1. Existing generic `YouTube.browse()` parses albums but discards pagination. No reusable `completed()` implementation was found. The existing playlist path confirms the grid/continuation transport, but its nullable result and continuation failure handling are unsuitable for a complete-or-error library.
2. New `YouTube.getLibraryAlbums(session)` exhausts pagination using `LibraryAlbumsPage.completed`. `LibraryAlbumsPage` only traverses typed page envelopes (`BrowseResponse`, `GridRenderer`, `Continuation`); album decoding is delegated to the existing `RelatedPage.fromMusicTwoRowItemRenderer`, the same parser used by generic browse. There is no duplicate album JSON parser.
3. `AlbumRepository.getYouTubeLibraryAlbums()` returns `Flow<Resource<List<AlbumsResult>>>` and reuses `AlbumItem.toAlbumsResult()`. It never reads or writes `AlbumEntity`, `favoriteAt`, or local `inLibrary`. `getLikedAlbums()` is unchanged.
4. `LibraryViewModel` owns separate remote state with the project's `LocalResource`: Loading, Success, Success with an empty list, and Error. A refresh replaces state and re-fetches the complete library. Cancellation is propagated, not translated into success.
5. `GridLibraryAlbum` wraps the Library's existing pull-to-refresh pattern and `LibraryGridCells`, directly passing `AlbumsResult` to `HomeItemContentPlaylist` (also used by MoreAlbumsScreen). No PlaylistType conversion. Clicks use the existing `AlbumDestination(browseId)`; album loading and playback implementations are unchanged.
6. The Library tab starts on Album for an authenticated YouTube account. It no longer restores a previously saved Library filter; reopening or re-tapping the Library tab resets to Album. Signed-out users fall back to Your Library.
7. Strings were added only to base English and Italian, not to every Crowdin locale. Other locales retain normal base fallback.

## Pagination and failure semantics

- Initial grid, grid continuation, and section-list continuation envelopes are supported.
- Continuations from grids and their containing section are retained; pending tokens are exhausted with no album/page count cap.
- Albums are deduplicated by `browseId`, preserving first-seen order.
- A seen-token set rejects repeated tokens, including duplicate tokens in one response and cycles. Blank/malformed tokens, missing content, unknown sections and unparseable album cards are errors.
- Coroutine cancellation is checked between pages and propagated through the transport.
- HTTP errors (including authorization errors) are already rejected by the existing Ktor client's `expectSuccess = true`.
- Any first-page or subsequent-page failure results in Error without partial data. A recognized empty grid is a successful empty library; an unrecognized response is not silently treated as empty.
- The UI provides localized empty/error messages, a retry button and pull-to-refresh even with an empty/error list.

## Account isolation

The existing global client receives cookie, page ID and Google account index through separate collectors. Reading those global fields during pagination could combine old and new account values.

`DataStoreManager.youtubeSession` therefore exposes one atomic preferences snapshot: login status, cookie, pageId and authUser. This uses the current authentication values and existing `ytClient` authorization helper, with an optional per-request snapshot; existing callers retain their previous behavior. The snapshot is fixed across every page of one library load, so switching accounts cannot mix pages.

The ViewModel observes this snapshot, cancels outstanding work, increments a request generation, and immediately clears its remote album state whenever identity changes. If the album filter is selected and the new session is authenticated, it reloads. Logout resets the filter to Your Library; the chip and grid are gated by loggedIn. The repository and ViewModel also re-check session identity before accepting results, rejecting late responses. Signed-out calls make no network request. Session string representations redact credentials.

## Regression boundary

Source inspection confirms no changes to YouTube playlists, LM, local album likes/favorites, downloaded/local/favorite playlists, AlbumScreen, album playback, FOSS dependencies, analytics or tracking. The optional request session argument defaults to the existing global behavior for those callers. This is a source-level regression review, not authenticated device testing.

## Verification

See the final verification record below for actual commands, outcomes and limitations.

## Suggested commits and publication prerequisites

1. Core: `feat(core): support complete YouTube library albums` — parser fixtures/tests, atomic session snapshot and repository support.
2. SimpMusic: `feat(library): display YouTube Music library albums` — UI/ViewModel/resources, the core submodule pointer and this report.

Core is published first to the personal fork, and SimpMusic points its submodule URL at that fork so a clone can resolve the committed submodule revision.

## Changed files

### SimpMusic

- Modified: `composeApp/src/commonMain/composeResources/values-it/strings.xml`
- Modified: `composeApp/src/commonMain/composeResources/values/strings.xml`
- Modified: `composeApp/src/commonMain/kotlin/com/maxrave/simpmusic/ui/screen/library/LibraryScreen.kt`
- Modified: `composeApp/src/commonMain/kotlin/com/maxrave/simpmusic/viewModel/LibraryViewModel.kt`
- New: `composeApp/src/commonMain/kotlin/com/maxrave/simpmusic/ui/component/GridLibraryAlbum.kt`
- New: `reports/youtube-library-albums.md`

### core

- Modified: `common/src/commonMain/kotlin/com/maxrave/common/Config.kt`
- Modified: `data/src/commonMain/kotlin/com/maxrave/data/dataStore/DataStoreManagerImpl.kt`
- Modified: `data/src/commonMain/kotlin/com/maxrave/data/di/RepositoryModule.kt`
- Modified: `data/src/commonMain/kotlin/com/maxrave/data/repository/AlbumRepositoryImpl.kt`
- Modified: `domain/src/commonMain/kotlin/com/maxrave/domain/manager/DataStoreManager.kt`
- Modified: `domain/src/commonMain/kotlin/com/maxrave/domain/repository/AlbumRepository.kt`
- Modified: `service/kotlinYtmusicScraper/src/commonMain/kotlin/com/maxrave/kotlinytmusicscraper/YouTube.kt`
- Modified: `service/kotlinYtmusicScraper/src/commonMain/kotlin/com/maxrave/kotlinytmusicscraper/Ytmusic.kt`
- New: `domain/src/commonMain/kotlin/com/maxrave/domain/manager/YouTubeSession.kt`
- New: `service/kotlinYtmusicScraper/src/commonMain/kotlin/com/maxrave/kotlinytmusicscraper/pages/LibraryAlbumsPage.kt`
- New: `service/kotlinYtmusicScraper/src/jvmTest/kotlin/com/maxrave/kotlinytmusicscraper/pages/LibraryAlbumsPageTest.kt`
- New: `service/kotlinYtmusicScraper/src/jvmTest/resources/library-albums/empty.json`
- New: `service/kotlinYtmusicScraper/src/jvmTest/resources/library-albums/first.json`
- New: `service/kotlinYtmusicScraper/src/jvmTest/resources/library-albums/invalid-album.json`
- New: `service/kotlinYtmusicScraper/src/jvmTest/resources/library-albums/missing.json`
- New: `service/kotlinYtmusicScraper/src/jvmTest/resources/library-albums/next-1.json`
- New: `service/kotlinYtmusicScraper/src/jvmTest/resources/library-albums/next-2.json`
- New: `service/kotlinYtmusicScraper/src/jvmTest/resources/library-albums/repeated.json`
- New: `service/kotlinYtmusicScraper/src/jvmTest/resources/library-albums/section-continuation.json`
- New: `service/kotlinYtmusicScraper/src/jvmTest/resources/library-albums/unexpected.json`


## Verification record (2026-09-22)

Command run from the SimpMusic checkout:

```sh
GRADLE_USER_HOME=/Users/stivy/Documents/ChatGPT/iOS/tools/gradle-cache \
  ./gradlew :kotlinYtmusicScraper:jvmTest :androidApp:assembleDebug :androidApp:lintDebug \
  -PisFullBuild=false --console=plain
```

- JVM parser/pagination suite: **13 tests, 0 failures, 0 errors, 0 skipped**. Covers initial album parsing, recognized empty library, grid continuation, chained pages with duplicate albums, repeated token, duplicate token in one page, blank token, section continuation, malformed response/card, first-page failure, continuation failure, cancellation and 150 pages without an arbitrary cap. Fixtures are synthetic typed-response examples, not captures of the user's authenticated account.
- `:androidApp:assembleDebug`: **completed**, including compilation of core, data, Compose UI and Android application. FOSS selection confirmed by `cast-empty` and `crashlytics-empty` tasks.
- ARM64 APK: `androidApp/build/outputs/apk/debug/androidApp-arm64-v8a-debug.apk`. Debug package: `com.maxrave.simpmusic.dev`, version `2.1.0-dev`. `apksigner verify` succeeded.
- APK SHA-256: `0c8fcb0ee52cba355daded5e3a41c752567a6d8edb39e5f136456cd43716738c`.
- ktlint 1.8.0 formatting and checking executed with the repository's `.editorconfig`. **All new Kotlin files pass**. Checking all touched files retains 10 pre-existing style/KDoc findings in `DataStoreManager.kt` and `YouTube.kt`; comparing against HEAD's 14 findings shows **zero introduced findings**. Unrelated comment/whitespace sections were preserved.
- Base English/Italian resource XML parsed successfully; each of the four new string keys occurs exactly once.
- `git diff --check` passes in both repositories.
- A separate overlapping JVM-only invocation timed out on Gradle's configuration-cache lock; it is not counted as a passing run. The combined invocation successfully executed all 13 tests.
- Android Lint: **failed with 6 errors and 125 warnings**. All six errors are in files verified byte-for-byte identical to HEAD: `AutoBackupWorker.kt` lines 166/208/232 (`NewApi`, MediaStore.Downloads requires API 29, minSdk 26) and `widget_preview_playlists.xml` lines 63/71/79 (`UseAppTint`). No findings reference the feature's files. These unrelated baseline issues were not changed or suppressed. The combined command therefore exited 1 even though its JVM test and assembleDebug tasks succeeded. Report: `androidApp/build/reports/lint-results-debug.html`.
- Separate build confirmation: `./gradlew :androidApp:assembleDebug -PisFullBuild=false --console=plain` returned **BUILD SUCCESSFUL in 9s**, exit 0 (303 tasks: 14 executed, 289 up-to-date). The same GRADLE_USER_HOME was used.

### Remaining acceptance verification

ADB listed no connected devices. No real account cookie was obtained or read. Login, comparing the complete library against YouTube Music (including a real multi-page library), opening/playing an album, switching accounts and logging out still require an authenticated-device acceptance run. The code/build/test results above do **not** claim that those user-path checks have passed.

Suggested device sequence: use the debug APK, sign in to account A, open Library → Album YouTube Music, compare counts/IDs with YouTube Music, refresh twice and check for duplicates, open and play an album, switch to account B (including a brand channel if applicable), then log out and confirm the chip disappears. Also check LM, remote playlists, local album favorites and local/downloaded/favorite playlists. A network interruption during a continuation must show the error/retry state without presenting the partial library as complete.

## Local evidence links

- [ARM64 debug APK](/Users/stivy/Documents/ChatGPT/iOS/SimpMusic/androidApp/build/outputs/apk/debug/androidApp-arm64-v8a-debug.apk)
- [JVM test report](/Users/stivy/Documents/ChatGPT/iOS/SimpMusic/core/service/kotlinYtmusicScraper/build/reports/tests/jvmTest/index.html)
- [Android Lint report](/Users/stivy/Documents/ChatGPT/iOS/SimpMusic/androidApp/build/reports/lint-results-debug.html)
- [Combined build/test/lint log](/tmp/simpmusic-albums-build.log)
- [Successful standalone build log](/tmp/simpmusic-albums-assemble.log)
- [ktlint current-file findings](/tmp/simpmusic-albums-ktlint-final.log)
- [ktlint original-file baseline](/tmp/simpmusic-lint-baseline.log)

Logs under `/tmp` are temporary; the source changes and this report are in the checkout.
