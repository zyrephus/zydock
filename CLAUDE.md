# zydock

macOS notch widget that monitors Claude Code sessions via hooks + Go daemon + SwiftUI.

## Build & Run

```bash
# Kill existing instance + daemon, rebuild, and relaunch
killall zydockd zydock 2>/dev/null; make run
```

## Project Structure

- `app/` — SwiftUI macOS app (XcodeGen project)
- `daemon/` — Go WebSocket daemon (`zydockd`), built automatically as a post-build script
- `hooks/` — Claude Code hook scripts

## Layout

Every expanded-notch tab's content root MUST use the global padding so content sits an equal `Layout.contentPadding` (20pt) from the notch shape edge on the left, right, and bottom:

- **Left / right:** `.padding(.horizontal, Layout.horizontalPadding)`
- **Bottom:** `.padding(.bottom, Layout.contentPadding)`

These look like different numbers but produce the same visual gap: `Layout.horizontalPadding` is window-relative, so it's `shapeInset + contentPadding` (the vertical shape sides are inset from the window edge); the bottom has no shape inset, so it uses `contentPadding` directly. Never hardcode these values — both live in `Shared/Typography.swift`. Top padding may vary per tab, but left/right/bottom are fixed and equal.

## Notes

- Uses XcodeGen (`project.yml`) to generate `zydock.xcodeproj` — `make build` runs `xcodegen generate` first
- The Go daemon is embedded inside the `.app` bundle at `Contents/MacOS/zydockd`
- App runs as a background agent (no dock icon) via `LSUIElement: YES`
