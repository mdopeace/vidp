#!/bin/bash
# Builds vidp.app — minimal libmpv-based video player.
set -euo pipefail
cd "$(dirname "$0")"

MPV_PREFIX="$(brew --prefix mpv 2>/dev/null || echo /opt/homebrew/opt/mpv)"
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
    -I . \
    -Xcc -I"$MPV_PREFIX/include" \
    -L "$MPV_PREFIX/lib" \
    -lmpv \
    *.swift \
    -o "$APP/Contents/MacOS/vidp"

cp Info.plist "$APP/Contents/"

# Build the app icon from the brand asset with no compositing/background.
ICON_SRC="resources/web/icon-512-maskable.png"
ICONSET="AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
cp "$ICON_SRC" "$ICONSET/icon_512x512.png"
sips -z 1024 1024 "$ICON_SRC" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/vidp.icns"
rm -rf "$ICONSET"

# Ad-hoc signing is mandatory on Apple Silicon.
codesign --force --sign - "$APP"

# Register with Launch Services so Finder offers vidp in "Open With".
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$PWD/$APP" 2>/dev/null

echo "Built $APP"
