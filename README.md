# Vidp

A minimal, keyboard-driven macOS video player built on [libmpv](https://mpv.io), written in Swift/AppKit.
No Electron, no bloat — just a fast native player that plays nearly anything mpv can.

## Install

### via Homebrew (recommended)

```sh
brew tap mdopeace/vidp
brew install vidp
```

That installs to `/Applications` — no compiler, no `brew install mpv`, nothing
else to set up. The app bundles its own libmpv and ffmpeg, so it runs standalone.

To update to a newer release:

```sh
brew update && brew upgrade vidp
```

Then launch:

```sh
open /Applications/vidp.app
```

Once installed, the app's **Check for Updates** command keeps it up to date. It
does nothing when you're already on the latest version, so it can't do the
initial install.

> **Apple Silicon only.** Releases are arm64, so the prebuilt binary won't run on
> Intel. Build from source below if you need x86_64.
>
> Because libmpv and ffmpeg are bundled, an update ships a new copy of them —
> expect a ~25 MB download per upgrade.

### from source

Requires [Homebrew](https://brew.sh), Xcode Command Line Tools (`swiftc`, `sips`),
and libmpv:

```sh
brew install mpv
./scripts/build.sh        # produces ./vidp.app
open vidp.app
```

## Requirements

- macOS 13+ (Apple Silicon for prebuilt releases; Intel can build from source)

Building from source additionally needs [Homebrew](https://brew.sh), the Xcode
Command Line Tools, and libmpv (`brew install mpv`). Release builds bundle
libmpv into the app itself, so end users need none of this.

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
Release builds ship copies of libmpv, FFmpeg and their dependencies inside the
app bundle; see [LICENSES.md](LICENSES.md) for those, and note that
`rubberband`, `x264` and `x265` are GPL-2.0-or-later, which puts the distributed
app under GPL terms.

## Links

- Homebrew tap: [mdopeace/homebrew-vidp](https://github.com/mdopeace/homebrew-vidp)
- Releases: <https://github.com/mdopeace/vidp/releases>

## Releases

Changes ship to Homebrew users as versioned releases, not per-commit. To cut a
release, run `./scripts/release.sh` — it reads the current version from `Info.plist`,
presents a Patch/Minor/Major selector (via a bash `select` menu),
and handles the full release flow (bump, PR, tag, GitHub Release, tap update).

Requires: [gh](https://cli.github.com) (authenticated).

Users then update with `brew update && brew upgrade vidp`.
