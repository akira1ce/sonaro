# NetEase direct requests implementation plan

**Goal:** Replace the self-hosted API dependency with native EAPI requests, preserving all existing music features.
**Architecture:** APIClient sends encrypted POST requests to interfacepc.music.163.com. MusicService owns official endpoint parameters; AuthManager obtains QR credentials from response cookies. Existing Keychain and device identity remain in use.
**Tech stack:** Swift, Foundation URLSession, system CommonCrypto, XCTest. No new dependencies.
**Approved design:** Conversation: native EAPI, existing managers and UI, no plugin framework or local server.

- [x] Add an OpenSSL-derived encryption vector test and invalid-path test; run them before implementation.
- [x] Implement EAPI encryption and direct APIClient requests, including body error codes, explicit cookie handling and redirect rejection.
- [x] Migrate all MusicService callers, including ordered playlist pagination and preview rejection; migrate QR login with cancellation guards and local logout.
- [x] Test transport responses with URLProtocol fixtures (QR cookies, authentication errors, risk control, anonymous credentials); run full XCTest suite.
- [x] Remove obsolete server configuration setup, update README and protocol attribution; verify unsigned Release build and anonymous live requests. Real account login/playback requires a phone scan and remains manual.

## Verification

- 59 XCTest cases passed, including OpenSSL-derived EAPI vector, cookie/error transport fixtures, null-string preview compatibility, and missing-song pagination.
- Anonymous production transport probe succeeded for search, toplist, high-quality playlists, top artists, playlist detail, song detail, lyrics, stream URL response and QR key; QR polling returned 801. This does not verify actual audio playback or an authenticated session.
- Manual checks remaining: phone-confirmed login, account recommendations/history, membership playback and like/subscribe writes. Upstream subscription may request Yidun anti-cheat verification; this trial reports those errors rather than embedding a browser SDK.
- Login cookie persistence remains at QR authorization; ordinary response cookie rotation has not been authenticated-tested.
- Universal Release build (arm64 + x86_64) succeeded with CODE_SIGNING_ALLOWED=NO; artifact: /tmp/sonaro-direct-build/Build/Products/Release/Sonaro.app. Existing installed app was not replaced.
