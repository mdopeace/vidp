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
TAP=mdopeace/homebrew-vidp    # tap repo containing Formula/vidp.rb

cd "$(dirname "$0")"

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
OPTIONS=("$NEXT_PATCH" "$NEXT_MINOR" "$NEXT_MAJOR")
LABELS=("Patch" "Minor" "Major")
DESCS=("→ $NEXT_PATCH" "→ $NEXT_MINOR" "→ $NEXT_MAJOR")
ACTIVE=0
SELECTED=0
COUNT=${#OPTIONS[@]}

draw_menu() {
    for ((i=0; i<COUNT; i++)); do
        if [[ $i -eq $ACTIVE ]]; then
            printf "\033[2K  ◉ %s %s\n" "${LABELS[$i]}" "${DESCS[$i]}"
        else
            printf "\033[2K  ○ %s %s\n" "${LABELS[$i]}" "${DESCS[$i]}"
        fi
    done
    printf "\033[%dA" "$COUNT"
}

echo "Release v$CURRENT — choose bump:"
echo ""
draw_menu

trap 'printf "\033[%dE" "$COUNT"; stty echo; exit' INT
stty -echo

while true; do
    read -rsn1 KEY
    case "$KEY" in
        $'\x1b')
            read -rsn2 KEY
            case "$KEY" in
                '[A') (( ACTIVE = (ACTIVE - 1 + COUNT) % COUNT )) ;;
                '[B') (( ACTIVE = (ACTIVE + 1) % COUNT )) ;;
            esac
            ;;
        " ") SELECTED=$ACTIVE ;;
        "")
            stty echo
            printf "\033[%dE" "$COUNT"
            V="${OPTIONS[$SELECTED]}"
            break
            ;;
    esac
    draw_menu
done

# Confirmation prompt
echo "This will release v$V:"
echo "  - Bump version in Info.plist"
echo "  - Create & merge PR to main"
echo "  - Tag v$V"
echo "  - Create GitHub Release"
echo "  - Update Homebrew tap"
read -p "Proceed? [y/N] " answer
[[ "$answer" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }

# 1. Bump version in Info.plist (short + full)
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $V" Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $V" Info.plist

# 2. Push the version bump to main via a PR (main is branch-protected)
BR="release/v$V"
git checkout -b "$BR"
git add Info.plist
git commit -m "Bump version to $V"
git push -u origin "$BR"
gh pr create --base main --head "$BR" --title "Release v$V" \
    --body "Bumps the version to $V for release." >/dev/null
gh pr merge --merge --delete-branch
git checkout main
git pull --ff-only origin main

# 3. Tag the release (tags are not branch-protected)
git tag "v$V"
git push origin "v$V"

# 4. Create a GitHub Release with auto-generated notes
gh release create "v$V" --title "v$V" --generate-notes

# 5. Update the tap formula to point at the new tag + its checksum
SRC="https://github.com/$REPO/archive/refs/tags/v$V.tar.gz"
SHA=$(curl -sL "$SRC" | shasum -a 256 | awk '{print $1}')

rm -rf "$TAP"
git clone "https://github.com/$TAP" "$TAP"
F="$TAP/Formula/vidp.rb"
sed -i '' "s#tags/v[0-9.]*\.tar\.gz#tags/v$V.tar.gz#" "$F"
sed -i '' "s/sha256 \"[0-9a-f]*\"/sha256 \"$SHA\"/" "$F"
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
rm -rf "$TAP"

echo "Released v$V. Users can now: brew update && brew upgrade vidp"
