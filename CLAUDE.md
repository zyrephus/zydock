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

## Notes

- Uses XcodeGen (`project.yml`) to generate `zydock.xcodeproj` — `make build` runs `xcodegen generate` first
- The Go daemon is embedded inside the `.app` bundle at `Contents/MacOS/zydockd`
- App runs as a background agent (no dock icon) via `LSUIElement: YES`
