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
