#!/usr/bin/env bash
# Release a new version to Homebrew users.
#
# Versioned-release model: ordinary commits never ship to users. Only when you
# run this script (a tagged release) do `brew update && brew upgrade vidp`
# deliver the change.
#
# Usage:
#   ./release.sh 0.0.2
#
# Bumps the version in Info.plist, bumps the tap formula's url + sha256, then
# commits, tags, and pushes to both repos.
set -euo pipefail

V="${1:?usage: release.sh <version> e.g. ./release.sh 0.0.2}"
REPO=mdopeace/vidp            # app repo (origin)
TAP=mdopeace/homebrew-vidp    # tap repo containing Formula/vidp.rb

cd "$(dirname "$0")"

if ! git diff --quiet; then
    echo "error: working tree is dirty. Commit your changes first." >&2
    exit 1
fi

# 1. Bump version in Info.plist (short + full)
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $V" Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $V" Info.plist

# 2. Commit, tag, push the app repo
git add Info.plist
git commit -m "Bump version to $V"
git push origin HEAD
git tag "v$V"
git push origin "v$V"

# 3. Update the tap formula to point at the new tag + its checksum
SRC="https://github.com/$REPO/archive/refs/tags/v$V.tar.gz"
SHA=$(curl -sL "$SRC" | shasum -a 256 | awk '{print $1}')
F="$TAP/Formula/vidp.rb"

rm -rf "$TAP"
git clone "https://github.com/$TAP" "$TAP"
sed -i '' "s#tags/v[0-9.]*\.tar\.gz#tags/v$V.tar.gz#" "$F"
sed -i '' "s/sha256 \"[0-9a-f]*\"/sha256 \"$SHA\"/" "$F"
( cd "$TAP" && git add -A && git commit -m "vidp $V" && git push origin HEAD )
rm -rf "$TAP"

echo "Released v$V. Users can now: brew update && brew upgrade vidp"
