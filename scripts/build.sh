#!/bin/bash
# Builds vidp.app — minimal libmpv-based video player.
set -euo pipefail
cd "$(dirname "$0")/.."

MPV_PREFIX="${MPV_PREFIX:-$(brew --prefix mpv 2>/dev/null || echo /opt/homebrew/opt/mpv)}"
if [ ! -f "$MPV_PREFIX/lib/libmpv.dylib" ]; then
    echo "error: libmpv not found. Run: brew install mpv" >&2
    exit 1
fi

APP=vidp.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 \
    -framework AppKit \
    -framework MediaPlayer \
    -F/System/Library/PrivateFrameworks \
    -framework PIP \
    -import-bridging-header vidp-Bridging-Header.h \
    -I . \
    -Xcc -I"$MPV_PREFIX/include" \
    -L "$MPV_PREFIX/lib" \
    -lmpv \
    -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
    Sources/*.swift \
    -o "$APP/Contents/MacOS/vidp"

cp Info.plist "$APP/Contents/"

# App icon is prebuilt (iconutil can't run inside the Homebrew sandbox).
# It regenerates automatically on every ./scripts/release.sh run;
# to rebuild it by hand: ./scripts/make-icns.sh (on your Mac, then commit it).
if [ ! -f resources/macos/vidp.icns ]; then
    echo "error: resources/macos/vidp.icns missing. Run ./scripts/make-icns.sh on your Mac and commit it." >&2
    exit 1
fi
cp resources/macos/vidp.icns "$APP/Contents/Resources/vidp.icns"

# GPL requires the licence text to travel with the distribution, and release
# builds copy libmpv/FFmpeg into the bundle -- so ship the notices inside it.
cp LICENSES.md "$APP/Contents/Resources/LICENSES.md"

# Bundle the libmpv closure so the app is self-contained. The cask ships a
# prebuilt binary, and a binary still linked to /opt/homebrew/... only launches
# on the machine that built it — so without this, `brew install vidp` would
# need a separate `brew install mpv` and would break on every other Mac.
FRAMEWORKS="$APP/Contents/Frameworks"
mkdir -p "$FRAMEWORKS"

# libmpv alone pulls in ~47 more non-system dylibs (ffmpeg, libplacebo, x264,
# x265, rubberband, ...), so this has to recurse rather than copy one.
#
# The queue holds each dylib's path in the Cellar, not its copy in the bundle:
# a dependency recorded as @rpath/X (brotli does this for libbrotlicommon) has
# no absolute path to copy, but it ships beside its parent, so the parent's own
# directory is what resolves it. Queueing the bundle copy instead resolved
# @rpath against Contents/Frameworks and silently dropped the dylib.
QUEUE=$(mktemp)
trap 'rm -f "$QUEUE" "$QUEUE.next"' EXIT
printf '%s\n' "$APP/Contents/MacOS/vidp" > "$QUEUE"
while [ -s "$QUEUE" ]; do
    : > "$QUEUE.next"
    while read -r cur; do
        otool -L "$cur" 2>/dev/null | tail -n +2 | awk '{print $1}' | while read -r dep; do
            case "$dep" in /System/* | /usr/lib/*) continue ;; esac
            case "$dep" in @rpath/*) dep="$(dirname "$cur")/${dep#@rpath/}" ;; esac
            [ -e "$dep" ] || { echo "warning: missing $dep, skipping" >&2; continue; }
            # Keep the symlink's own name (libavcodec.63.dylib) rather than the
            # versioned Cellar name — it's what LC_LOAD_DYLIB records, so the
            # -change below matches without a second lookup.
            name=$(basename "$dep")
            [ -f "$FRAMEWORKS/$name" ] && continue
            cp -L "$dep" "$FRAMEWORKS/$name"
            printf '%s\n' "$dep" >> "$QUEUE.next"
        done
    done < "$QUEUE"
    mv "$QUEUE.next" "$QUEUE"
done

# Repoint every recorded reference at the bundled copy. Match on the literal
# string in LC_LOAD_DYLIB, not the symlink target, or the rewrite silently no-ops.
for f in "$FRAMEWORKS"/*.dylib "$APP/Contents/MacOS/vidp"; do
    while read -r dep; do
        case "$dep" in /System/* | /usr/lib/*) continue ;; esac
        install_name_tool -change "$dep" "@rpath/$(basename "$dep")" "$f" 2>/dev/null || true
    done < <(otool -L "$f" | tail -n +2 | awk '{print $1}')
    case "$f" in *.dylib) install_name_tool -id "@rpath/$(basename "$f")" "$f" ;; esac
done

# Fail loudly rather than shipping a binary that only runs on the build machine.
if otool -L "$APP/Contents/MacOS/vidp" "$FRAMEWORKS"/*.dylib | grep -q "/opt/homebrew/"; then
    echo "error: unbundled Homebrew paths remain in the dylib closure" >&2
    otool -L "$APP/Contents/MacOS/vidp" "$FRAMEWORKS"/*.dylib | grep "/opt/homebrew/" >&2
    exit 1
fi

# Ad-hoc signing is mandatory on Apple Silicon, and nested code must be signed
# inside-out — the dylibs before the bundle that contains them.
for f in "$FRAMEWORKS"/*.dylib; do
    codesign --force --sign - "$f"
done
codesign --force --sign - "$APP"

# Register with Launch Services so Finder offers vidp in "Open With".
# Best-effort: sandboxed builds (e.g. Homebrew) deny it; macOS registers
# the app automatically on first launch instead.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$PWD/$APP" 2>/dev/null || echo "warning: lsregister denied, skipping (registers on first launch)" >&2

echo "Built $APP"
