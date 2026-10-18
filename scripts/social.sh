#!/bin/bash
# Renders docs/social.png (1200x630) from docs/social.html.
#
# A separate script from screenshots.sh because this one needs no permissions:
# headless Chrome draws the page itself, rather than capturing a real window.
set -euo pipefail
cd "$(dirname "$0")/.."

CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
if [ ! -x "$CHROME" ]; then
    echo "error: Chrome not found. Set CHROME=/path/to/chrome" >&2
    exit 1
fi

"$CHROME" --headless --disable-gpu --hide-scrollbars \
    --force-device-scale-factor=1 \
    --window-size=1200,630 \
    --screenshot=docs/social.png \
    "file://$PWD/docs/social.html"

echo "wrote docs/social.png"