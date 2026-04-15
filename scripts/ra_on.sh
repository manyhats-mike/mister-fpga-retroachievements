#!/usr/bin/env bash
# ra_on.sh - activate RetroAchievements-enabled cores on MiSTer.
#
# For each entry in /media/fat/_RA_Cores/.manifest:
#   - moves every stock .rbf matching the pattern into <stock_folder>/.ra_stash/
#   - creates a symlink at the stashed file's original path pointing to the
#     corresponding /media/fat/_RA_Cores/<basename>.rbf
#   - restores odelot's MiSTer binary from /media/fat/_RA_Cores/MiSTer.ra
#     in case update_all (or anything else) overwrote it.
#
# Idempotent: re-running reapplies the current manifest, useful after
# update_all pulls fresh stock cores or overwrites the live binary.
#
# Project: https://github.com/manyhats-mike/mister-fpga-retroachievements
# License: MIT

set -eu

SCRIPT_VERSION="0.1.0"

RA_DIR="/media/fat/_RA_Cores"
MANIFEST="${RA_DIR}/.manifest"
STATE="${RA_DIR}/.state"
RA_BIN="${RA_DIR}/MiSTer.ra"
LIVE_BIN="/media/fat/MiSTer"

[ -f "$MANIFEST" ] || { echo "ERR: $MANIFEST missing; run ra_update.sh first" >&2; exit 1; }

restore_binary() {
  if [ -f "$RA_BIN" ] && ! cmp -s "$LIVE_BIN" "$RA_BIN"; then
    echo "  binary: updating $LIVE_BIN to odelot's build"
    cp -f "$RA_BIN" "$LIVE_BIN"
    chmod +x "$LIVE_BIN"
  else
    echo "  binary: already odelot"
  fi
}

echo "== ra_on v${SCRIPT_VERSION}: activating RetroAchievements mode =="
restore_binary

while IFS='|' read -r repo basename stock_folder stock_pattern _rest; do
  [ -z "${repo:-}" ] && continue
  case "$repo" in \#*) continue ;; esac
  ra_rbf="${RA_DIR}/${basename}.rbf"
  if [ ! -f "$ra_rbf" ]; then
    echo "  $basename: SKIP (missing $ra_rbf; run ra_update.sh)"
    continue
  fi
  stash="${stock_folder}/.ra_stash"
  mkdir -p "$stash"

  moved=0
  for f in "$stock_folder"/$stock_pattern; do
    [ -e "$f" ] || continue
    if [ -L "$f" ]; then
      cur_target="$(readlink "$f")"
      if [ "$cur_target" != "$ra_rbf" ]; then
        ln -snf "$ra_rbf" "$f"
        echo "  $basename: repointed symlink $(basename "$f")"
      fi
      continue
    fi
    mv -f "$f" "$stash/"
    ln -s "$ra_rbf" "$f"
    echo "  $basename: stashed $(basename "$f"), symlinked RA core"
    moved=$((moved + 1))
  done
  if [ "$moved" -eq 0 ] && [ -z "$(ls -A "$stash" 2>/dev/null | grep -E "^${basename}_" || true)" ]; then
    target="${stock_folder}/${basename}.rbf"
    if [ ! -e "$target" ]; then
      ln -s "$ra_rbf" "$target"
      echo "  $basename: no stock .rbf found; created bare symlink $(basename "$target")"
    fi
  fi
done < "$MANIFEST"

echo "ON" > "$STATE"
echo "== done. Reload a core (or reboot) for changes to take effect. =="
