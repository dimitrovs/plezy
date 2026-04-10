<h1>
  <img src="assets/plezy.png" alt="Plezy Logo" height="24" style="vertical-align: middle;" />
  Plezy
</h1>

A modern Plex client for desktop and mobile. Built with Flutter for native performance and a clean interface.

<p align="center">
  <img src="assets/screenshots/macos-home.png" alt="Plezy macOS Home Screen" width="800" />
</p>

*More screenshots in the [screenshots folder](assets/screenshots/#readme)*

## Download

Download the latest self-signed APK from the [GitHub Releases](https://github.com/dimitrovs/plezy/releases/latest) page.

Available APK variants:
- **arm64-v8a** - Most modern Android phones and tablets
- **armeabi-v7a** - Older 32-bit ARM devices
- **x86_64** - Android emulators and x86 devices

## Features

### 🔐 Authentication
- Sign in with Plex
- Automatic server discovery and smart connection selection
- Persistent sessions with auto-login

### 📚 Media Browsing
- Browse libraries with rich metadata
- Advanced search across all media
- Collections and playlists

### 🎬 Playback
- Wide codec support (HEVC, AV1, VP9, and more)
- HDR and Dolby Vision (not Linux)
- Full ASS/SSA subtitle support
- Audio and subtitle preferences synced with Plex profile
- Progress sync and resume
- Auto-play next episode

### 📺 Live TV & DVR
- EPG guide grid
- Channel tuning
- DVR recording rules and scheduled recordings
- Multi-server DVR support

### 📥 Downloads
- Download media for offline viewing
- Background downloads with queue management

### 👥 Watch Together
- Synchronized playback with friends
- Real-time play/pause and seek sync

## Building from Source

### Prerequisites
- Flutter SDK 3.8.1+
- A Plex account with server access

### Setup

```bash
git clone https://github.com/dimitrovs/plezy.git
cd plezy
flutter pub get
dart run build_runner build
flutter run
```

### Code Generation

After modifying model classes:

```bash
dart run build_runner build --delete-conflicting-outputs
```

## Acknowledgments

- Built with [Flutter](https://flutter.dev)
- Designed for [Plex Media Server](https://www.plex.tv)
- Playback powered by [mpv](https://mpv.io) via [MPVKit](https://github.com/mpvkit/MPVKit) and [libmpv-android](https://github.com/jarnedemeulemeester/libmpv-android)
