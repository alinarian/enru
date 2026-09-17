# enru

A macOS menu-bar utility for quick translation between any two languages you choose — pick any
pair that Apple's Translation framework supports and switch pairs at any time. Press **⌘E**
anywhere, type in either language, and get a live translation — the direction is auto-detected from
what you type.

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

### Updating

Quit the running copy, pull, rebuild, and replace the installed bundle:

```bash
pkill -x enru
git pull
./Scripts/build-app.sh
rm -rf /Applications/enru.app && mv enru.app /Applications/
open /Applications/enru.app
```

`swift run` leaves debug builds under `.build/`; `rm -rf .build` clears them. Settings — the
language pair and the popup's position and size — live in user defaults, so they survive an update.

The app icon is drawn from the wordmark exported to `Resources/Icon.svg`, embedded as path data in
`Sources/enru/Wordmark.swift`. `Resources/enru.icns` is committed; re-run `./Scripts/make-icon.sh`
after changing the artwork.

## Using it

- **⌘E** — toggle the popup, from anywhere, even when another app is focused.
- Type in either of the two selected languages. Translation updates ~400ms after you stop typing;
  pasted text translates immediately.
- The two language names centred above the text field are menus: the left one is the **input**
  language, the right one the **output**, and the ⇄ between them swaps the pair. Picking the same
  language on both sides also swaps. The choice persists and any text already typed is re-translated
  straight away.
- **Esc** or a click outside — close it.
- Drag the background to move the popup; drag any edge or corner to resize it, width included.
  Position and size persist.
- Left-click the menu bar icon to toggle; right-click for a menu.

### Languages

The language menus list everything Apple's on-device Translation framework supports on your Mac;
the current choice is checked. The input language is the one you normally type; text recognised as
the output language is translated back into the input language instead, so a pair works in both
directions without touching the menus. The pair is yours to choose; a fresh install starts with
English → Russian only until you pick something else.

### First-time language download

The first translation in each direction may need macOS to download a small language model. The
popup shows "Preparing language model…" while that happens. If it stalls, add both languages
under **System Settings → General → Language & Region → Translation Languages**.

### Permissions

The global hotkey uses the Carbon Hot Key Manager, which needs no permissions. Click-outside
dismissal uses a global mouse monitor — if that doesn't work, enable enru under
**System Settings → Privacy & Security → Accessibility**.

## How it works

The popup is a borderless `.nonactivatingPanel` at floating level, so it appears over other apps
and across full-screen Spaces without stealing focus, while still accepting keystrokes. A borderless
window's built-in resize zone is a few invisible points wide, so `PopupPanel` handles edge and corner
drags itself with an 8pt margin, tracks the drag in screen coordinates (dragging the left or bottom
edge moves the window's origin), and shows the matching resize cursor on hover.

The language bar is two `Menu`s drawn without bezel or indicator, each centred in an equal, flexible
half of the row, so the swap glyph stays on the panel's centre line whatever the names' lengths.

Translation is the interesting part. `TranslationSession` can only be obtained from a SwiftUI
`.translationTask`, and that modifier re-runs only when its configuration *value* changes — two
configurations for the same language pair compare equal. So rebuilding a configuration per
keystroke does not reliably restart the task, and tearing down a session mid-`translate` can hang.

Instead, `ContentView` holds one configuration per direction, rebuilt only when the language pair
changes. Each gets a long-lived session running a loop that drains a job queue from `AppState`.
Typing pushes jobs onto the queue (`bufferingNewest(1)`, so bursts collapse to the latest); results
carry a monotonic job ID and are discarded if a newer job has since been dispatched. In-flight
translations are never cancelled — dropping a stale result is free, whereas cancelling meant
destroying the session. A session that errors invalidates its configuration to get a fresh one.
Changing the language pair finishes both queues, orphans in-flight jobs, and parks the current text
until the new sessions register, at which point it is dispatched again.

Language detection uses `NLLanguageRecognizer` constrained to the two selected languages, so it
also works for pairs that share a script; when it has no opinion, the text is treated as the input
language.

The package targets Swift language mode 5 to avoid strict-concurrency friction with AppKit and
Translation APIs that aren't fully `Sendable`-audited — a pragmatic choice, not a correctness one.
