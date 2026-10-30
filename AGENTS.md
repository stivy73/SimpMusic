# NoteNarrate delivery rules

After every Android APK build, commit and push its corresponding sources to the personal GitHub forks (`stivy73/SimpMusic` and, when modified, `stivy73/core`). Verify remote URLs before pushing. Never push to maxrave-dev upstream. Push core first and record its commit in the parent repository. Do not include API keys, private signing keys, generated build directories or unrelated work. Report test/build results and any push failure explicitly.

For every NoteNarrate iOS TestFlight release, also assign the processed build to the existing `Team interno` tester group. Preserve other assigned groups such as `Stivy73`. Verify Apple processing, internal testing state and actual group assignment before reporting the beta available. This does not authorize creating users, changing account roles, enabling automatic distribution or submitting a public App Store release. Commit and push the matching iOS sources/version/build to the personal fork for each release.
