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

# Ad-hoc signing is mandatory on Apple Silicon.
codesign --force --sign - "$APP"

# Register with Launch Services so Finder offers vidp in "Open With".
# Best-effort: sandboxed builds (e.g. Homebrew) deny it; macOS registers
# the app automatically on first launch instead.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$PWD/$APP" 2>/dev/null || echo "warning: lsregister denied, skipping (registers on first launch)" >&2

echo "Built $APP"
