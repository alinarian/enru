# enru

A macOS menu-bar utility for English ↔ Russian translation. Press **⌘E** anywhere, type in either
language, and get a live translation — the direction is auto-detected from the script you type in.

Runs entirely **on-device** via Apple's Translation framework: no API key, no account, no network.
Native Swift + SwiftUI, no Dock icon.

**Requires macOS 15 (Sequoia) or later.** Building from source needs Swift 6 / Xcode 16.

## Install

```bash
./Scripts/build-app.sh
mv enru.app /Applications/
```

Then launch it like any other app. To start it automatically, add `enru.app` under
**System Settings → General → Login Items**.

For development, `swift run enru` launches it from the terminal (Ctrl+C to quit).

The app icon is drawn from the wordmark exported to `Resources/Icon.svg`, embedded as path data in
`Sources/enru/Wordmark.swift`. `Resources/enru.icns` is committed; re-run `./Scripts/make-icon.sh`
after changing the artwork.

## Using it

- **⌘E** — toggle the popup, from anywhere, even when another app is focused.
- Type in English or Russian. Translation updates ~400ms after you stop typing; pasted text
  translates immediately.
- **Esc** or a click outside — close it.
- Drag the background to move the popup, drag an edge to resize. Position and size persist.
- Left-click the menu bar icon to toggle; right-click for a menu.

### First-time language download

The first translation in each direction may need macOS to download a small language model. The
popup shows "Preparing language model…" while that happens. If it stalls, add English and Russian
under **System Settings → General → Language & Region → Translation Languages**.

### Permissions

The global hotkey uses the Carbon Hot Key Manager, which needs no permissions. Click-outside
dismissal uses a global mouse monitor — if that doesn't work, enable enru under
**System Settings → Privacy & Security → Accessibility**.

## How it works

The popup is a borderless `.nonactivatingPanel` at floating level, so it appears over other apps
and across full-screen Spaces without stealing focus, while still accepting keystrokes.

Translation is the interesting part. `TranslationSession` can only be obtained from a SwiftUI
`.translationTask`, and that modifier re-runs only when its configuration *value* changes — two
configurations for the same language pair compare equal. So rebuilding a configuration per
keystroke does not reliably restart the task, and tearing down a session mid-`translate` can hang.

Instead, `ContentView` holds one configuration per direction, created once and never mutated. Each
gets a long-lived session running a loop that drains a job queue from `AppState`. Typing pushes
jobs onto the queue (`bufferingNewest(1)`, so bursts collapse to the latest); results carry a
monotonic job ID and are discarded if a newer job has since been dispatched. In-flight translations
are never cancelled — dropping a stale result is free, whereas cancelling meant destroying the
session. A session that errors invalidates its configuration to get a fresh one.

Language detection counts Cyrillic vs. Latin code points; ties default to English.

The package targets Swift language mode 5 to avoid strict-concurrency friction with AppKit and
Translation APIs that aren't fully `Sendable`-audited — a pragmatic choice, not a correctness one.
