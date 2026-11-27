> [!IMPORTANT]
> Sonaro is an unofficial, independently developed music client with no affiliation or partnership with the services it connects to.
> The project contains no music content or account data and is intended for learning and personal use only, not for commercial purposes.
> Music content and related copyrights belong to their respective rights holders.

<div align="right">

**English** | [简体中文](README_CN.md)

</div>

<div align="center">

<img src="Sonaro/Assets.xcassets/AppIcon.appiconset/icon-256.png" width="128" alt="Sonaro" />

# Sonaro

**Listen to your world — a native SwiftUI music client for macOS**

SwiftUI · AVPlayer · Direct connection

[![Platform](https://img.shields.io/badge/platform-macOS%2026%2B-blue?logo=apple)](#build--run)
[![Swift](https://img.shields.io/badge/Swift-5.0-F05138?logo=swift&logoColor=white)](#build--run)
[![UI](https://img.shields.io/badge/UI-SwiftUI-0A84FF)](#features)

<table>
  <tr>
    <td><img src="public/screenshot-recommend.png" alt="Recommendations" /></td>
    <td><img src="public/screenshot-dayly.png" alt="Daily Recommendations" /></td>
  </tr>
  <tr>
    <td><img src="public/screenshot-full-player.png" alt="Now Playing" /></td>
    <td><img src="public/screenshot-artist.png" alt="Artist page" /></td>
  </tr>
</table>

</div>

## Features

- 🔐 **QR code login** — scan with the music service’s official app; the cookie is stored in the macOS Keychain. On cold launch the cached session renders immediately while validation runs in the background, so a network hiccup never signs you out
- 🏠 **Recommendations** — daily playlists, charts, editor-picked playlists, and popular artists across four horizontal shelves, with skeleton loading and page-level retry
- 📅 **Daily Recommendations** — a fresh set of tracks every day, with a cover header, Play All, and the track list
- 🕘 **Recently Played** — switch the play history between Last week and All time
- 🔍 **Search** — song search with 600 ms debounce, duplicate submission suppression, skeletons, infinite scrolling, and empty/error states
- 💿 **Playlists & Artists** — playlist details (creator, description, play count, update time, Play All, subscribe/unsubscribe); artist pages (circular portrait, bio, hot tracks). Artist names in track rows link straight to the artist page
- ❤️ **Likes** — hover actions in track lists and a heart in the player; optimistic updates roll back automatically if the request fails
- 🎧 **Playback** — AVPlayer queue; sequential, repeat-one, shuffle, and repeat-all modes; five quality levels (Standard, Higher, Ex-High, Lossless, Hi-Res) applied to the next track; loading and failure states are visible
- 🪟 **Mini player** — a glass capsule docked at the bottom of the window; click to open Now Playing
- 🖼 **Now Playing** — large artwork that scales with playback; cover and transport controls on the left, synced lyrics on the right. Automatically switches to a compact lyrics-plus-controls layout when the window is narrow
- 📝 **Synced lyrics** — line-by-line highlighting and auto-follow; click a line to seek. Manual scrolling pauses following, and the view returns to the current line after 2.5 seconds; edges fade out
- ⌨️ **System integration** — lock screen, Control Center, and media keys (play, pause, previous, next, seek); Space toggles playback
- 🎨 **Appearance & fonts** — light, dark, or system; custom font family and four size presets with a live preview in Settings
- 🗄️ **Cache** — covers in a disk-backed `URLCache` (about 256 MB), lyrics reused in memory per song ID during the current run; Settings shows cover disk usage and offers one-click clearing
- 🧪 **Unit tests** — pure-logic coverage for LRC parsing, playback mode cycling, tolerant model decoding, formatting, and search paging

## Build & Run

Requires **macOS 26+** and **Xcode 26+** (Swift 5).

```bash
open Sonaro.xcodeproj
```

Choose the **Sonaro** scheme and **My Mac**, then press ⌘R. The project uses synchronized folder groups, so new source files on disk join the target automatically.

No additional server setup is required. Requests are prepared locally and sent to the music service over HTTPS.

### Command-line build and tests

```bash
# Build (same command as CI)
xcodebuild -scheme Sonaro -destination 'platform=macOS' build

# Run unit tests
xcodebuild test -scheme Sonaro -destination 'platform=macOS'
```

`.github/workflows/ci.yml` runs the build and tests on every push / PR.

### Packaging a DMG

```bash
./build-dmg.sh
# Output: dist/Sonaro-<version>.dmg
```

Builds a universal Release app and packages it into a DMG with an Applications shortcut using `hdiutil` — no create-dmg and no Finder automation. The app is signed with the local Apple Development identity (requires an Xcode account matching `DEVELOPMENT_TEAM`), so Keychain permissions survive reinstalls instead of prompting for your login password each time. The signature is machine-bound: on another Mac, right-click the icon and choose **Open** on first launch. If no signing identity is available the script fails instead of falling back to an ad-hoc signature.

## Connection & Session

The app connects directly to the music service without an additional server or runtime.

- QR images are generated locally; credentials obtained through QR authorization are stored in macOS Keychain.
- Account credentials are used only for service API requests and are never sent to audio CDNs. Signing out clears only the local session.
- A separate local device identity survives logout.
- The integration is unofficial and may become unavailable after service changes or verification requirements. Account, regional and licensing restrictions apply; previews are not treated as full tracks.
- See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for third-party sources and licensing.

## Architecture

Five `@MainActor` `ObservableObject` managers are created in [`SonaroApp.swift`](Sonaro/SonaroApp.swift) and injected with `.environmentObject`. They own all session, networking, and playback state; screens never maintain their own:

- `AuthManager` — session state machine (`.unknown → .loggedOut/.loggedIn`) and QR login polling
- `PlayerManager` — AVPlayer queue, playback controls, lyric sync, and system Now Playing; high-frequency progress lives in `PlaybackProgress` / `LyricPlaybackState` so list screens don't redraw every second
- `AppearanceManager` — dark / light / system
- `FontManager` — global font family and size
- `LikeManager` — the liked-song ID set with optimistic updates and rollback

`RootView` switches on `auth.state` (splash → QR login → `MainShell`). `MainShell` uses a `NavigationSplitView` sidebar; the mini player and Now Playing live at window level, so they stay visible after drilling into a playlist.

```
Sonaro/
├─ SonaroApp.swift          # @main; creates and injects shared state
├─ App/                     # RootView, MainShell, Theme, AppearanceManager, FontModifier
├─ Core/
│  ├─ Networking/           # APIConfig (built-in URL), APIClient (async + cookie), APIError
│  ├─ Models/               # Song / Album / Artist / Playlist / Profile (tolerant decoding)
│  ├─ Services/             # MusicService (one method per endpoint), LyricParser, LyricsCache
│  ├─ Auth/                 # AuthManager, Keychain, SessionStore
│  ├─ Player/               # PlayerManager, LyricSynchronizer, NowPlayingController
│  ├─ Library/              # LikeManager
│  └─ Utils/                # ImageLoader, platform helpers, formatters
└─ Features/                # Login, Recommend, Daily, Search, Recent, Home,
                            # Artist, Player, Settings, Sidebar, Components
```

## Disclaimer

- This is a personal learning and technical exchange project, an unofficial product with no affiliation or partnership with the services it connects to.
- The project does not provide or distribute any music resources. Songs, covers, lyrics, and other content are provided by the connected music service.
- Account features require your own service account. Please comply with the service’s user agreement; any account or usage risk is borne by the user.
- Availability and verification requirements are controlled by the service provider; continued compatibility is not guaranteed.
- This project is for personal learning and research only and must not be used commercially or for any copyright-infringing activity.

## Credits

- [Integration references](THIRD_PARTY_NOTICES.md) — third-party sources and licensing
- UI and interactions are inspired by Apple Music; only design ideas were referenced, no assets were used.
