#!/usr/bin/env bash
# Point the Homebrew tap's cask at a published release binary and open the PR.
#
# A cask, not a formula: only a cask can install an .app to /Applications.
#
# Usage:
#   scripts/update-tap.sh <version> <sha256>
#   scripts/update-tap.sh <version> <sha256> --dry-run
#
# --dry-run prints the cask to stdout and touches no git, so the generated
# file can be diffed against the live one.
#
# Set TAP_DIR to operate on an existing checkout (CI) instead of cloning one.
#
# Requires: gh (authenticated), push access to the tap repo.
set -euo pipefail

REPO=mdopeace/vidp            # app repo, for building the download URL
TAP=mdopeace/homebrew-vidp    # tap repo containing Casks/vidp.rb

VERSION=${1:?usage: update-tap.sh <version> <sha256> [--dry-run]}
SHA256=${2:?usage: update-tap.sh <version> <sha256> [--dry-run]}
MODE=${3:-}

CASK=$(cat <<EOF
# frozen_string_literal: true

cask "vidp" do
  version "$VERSION"
  sha256 "$SHA256"

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
EOF
)

if [ "$MODE" = "--dry-run" ]; then
    printf '%s\n' "$CASK"
    exit 0
fi

# Default to the clone path the .gitignore already excludes. TAP_DIR lets CI
# hand over an authenticated checkout instead of cloning one here.
TAP_DIR=${TAP_DIR:-$TAP}
CLONED=""
if [ ! -d "$TAP_DIR/.git" ]; then
    # rm -rf, not just clone: a leftover non-repo dir would make clone fail.
    rm -rf "$TAP_DIR"
    git clone "https://github.com/$TAP" "$TAP_DIR"
    CLONED=1
fi
# Also cleans the parent dir the clone path implies, so a mid-release failure
# doesn't leave an untracked dir in the repo root.
cleanup() {
    if [ -n "$CLONED" ]; then
        rm -rf "$TAP_DIR"
        rmdir "$(dirname "$TAP_DIR")" 2>/dev/null || true
    fi
    return 0
}
trap cleanup EXIT

# The migration must land in the same commit as the Formula deletion, or
# `brew upgrade` errors with "No available formula". Needs Homebrew >= 5.0.6.
# Both already happened in 0.13.0, so this is a no-op on every release after.
rm -rf "$TAP_DIR/Formula"
printf '{\n  "vidp": "vidp"\n}\n' > "$TAP_DIR/tap_migrations.json"
mkdir -p "$TAP_DIR/Casks"
printf '%s\n' "$CASK" > "$TAP_DIR/Casks/vidp.rb"

(
    cd "$TAP_DIR"
    BR="vidp-v$VERSION"
    git checkout -b "$BR"
    git add -A
    git commit -m "vidp $VERSION"
    # Clear any branch a failed run left behind: a re-run for the same version
    # has a different commit, so a plain push would be rejected as
    # non-fast-forward.
    git push --quiet origin ":$BR" 2>/dev/null || true
    git push -u origin "$BR"
    # gh pr create prints the URL on stdout; keep it for the failure handler below.
    TAP_PR_URL=$(gh pr create --base main --head "$BR" --title "vidp $VERSION" \
        --body "Releases vidp v$VERSION.")
    # Runs after the GitHub Release is already published, so a failure here is a
    # half-published release: v$VERSION is live but Homebrew still serves the
    # previous version. Name the PR instead of aborting silently.
    gh pr merge --merge --delete-branch || {
        echo "error: could not merge the tap PR, so Homebrew is not updated yet." >&2
        echo "       GitHub Release v$VERSION IS published — only the tap update failed." >&2
        echo "       Merge this PR to finish, then 'brew update && brew upgrade vidp':" >&2
        echo "         $TAP_PR_URL" >&2
        exit 1
    }
)

echo "Tap updated to vidp $VERSION"