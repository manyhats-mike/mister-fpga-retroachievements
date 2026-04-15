#!/usr/bin/env bash
# ra_off.sh - deactivate RA-enabled cores; restore stock .rbf files.
#
# For each manifest entry:
#   - removes any symlinks in the stock folder that point at the RA core
#   - moves stashed originals from <stock_folder>/.ra_stash/ back into place
#
# Does NOT swap the MiSTer binary. odelot's binary is backward-compatible
# with stock cores (it only activates RA logic when a core cooperates by
# exposing RAM to DDRAM), so leaving it resident is safe. If you need to
# fully revert to the upstream MiSTer binary, use ra_rollback_binary.sh.
#
# Project: https://github.com/manyhats-mike/mister-fpga-retroachievements
# License: MIT

set -eu

SCRIPT_VERSION="0.1.0"

RA_DIR="/media/fat/_RA_Cores"
MANIFEST="${RA_DIR}/.manifest"
STATE="${RA_DIR}/.state"

[ -f "$MANIFEST" ] || { echo "ERR: $MANIFEST missing" >&2; exit 1; }

echo "== ra_off v${SCRIPT_VERSION}: restoring stock cores =="

while IFS='|' read -r repo basename stock_folder stock_pattern _rest; do
  [ -z "${repo:-}" ] && continue
  case "$repo" in \#*) continue ;; esac
  stash="${stock_folder}/.ra_stash"
  ra_rbf="${RA_DIR}/${basename}.rbf"

  for f in "$stock_folder"/$stock_pattern "$stock_folder/${basename}.rbf"; do
    [ -L "$f" ] || continue
    tgt="$(readlink "$f")"
    if [ "$tgt" = "$ra_rbf" ]; then
      rm -f "$f"
      echo "  $basename: removed symlink $(basename "$f")"
    fi
  done

  if [ -d "$stash" ]; then
    for f in "$stash"/${basename}_*.rbf "$stash"/${basename}.rbf; do
      [ -e "$f" ] || continue
      mv -f "$f" "$stock_folder/"
      echo "  $basename: restored $(basename "$f")"
    done
    rmdir "$stash" 2>/dev/null || true
  fi
done < "$MANIFEST"

echo "OFF" > "$STATE"
echo "== done =="
