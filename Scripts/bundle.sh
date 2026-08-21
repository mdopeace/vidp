#!/bin/zsh
# Builds release binary and assembles dist/VidP.app with sandbox entitlements
# and hardened runtime. Ad-hoc signed locally; use your Team ID for MAS.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="dist/VidP.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/VidP "$APP/Contents/MacOS/VidP"
cp Resources/ffmpeg "$APP/Contents/Resources/ffmpeg"
chmod +x "$APP/Contents/Resources/ffmpeg"
cp Scripts/Info.plist "$APP/Contents/Info.plist"

codesign --force --options runtime \
  --entitlements Scripts/entitlements.plist \
  --sign "${TEAM_ID:--}" \
  "$APP"

echo "Built $APP"
