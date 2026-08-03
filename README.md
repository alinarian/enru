# enru

A lightweight macOS menu-bar utility: press **Cmd+E** anywhere on the system to pop up a small
floating window, type a word or phrase in English or Russian, and get a live translation to the
other language, auto-detected from the script you type in.

Translation runs entirely **on-device** via Apple's native Translation framework — no API key,
no account, no network calls, no usage limits.

Native Swift + SwiftUI, no Electron, no Dock icon — runs as a menu-bar accessory app.

## Requirements

- **macOS 15 (Sequoia) or later** — required by Apple's on-device Translation framework
- Xcode 16+ / Swift 6+ (for building from source)

## Project structure

```
enru/
├── Package.swift                 # Swift Package Manager manifest
├── Sources/enru/
│   ├── main.swift                # Entry point, activation policy (no Dock icon)
│   ├── AppDelegate.swift         # Wires up status bar, hotkey, popup on launch
│   ├── StatusBarController.swift # Menu bar icon + right-click menu (Quit)
│   ├── HotkeyManager.swift       # Global Cmd+E registration (Carbon Hot Key Manager)
│   ├── PopupPanel.swift          # Borderless, floating, non-activating NSPanel
│   ├── PopupWindowController.swift # Show/hide/toggle, positioning, click-outside & Esc dismiss, frame persistence
│   ├── ContentView.swift         # SwiftUI: input field + output area, vibrancy background,
│   │                              #   drives the .translationTask that performs the translation
│   ├── AppState.swift            # Debounced translation pipeline, loading/error state
│   ├── LanguageDetector.swift    # Cyrillic vs Latin heuristic
│   └── TranslationRequest.swift  # The small value type passed from AppState to the view
├── Scripts/build-app.sh          # Packages a release build into enru.app
└── README.md
```

## 1. Run in development

```bash
swift build
swift run enru
```

This launches the app in the foreground of your terminal session; it still runs as a proper
menu-bar accessory app (icon appears in the menu bar, no Dock icon). Press **Ctrl+C** in the
terminal to quit, or use the status bar menu's Quit item.

## 2. Using it

- **Cmd+E** — toggle the popup open/closed, from anywhere, even when another app is focused.
- Type a word or phrase in English or Russian — the script you use is auto-detected.
- Translation updates live, ~1000ms after you stop typing.
- **Esc** — close the popup.
- Click anywhere outside the popup — also closes it.
- Drag the background of the popup to reposition it; drag an edge/corner to resize it. Position
  and size are remembered the next time you open the app.
- Left-click the menu bar icon to toggle the popup; right-click it for a small menu (toggle, quit).

### First-time language download

The first time you translate a given EN→RU or RU→EN pair, macOS needs to download a small
on-device language model. This normally happens automatically and silently (a few seconds on a
decent connection) — the output area will just show the translation once it's ready. If it seems
stuck the first time, check **System Settings → General → Language & Region → Translation
Languages** and make sure English and Russian are both added there; you can also trigger the
download manually from that screen.

## 3. Package as a standalone app

```bash
./Scripts/build-app.sh
```

This builds a release binary and assembles `enru.app` in the project root (with `LSUIElement`
set so it never shows a Dock icon or app switcher entry). Move it wherever you like:

```bash
mv enru.app /Applications/
```

Then launch it like any other Mac app (Spotlight, Finder, etc.) — no Xcode needed on the
target machine, just the built bundle.

> Note: `enru.app` built this way is unsigned. On first launch, right-click (or Control-click)
> the app in Finder and choose **Open**, then confirm, since Gatekeeper will otherwise warn about
> an app from an unidentified developer. This is a one-time step.

## 4. Permissions

- The **Cmd+E** global hotkey uses the classic Carbon Hot Key Manager (`RegisterEventHotKey`),
  which works system-wide without requiring Accessibility permission.
- The "click outside to dismiss" feature uses a global mouse-event monitor
  (`NSEvent.addGlobalMonitorForEvents`). On first use, macOS may prompt you to grant **enru**
  access under **System Settings → Privacy & Security → Accessibility** (or **Input Monitoring**).
  If the popup doesn't dismiss on outside clicks, check that enru is enabled there.
- No network or account permissions are needed for translation — it's all on-device.

## 5. Launch at login

Easiest path — no extra code needed:

1. Build and move `enru.app` to `/Applications` (see step 3).
2. Open **System Settings → General → Login Items**.
3. Click **+** under "Open at Login", select `enru.app`, and add it.

The app will then start automatically (in the background, no Dock icon) every time you log in.

## Notes on the implementation

- The window is an `NSPanel` (`.nonactivatingPanel`, `.borderless`) at `.floating` level, so it
  stays above normal windows without stealing focus from whatever app you were using, and appears
  across full-screen Spaces (`.canJoinAllSpaces`, `.fullScreenAuxiliary`).
- The panel *can* become key (`canBecomeKey` overridden) so the text field is immediately typable,
  while `NSApp` remains an accessory app.
- Debouncing is done with Combine's `debounce` operator on `@Published var inputText`; a 1000ms
  delay after the last keystroke triggers translation.
- Translation uses Apple's `Translation` framework (`TranslationSession`), which is
  SwiftUI-view-attached: `AppState` decides *when* a translation is needed and publishes a
  `TranslationRequest`; `ContentView` turns that into a `TranslationSession.Configuration` and
  performs the actual `session.translate(...)` call inside a `.translationTask` modifier, then
  reports the result back to `AppState`. Superseded requests are naturally cancelled by SwiftUI
  when the configuration changes again before a translation completes.
- Language detection counts Cyrillic vs. Latin code points; ties/no-signal default to English.
- The Swift package targets language mode 5 (`swiftLanguageMode(.v5)` in `Package.swift`) to avoid
  Swift 6 strict-concurrency friction around AppKit/Translation APIs that aren't yet fully
  `Sendable`-audited; this is a pragmatic choice for a small app, not a correctness requirement.
