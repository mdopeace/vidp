#!/bin/bash
# Builds WO.app — minimal libmpv-based video player.
set -euo pipefail
cd "$(dirname "$0")"

MPV_PREFIX="$(brew --prefix mpv 2>/dev/null || echo /opt/homebrew/opt/mpv)"
if [ ! -f "$MPV_PREFIX/lib/libmpv.dylib" ]; then
    echo "error: libmpv not found. Run: brew install mpv" >&2
    exit 1
fi

APP=WO.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 \
    -framework AppKit \
    -framework MediaPlayer \
    -framework AVKit \
    -I . \
    -Xcc -I"$MPV_PREFIX/include" \
    -L "$MPV_PREFIX/lib" \
    -lmpv \
    main.swift \
    -o "$APP/Contents/MacOS/WO"

cp Info.plist "$APP/Contents/"
cp WO.icns "$APP/Contents/Resources/"

# Regenerate the icon if the script or icns are missing.
if [ ! -f WO.icns ]; then
    swift make_icon.swift "$PWD" && iconutil -c icns AppIcon.iconset -o WO.icns
    cp WO.icns "$APP/Contents/Resources/"
fi

# Ad-hoc signing is mandatory on Apple Silicon.
codesign --force --sign - "$APP"

# Register with Launch Services so Finder offers WO in "Open With".
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$PWD/$APP" 2>/dev/null

echo "Built $APP"
