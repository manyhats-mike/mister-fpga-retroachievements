#!/usr/bin/env bash
# release.sh - cut a GitHub release of the mister-fpga-retroachievements
# toolkit. Workstation-side; run from a clean main checkout.
#
# Pipeline:
#   1. Read VERSION (single source of truth).
#   2. Extract the matching section from CHANGELOG.md for release notes.
#   3. Verify the working tree is clean and we're on main.
#   4. Verify the tag doesn't already exist locally or remotely.
#   5. Tag vX.Y.Z on the current HEAD and push it.
#   6. Create the GitHub release via gh, attaching the extracted notes.
#
# Re-running after a failure at step 5 or 6 is safe: the script is
# idempotent up to each point (checks presence before creating).
#
# Usage:
#   scripts/release.sh              # release VERSION from main
#   scripts/release.sh --dry-run    # print actions, take none
#
# Requirements:
#   - gh CLI authenticated with repo push perms
#   - git, awk, sed
#
# Project: https://github.com/manyhats-mike/mister-fpga-retroachievements
# License: MIT

set -eu

SCRIPT_VERSION="0.3.0"

DRY_RUN=0
if [ "${1:-}" = "--dry-run" ]; then
  DRY_RUN=1
  shift || true
fi

cd "$(dirname "$0")/.."

[ -f VERSION ]      || { echo "ERR: VERSION file missing" >&2; exit 1; }
[ -f CHANGELOG.md ] || { echo "ERR: CHANGELOG.md missing"  >&2; exit 1; }

VERSION="$(tr -d ' \t\n\r' < VERSION)"
[ -n "$VERSION" ] || { echo "ERR: VERSION file is empty" >&2; exit 1; }
TAG="v${VERSION}"

echo "release.sh v${SCRIPT_VERSION}"
echo "  version: ${VERSION}"
echo "  tag    : ${TAG}"

# --- extract release notes ---
# Everything between "## [X.Y.Z]" (inclusive of the rest of that line)
# and the next "## [" header. Strip leading/trailing blank lines.
NOTES="$(awk -v ver="$VERSION" '
  BEGIN { printing = 0 }
  /^## \[/ {
    if (printing) exit
    if ($0 ~ "^## \\["ver"\\]") { printing = 1; next }
  }
  printing { print }
' CHANGELOG.md | awk '
  # trim leading blank lines
  NF || started { started = 1; lines[++n] = $0 }
  END {
    # trim trailing blank lines
    while (n > 0 && lines[n] ~ /^[[:space:]]*$/) n--
    for (i = 1; i <= n; i++) print lines[i]
  }
')"

if [ -z "$NOTES" ]; then
  echo "ERR: no CHANGELOG section found for [${VERSION}]" >&2
  echo "     expected a heading like '## [${VERSION}] - YYYY-MM-DD'" >&2
  exit 1
fi

echo
echo "--- release notes ---"
echo "$NOTES"
echo "--- end notes ---"
echo

# --- preflight: clean tree, on main, tag not taken ---
if [ -n "$(git status --porcelain)" ]; then
  echo "ERR: working tree has uncommitted changes. Commit or stash first." >&2
  exit 1
fi

branch="$(git symbolic-ref --quiet --short HEAD || echo 'DETACHED')"
if [ "$branch" != "main" ]; then
  echo "WARN: not on main (currently on '$branch'). Proceeding anyway." >&2
fi

if git rev-parse "refs/tags/${TAG}" >/dev/null 2>&1; then
  echo "ERR: local tag ${TAG} already exists." >&2
  echo "     delete with: git tag -d ${TAG} (and on remote: git push --delete origin ${TAG})" >&2
  exit 1
fi

if git ls-remote --exit-code --tags origin "refs/tags/${TAG}" >/dev/null 2>&1; then
  echo "ERR: remote tag ${TAG} already exists on origin." >&2
  exit 1
fi

# --- tag + push + release ---
if [ "$DRY_RUN" = "1" ]; then
  echo "[dry-run] git tag -a ${TAG} -m 'Release ${TAG}'"
  echo "[dry-run] git push origin ${TAG}"
  echo "[dry-run] gh release create ${TAG} --title ${TAG} --notes <...>"
  exit 0
fi

echo "== tagging =="
git tag -a "$TAG" -m "Release ${TAG}"

echo "== pushing tag =="
git push origin "$TAG"

echo "== creating GitHub release =="
NOTES_FILE="$(mktemp)"
printf '%s\n' "$NOTES" > "$NOTES_FILE"
trap 'rm -f "$NOTES_FILE"' EXIT

gh release create "$TAG" \
  --title "$TAG" \
  --notes-file "$NOTES_FILE"

echo
echo "== released ${TAG} =="
echo "URL:"
gh release view "$TAG" --json url --jq '.url' || true
