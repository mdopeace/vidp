#!/bin/bash
# Renders docs/screenshots/*.png from the real vidp.app window.
#
# Unlike quicktodo's script, this cannot render off-screen: the video is an
# OpenGL layer, which does not draw into a cached bitmap. So the app is
# launched for real, driven with synthetic keystrokes, and its window is
# captured with `screencapture`.
#
# Needs Screen Recording (for screencapture) and Accessibility (for the
# keystrokes) for whatever runs this -- grant them to your terminal once:
#   System Settings > Privacy & Security > Screen Recording / Accessibility
#
# Requires: ffmpeg (ships with the mpv install this repo already needs).
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="docs/screenshots"
SRC="$PWD/vidp.app"
BUNDLE_ID=com.vidp.screenshots

if [ ! -d "$SRC" ]; then
    echo "error: vidp.app not found. Run ./scripts/build.sh first." >&2
    exit 1
fi
command -v ffmpeg >/dev/null || { echo "error: ffmpeg not found (brew install mpv pulls it in)" >&2; exit 1; }

WORK=$(mktemp -d)
# A fixed name so the HUD shows a stable title and meta line; the parser turns
# this into "Vidp Demo Clip" / "2024", which is what appears in the shots.
CLIP="$WORK/Vidp Demo Clip 2024.mp4"

# Run a re-signed copy under a throwaway bundle id. UserDefaults keys off the
# bundle id, so this reads app defaults instead of yours -- otherwise the shots
# bake in whatever fonts and colours you happen to have set, and regenerate
# differently on your machine than on anyone else's.
APP="$WORK/vidp.app"
cp -R "$SRC" "$APP"
codesign --force --deep --sign - "$APP"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP"

cleanup() {
    # Quit before deleting the clip it has open, or it relaunches.
    pkill -x vidp 2>/dev/null || true
    defaults delete "$BUNDLE_ID" 2>/dev/null || true
    rm -rf "$WORK"
}
trap cleanup EXIT

# gradients, not testsrc: a colour-bar test pattern reads as a test pattern.
# Long enough that the 3s HUD auto-hide never fires mid-shot.
# hqdn3d smooths the filter's dithering -- nothing real is lost from a
# synthetic gradient, and it takes each PNG from ~750KB to ~50KB.
ffmpeg -hide_banner -loglevel error \
    -f lavfi -i "gradients=s=1280x720:d=120:speed=0.03" \
    -vf "hqdn3d=2:2:3:3" -pix_fmt yuv420p -y "$CLIP"

mkdir -p "$OUT"

pkill -x vidp 2>/dev/null || true
open -a "$APP" "$CLIP"
sleep 5

# Window ids change every launch, so look them up rather than assume. The
# Settings sheet is a separate window, so find both by title.
cat > "$WORK/winswift.swift" <<'EOF'
import CoreGraphics
import Foundation
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                      kCGNullWindowID) as? [[String: Any]] ?? []
for w in list where (w[kCGWindowOwnerName as String] as? String) == "Vidp" {
    let name = w[kCGWindowName as String] as? String ?? ""
    let num = w[kCGWindowNumber as String] as? Int ?? -1
    guard let d = w[kCGWindowBounds as String] as? [String: Any] else { continue }
    print("\(name)\t\(num)\t\(Int(d["X"] as! Double)),\(Int(d["Y"] as! Double)),\(Int(d["Width"] as! Double)),\(Int(d["Height"] as! Double))")
}
EOF
swiftc -O "$WORK/winswift.swift" -o "$WORK/winswift"

# Columns are: title, window id, x,y,w,h
field() { "$WORK/winswift" | awk -F'\t' -v n="$1" -v c="$2" '$1 == n { split($3, r, ","); print (c == 2 ? $2 : r[c - 2]); exit }'; }

WIN=$(field "Vidp" 2)
RECT=$(field "Vidp" 3),$(field "Vidp" 4),$(field "Vidp" 5),$(field "Vidp" 6)
if [ -z "$WIN" ]; then
    echo "error: no Vidp window found. Is the app running?" >&2
    exit 1
fi

key() { # key <code> [modifier]
    local clause="key code $1"
    [ -n "${2:-}" ] && clause="$clause using {$2}"
    osascript -e 'tell application "Vidp" to activate' \
              -e "tell application \"System Events\" to $clause" >/dev/null
}

shot() { # shot <name> [settle] [capture-flag...]
    local name=$1 settle=${2:-0.6}
    shift 2 2>/dev/null || shift $#
    # -o drops the window shadow, -x drops the click sound. Give the animation
    # a beat to finish or the OSD is caught mid-fade.
    sleep "$settle"
    screencapture -x -o "$@" "$OUT/$name.png"
    # A Retina capture is ~2.5MB and the page shows these a few hundred px
    # wide, so 1200px is still 2x there.
    sips -Z 1200 "$OUT/$name.png" >/dev/null
    # Video frames, not flat UI: PNG leaves mpv's YUV->RGB dithering as noise
    # and lands ~800KB. JPEG q88 is ~56KB and indistinguishable at page size.
    ffmpeg -hide_banner -loglevel error -i "$OUT/$name.png" -q:v 12 -y "$OUT/$name.jpg"
    rm -f "$OUT/$name.png"
    printf '%s  %s  %s\n' "$name.jpg" \
        "$(sips -g pixelWidth -g pixelHeight "$OUT/$name.jpg" 2>/dev/null | awk '/pixel/{printf "%s ", $2}')" \
        "$(du -h "$OUT/$name.jpg" | cut -f1 | tr -d ' ')"
}

# Pause first: while playing, the HUD hides itself after 3s, and several shots
# need it up. Paused, it stays.
key 49                    # space
shot playing 0.6 -l"$WIN"

key 126                   # up arrow: volume OSD
shot volume 0.3 -l"$WIN"

key 124 "shift down"      # shift-right: the 30s skip indicator
shot skip 0.3 -l"$WIN"

# The Settings sheet is its own window, so -l would miss it -- a region
# capture of the player's rect is what catches both.
key 43 "command down"     # cmd-, : the Settings sheet
shot settings 0.8 -R"$RECT"

key 53                    # escape closes the sheet
sleep 0.5

echo "wrote $OUT/*.jpg"