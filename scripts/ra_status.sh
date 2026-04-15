#!/usr/bin/env bash
# ra_status.sh - report current state of the RA setup.
#
# Output:
#   - whether the live /media/fat/MiSTer binary matches odelot's or stock
#   - per-core mode: RA, STOCK, MISSING, NONE, or DIRTY (drift detected)
#
# Project: https://github.com/manyhats-mike/mister-fpga-retroachievements
# License: MIT

set -eu

SCRIPT_VERSION="0.1.0"

RA_DIR="/media/fat/_RA_Cores"
MANIFEST="${RA_DIR}/.manifest"
STATE="${RA_DIR}/.state"
RA_BIN="${RA_DIR}/MiSTer.ra"
STOCK_BIN="/media/fat/MiSTer.stock"
LIVE_BIN="/media/fat/MiSTer"

echo "ra_status v${SCRIPT_VERSION}"
printf "Mode flag: %s\n" "$([ -f "$STATE" ] && cat "$STATE" || echo 'never toggled')"

if [ -f "$LIVE_BIN" ] && [ -f "$RA_BIN" ] && cmp -s "$LIVE_BIN" "$RA_BIN"; then
  bin_state="RA (odelot)"
elif [ -f "$LIVE_BIN" ] && [ -f "$STOCK_BIN" ] && cmp -s "$LIVE_BIN" "$STOCK_BIN"; then
  bin_state="STOCK"
else
  bin_state="UNKNOWN (does not match RA or STOCK backup)"
fi
printf "/media/fat/MiSTer : %s\n" "$bin_state"

[ -f "$MANIFEST" ] || { echo "No manifest yet - run ra_update.sh."; exit 0; }

printf "\n%-12s %-7s %s\n" "CORE" "STATE" "DETAILS"
printf "%-12s %-7s %s\n" "----" "-----" "-------"

while IFS='|' read -r repo basename stock_folder stock_pattern _rest; do
  [ -z "${repo:-}" ] && continue
  case "$repo" in \#*) continue ;; esac
  ra_rbf="${RA_DIR}/${basename}.rbf"
  stash="${stock_folder}/.ra_stash"

  state="STOCK"
  details=""
  symlink_count=0
  real_count=0
  symlink_example=""
  real_example=""
  for f in "$stock_folder"/$stock_pattern "$stock_folder/${basename}.rbf"; do
    [ -e "$f" ] || continue
    if [ -L "$f" ]; then
      tgt="$(readlink "$f")"
      if [ "$tgt" = "$ra_rbf" ]; then
        symlink_count=$((symlink_count + 1))
        symlink_example="$(basename "$f")"
      fi
    else
      real_count=$((real_count + 1))
      real_example="$(basename "$f")"
    fi
  done

  stashed_count=0
  if [ -d "$stash" ]; then
    for f in "$stash"/${basename}_*.rbf "$stash/${basename}.rbf"; do
      [ -e "$f" ] || continue
      stashed_count=$((stashed_count + 1))
    done
  fi

  if [ "$symlink_count" -gt 0 ] && [ "$real_count" -gt 0 ]; then
    state="DIRTY"
    details="symlink=$symlink_example, stock=$real_example (run ra_on to re-stash)"
  elif [ "$symlink_count" -gt 0 ]; then
    state="RA"
    details="-> $(basename "$ra_rbf") (${symlink_count} symlink(s), ${stashed_count} stashed)"
  elif [ "$real_count" -gt 0 ]; then
    state="STOCK"
    details="$real_example"
  elif [ ! -f "$ra_rbf" ]; then
    state="MISSING"
    details="RA core not downloaded (run ra_update.sh)"
  else
    state="NONE"
    details="no stock .rbf found"
  fi
  printf "%-12s %-7s %s\n" "$basename" "$state" "$details"
done < "$MANIFEST"
