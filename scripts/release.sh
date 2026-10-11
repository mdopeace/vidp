#!/usr/bin/env bash
# Release a new version to Homebrew users.
#
# Versioned-release model: ordinary commits never ship to users. Only when you
# run this script (a tagged release) do `brew update && brew upgrade vidp`
# deliver the change.
#
# `main` is branch-protected (no direct pushes), so the version bump goes
# through a PR which is opened and merged here via the GitHub CLI.
#
# Usage:
#   ./release.sh
#
# Requires: gh (authenticated), push access to the tap repo.
set -euo pipefail

REPO=mdopeace/vidp            # app repo (origin)
TAP=mdopeace/homebrew-vidp    # tap repo containing Casks/vidp.rb (binary distribution only)

cd "$(dirname "$0")/.."

# Read current version from Info.plist
CURRENT=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT"
NEXT_MAJOR="$((MAJOR + 1)).0.0"
NEXT_MINOR="$MAJOR.$((MINOR + 1)).0"
NEXT_PATCH="$MAJOR.$MINOR.$((PATCH + 1))"

if ! git diff --quiet; then
    echo "error: working tree is dirty. Commit your changes first." >&2
    exit 1
fi

# Version bump selector
echo "Release v$CURRENT — choose bump:"
select V in "$NEXT_PATCH" "$NEXT_MINOR" "$NEXT_MAJOR" "Abort"; do
    case "$V" in
        "") continue ;;
        "Abort") echo "Aborted."; exit 1 ;;
        *) break ;;
    esac
done

# Confirmation prompt
echo "This will release v$V:"
echo "  - Bump version in Info.plist"
echo "  - Create & merge PR to main"
echo "  - Tag v$V"
echo "  - Create GitHub Release"
echo "  - Update Homebrew tap cask"
read -p "Proceed? [y/N] " confirm || { echo "Aborted."; exit 1; }
[[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }

# 1. Bump version in Info.plist (short + full)
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $V" Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $V" Info.plist

# 2. Regenerate the app icon (no-op if the logo PNGs are unchanged) and
#    push the version bump to main via a PR (main is branch-protected)
BR="release/v$V"
git checkout -b "$BR"
./scripts/make-icns.sh
git add Info.plist resources/macos/vidp.icns
git commit -m "Bump version to $V"
git push -u origin "$BR"
gh pr create --base main --head "$BR" --title "Release v$V" \
    --body "Bumps the version to $V for release." >/dev/null
gh pr merge --merge --delete-branch
git checkout main
git fetch origin
git reset --hard origin/main

# 3. Build the app archive used by the in-app updater before publishing the
#    tag, so a packaging failure cannot leave an incomplete release.
./scripts/build.sh
ARCHIVE="vidp.app.zip"
CHECKSUM="$ARCHIVE.sha256"
# Also cleans the tap clone (step 5) and the parent dir its clone path implies,
# so a mid-release failure doesn't leave an untracked dir in the repo root.
# rmdir, not rm -rf, on the parent: it refuses when the dir still has contents.
trap 'rm -f "$ARCHIVE" "$CHECKSUM"; rm -rf "$TAP"; rmdir "$(dirname "$TAP")" 2>/dev/null || true' EXIT
rm -f "$ARCHIVE"
ditto -c -k --keepParent vidp.app "$ARCHIVE"
shasum -a 256 "$ARCHIVE" > "$CHECKSUM"

# 4. Tag the release (tags are not branch-protected) and attach both the app
#    archive and its checksum to the GitHub Release.
git tag "v$V"
git push origin "v$V"
gh release create "v$V" --title "v$V" --generate-notes "$ARCHIVE" "$CHECKSUM"

# 5. Update the tap: a cask, not a formula — only a cask can install an .app
#    to /Applications, and the app is self-contained so there's nothing to
#    compile on the user's machine.
SHA=$(awk '{print $1}' "$CHECKSUM")

rm -rf "$TAP"
git clone "https://github.com/$TAP" "$TAP"
F="$TAP/Casks/vidp.rb"
mkdir -p "$(dirname "$F")"
cat > "$F" <<RUBY
# frozen_string_literal: true

cask "vidp" do
  version "$V"
  sha256 "$SHA"

  url "https://github.com/$REPO/releases/download/v#{version}/vidp.app.zip"
  name "vidp"
  desc "Minimal keyboard-driven video player built on libmpv"
  homepage "https://github.com/$REPO"

  depends_on macos: :ventura

  app "vidp.app"

  # Ad-hoc signed, not notarized, so Gatekeeper blocks the first launch.
  postflight_steps do
    run "/usr/bin/xattr",
        args:         ["-dr", "com.apple.quarantine", "{{appdir}}/vidp.app"],
        must_succeed: false
  end
end
RUBY

# The migration must land in the same commit as the Formula deletion, or
# `brew upgrade` errors with "No available formula". Needs Homebrew >= 5.0.6.
rm -rf "$TAP/Formula"
printf '{\n  "vidp": "vidp"\n}\n' > "$TAP/tap_migrations.json"

(
    cd "$TAP"
    git checkout -b "vidp-v$V"
    git add -A
    git commit -m "vidp $V"
    git push -u origin "vidp-v$V"
    gh pr create --base main --head "vidp-v$V" --title "vidp $V" \
        --body "Releases vidp v$V." >/dev/null
    gh pr merge --merge --delete-branch
)

echo "Released v$V. Users can now: brew update && brew upgrade vidp"
