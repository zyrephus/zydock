# Changelog

All notable changes to zydock are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] - 2026-11-15

### Added
- Glass panel: on macOS 26 and later, the open notch shows the desktop through
  Liquid Glass below a black top that fades smoothly into it. On by default;
  turn it off in Settings for solid black.
- Glass tint: pick black, blue, purple, pink, red, orange, yellow, green, or
  teal in Settings.
- Music bump: the closed notch springs wider when the track changes or
  playback pauses or resumes.
- Dragging a file near the closed notch opens it on the Tray tab.

### Changed
- The Tray tab opens larger (640 by 240 pt), so a full tray shows every item
  without scrolling. Other tabs keep their size.

### Fixed
- Files can be dropped anywhere on the open notch, on any tab. Before, drops
  failed over the tray's item grid and the top bar.
- An image dragged from a browser is now saved to the tray instead of showing
  a blank item.
- Dragging a window or selecting text near the notch no longer switches to the
  Tray tab.

## [1.1.1] - 2026-08-02

### Added
- Settings: an "Open on" preference that picks which tab the notch shows each
  time it expands. Defaults to the last used tab; the list is built from the
  enabled modules, so it follows whatever is turned on.
- Tray items can be pinned so they survive the trim that drops old entries.

### Changed
- Renamed the tray's Files sub-tab to Tray.
- Tray file names use the app's standard font instead of a monospaced one.

### Fixed
- Home tab: a day with three calendar events no longer pushes the music
  controls and progress bar down.

## [1.1.0] - 2026-06-16

### Added
- Now-playing peek: when the notch is collapsed, a track change or playback
  start drops a small sliver below it for a few seconds showing the current
  track, then retracts. Hovering it expands the full notch. Long titles
  marquee-scroll; short titles are centered.
- Tray tab: a Files / Clipboard toggle to switch between the two sections.

### Changed
- Reworked the notch expand/collapse animation. The panel now snaps open
  instantly while SwiftUI animates the shape, so it no longer stutters or
  reflows as it grows; content is revealed in place by the opening shape and
  each component springs in individually with a staggered, bouncy entrance.

### Fixed
- Claude Code session no longer gets stuck showing the blue "waiting" state
  after a tool fails or a permission prompt is denied (now handles the
  `PostToolUseFailure` and `PermissionDenied` hook events).

## [1.0.2] - 2026-05-27

### Changed
- Redesigned the stats tab.

### Fixed
- Process name truncation.

## [1.0.1] - 2026-05-15

### Added
- Claude Code hooks now install automatically on app launch.

### Fixed
- Apple Music skip-while-paused, play/pause flicker, and missing artwork.

## [1.0.0] - 2026-05-10

- Initial release.
