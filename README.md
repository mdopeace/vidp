# vidp

A minimal, keyboard-driven macOS video player built on [libmpv](https://mpv.io), written in Swift/AppKit.
No Electron, no bloat — just a fast native player that plays nearly anything mpv can.

## Install

### via Homebrew (recommended)

```sh
brew tap mdopeace/vidp
brew install vidp
```

To update to a newer release:

```sh
brew update && brew upgrade vidp
```

Then launch:

```sh
open "$(brew --prefix)/opt/vidp/libexec/vidp.app"
```

Or copy it into `/Applications` to use it like any other app:

```sh
cp -R "$(brew --prefix)/opt/vidp/libexec/vidp.app" /Applications/
```

### from source

Requires [Homebrew](https://brew.sh), Xcode Command Line Tools (`swiftc`, `sips`),
and libmpv:

```sh
brew install mpv
./scripts/build.sh        # produces ./vidp.app
open vidp.app
```

## Requirements

- macOS 13+ (Apple Silicon or Intel)
- [libmpv](https://mpv.io) (`brew install mpv`)
- Xcode Command Line Tools
- [gum](https://github.com/charmbracelet/gum) for releases (`brew install charmbracelet/tap/gum`)

## Features

- Native AppKit UI rendering video via mpv/OpenGL
- Keyboard-driven controls and a minimal on-screen HUD
- Now-playing integration with macOS MediaPlayer
- Supports common video formats: mp4, m4v, mov, mkv, webm, avi
- Reads media from files or the Finder ("Open With")
- Check for updates via GitHub API (automatic on launch + manual menu item)
- Uninstall support with full cleanup or app-only removal

## Notes

- The app is ad-hoc signed for local use. It is not notarized, so the first
  launch of a downloaded copy may require right-click → Open (or
  `xattr -dr com.apple.quarantine /Applications/vidp.app`).
- Contributions and issues are welcome, but `main` is branch-protected —
  please open a pull request.

## License

[MIT](LICENSE) © 2026 Md Mostafijur Rahman.

This project links against [libmpv](https://mpv.io), which remains under its own
[LGPL/GPL license](https://github.com/mpv-player/mpv/blob/master/Copyright).

## Links

- Homebrew tap: [mdopeace/homebrew-vidp](https://github.com/mdopeace/homebrew-vidp)
- Releases: <https://github.com/mdopeace/vidp/releases>

## Releases

Changes ship to Homebrew users as versioned releases, not per-commit. To cut a
release, run `./scripts/release.sh` — it reads the current version from `Info.plist`,
presents a Patch/Minor/Major selector (via [gum](https://github.com/charmbracelet/gum)),
and handles the full release flow (bump, PR, tag, GitHub Release, tap update).

Requires: [gh](https://cli.github.com) (authenticated), [gum](https://github.com/charmbracelet/gum) (`brew install charmbracelet/tap/gum`).

Users then update with `brew update && brew upgrade vidp`.
