# Cone Player

Cross-platform (macOS, Windows, Linux) video player built with Flutter on top of
libmpv (via [media_kit](https://pub.dev/packages/media_kit)).

## Run

```bash
flutter pub get
flutter run -d macos     # or: -d windows / -d linux
```

- macOS builds need full Xcode (not just Command Line Tools).
- Windows builds need Visual Studio 2022 with "Desktop development with C++".
- Linux builds need: `sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev libmpv-dev mpv`.

Windows and Linux binaries must be built on those systems (or in CI).

## Keyboard shortcuts

| Key | Action |
|---|---|
| Space / K | Play / pause |
| ← / → | Seek ±5 s (Shift: ±60 s) |
| , / . | Previous / next frame |
| ↑ / ↓ | Volume ±5 |
| M | Mute |
| F / Esc | Fullscreen / exit |
| I | Picture-in-picture |
| N / P | Next / previous in queue |
| [ / ] / Backspace | Slower / faster / reset speed |
| H | Hide UI |
| R | Rotate 90° |
| Z / X | Zoom in / out |
| Ctrl/⌘ + B | Add bookmark |
| Ctrl/⌘ + O | Open file (Shift: folder) |
| Ctrl/⌘ + U | Open network stream |
| Ctrl/⌘ + V | Play link/path from clipboard |
| Ctrl/⌘ + L | Queue & bookmarks panel |

## Mouse & trackpad

- Seek bar: drag to scrub, hold **Shift** for 10× finer scrubbing, scroll to step frames.
- Video: scroll for volume; trackpad two-finger swipe on the left half for brightness,
  right half for volume; pinch to zoom; double-click left/right third to jump 10 s,
  centre to toggle fullscreen; right-click for the video menu.
- Drop files onto the window to play, or onto a playing video to add them to the queue.

## Roadmap

1. ✅ Core player: theme, control bar, cone volume, seek bar, auto-hide, subtitle/audio
   flyouts (with output-device switching), OSD, shortcuts, queue, bookmarks, PiP, gestures.
2. Inspector sidebar (subtitle / audio / video / playback panels, EQ).
3. Library, home hub, resume banner, IPTV channel lists.
4. Seek thumbnails, waveform, subtitle timeline sync, OpenSubtitles.
5. Settings (10 panels), layout customizer, onboarding, shaders, multi-window sync.
6. Convert, capture device, cast.
