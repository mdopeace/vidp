#!/bin/bash
# Builds OTV.app — minimal libmpv-based video player.
set -euo pipefail
cd "$(dirname "$0")"

MPV_PREFIX="$(brew --prefix mpv 2>/dev/null || echo /opt/homebrew/opt/mpv)"
if [ ! -f "$MPV_PREFIX/lib/libmpv.dylib" ]; then
    echo "error: libmpv not found. Run: brew install mpv" >&2
    exit 1
fi

APP=OTV.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O -swift-version 5 \
    -framework AppKit \
    -I . \
    -Xcc -I"$MPV_PREFIX/include" \
    -L "$MPV_PREFIX/lib" \
    -lmpv \
    main.swift \
    -o "$APP/Contents/MacOS/OTV"

cp Info.plist "$APP/Contents/"

# Ad-hoc signing is mandatory on Apple Silicon.
codesign --force --sign - "$APP"

# Register with Launch Services so Finder offers OTV in "Open With".
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$PWD/$APP"

echo "Built $APP"
