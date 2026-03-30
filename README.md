# zydock

A macOS notch widget to monitor Claude Code via hooks and a Go daemon backend.

## Build

```bash
cd app
xcode-project build
```

The app includes a post-build step that compiles the Go daemon automatically.

## Architecture

- **App**: Swift/SwiftUI macOS notch widget
- **Daemon**: Go backend for monitoring and status updates
- **Communication**: Hooks for integration with CLI tools
