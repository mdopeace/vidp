# VidP — Design Spec (2026-08-21)

Offline macOS video player with genuine Apple TV controls, Mac App Store-ready.

## Decisions

| Area | Choice |
|---|---|
| Stack | Native SwiftUI, Swift 6, macOS 14+, arm64 |
| Scope | Player only — no library UI |
| Engine | `AVPlayerView` (AVKit) — real Apple TV controls: floating bar, scrubber, subtitle menu, PiP, fullscreen |
| Non-native containers (mkv/avi/webm/ts/flv…) | ffmpeg **stream-copy remux** to temp fMP4, played by AVPlayer |
| Subtitles | Embedded text subs + user co-selected `.srt`/`.vtt` sidecars → `mov_text` tracks named by filename |
| Resume memory | UserDefaults dict keyed by absolute path; save every 10 s + on close/quit; auto-resume when >30 s watched and <95 % done; entry cleared on finish |
| Distribution | App Sandbox ON (`user-selected.read-only`), hardened runtime, LGPL-only ffmpeg usage |

## Build system

Swift Package (executable target) + `Scripts/bundle.sh` assembling `dist/VidP.app`
(Info.plist, entitlements, ffmpeg resource, ad-hoc/dev codesign). Xcode can open
`Package.swift` directly. No xcodegen/tuist dependency.

## Files

```
Sources/VidP/
├── VidPApp.swift             @main, open handling, window, alerts
├── PlayerView.swift          NSViewRepresentable → AVPlayerView
├── PlaybackController.swift  routing native vs remux, AVPlayer lifecycle, resume wiring
├── RemuxService.swift        argv builder, Process runner, cascade, temp cleanup
├── ResumeStore.swift         position persistence + thresholds
Scripts/
├── build-ffmpeg.sh           minimal LGPL ffmpeg built from pinned source tarball
└── bundle.sh                 .app assembly + signing
```

## Playback flow

1. Open 1..n files via ⌘O panel, drag-drop on window/dock, or Finder.
2. Partition selection: first video file = feature; all `.srt`/`.vtt` = sidecars.
3. Container check by extension: `mp4/mov/m4v` → direct `AVPlayerItem`.
4. Else remux cascade (stream-copy only, `-movflags +faststart`):
   - Try 1: all streams, embedded subs→`mov_text`, sidecar SRTs appended as extra tracks.
   - Try 2: video+audio only (`-sn`) — weird/PGS subs.
   - Fail → error alert.
5. "Preparing…" spinner appears after 300 ms of remuxing.
6. Play; window title = filename; temp purged on close/quit/stale-sweep at launch.

## Remux argv contract

```
-y -i <video> [-i <srt> …]
-map 0:v? -map 0:a? -map 0:s? -map <n>:0 …
-c:v copy -c:a copy -c:s mov_text -f mp4 out.mp4
-metadata:s:s:<k> title=<sidecar filename>
```

Attempt 2 drops all `-map *:s?`/subtitle args and adds `-sn`.

## Sandbox & MAS compliance notes

- All file access from explicit user action (panel/drag-drop grants per-file read).
- Helper binary execution under sandbox is allowed (child inherits sandbox);
  helper must be same-Team-ID signed at distribution time.
- Fallback path if App Review objects to helper execution: link libav*
  (LGPL) inside an XPC service; `RemuxService` interface unchanged.
- Licensing: LGPL build required — no `--enable-gpl` components. Built from
  pinned ffmpeg source (`Scripts/ffmpeg-9.0.tar.xz.sha256`) with a pinned
  configure recipe (`Scripts/ffmpeg.recipe.sha256`); binary hash enforced at
  `Scripts/ffmpeg.sha256`. Configure quirk: subtitle codec flags use the C
  symbol `movtext`, while runtime `-c:s mov_text` uses the public name.

## Error handling

- Corrupt/unplayable input → alert after cascade exhaustion; app stays usable.
- ffmpeg stderr tail surfaced in alert detail.

## Testing

Unit: argv builder, selection partitioning, routing, ResumeStore round-trip/thresholds.
Manual matrix: MP4 direct · MKV+embedded subs · MKV+2 SRTs · corrupt file ·
PGS-sub MKV (falls back) · resume across relaunch · finish clears position.

## Explicitly out of scope (YAGNI)

Library grid, playlists, ASS styling preservation, mpv fallback engine, theming.
