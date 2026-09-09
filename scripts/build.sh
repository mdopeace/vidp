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

# Build the app icon from the IconKitchen assets (full set, no scaling needed).
ICONSET="AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
cp resources/macos/AppIcon16.png "$ICONSET/icon_16x16.png"
cp resources/macos/AppIcon32.png "$ICONSET/icon_16x16@2x.png"
cp resources/macos/AppIcon32.png "$ICONSET/icon_32x32.png"
cp resources/macos/AppIcon64.png "$ICONSET/icon_32x32@2x.png"
cp resources/macos/AppIcon128.png "$ICONSET/icon_128x128.png"
cp resources/macos/AppIcon256.png "$ICONSET/icon_128x128@2x.png"
cp resources/macos/AppIcon256.png "$ICONSET/icon_256x256.png"
cp resources/macos/AppIcon512.png "$ICONSET/icon_256x256@2x.png"
cp resources/macos/AppIcon512.png "$ICONSET/icon_512x512.png"
cp resources/macos/AppIcon1024.png "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/vidp.icns"
rm -rf "$ICONSET"

# Ad-hoc signing is mandatory on Apple Silicon.
codesign --force --sign - "$APP"

# Register with Launch Services so Finder offers vidp in "Open With".
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$PWD/$APP" 2>/dev/null

echo "Built $APP"
