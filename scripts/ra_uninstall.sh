#!/usr/bin/env bash
# ra_uninstall.sh - completely remove the mister-fpga-retroachievements
# toolkit from the MiSTer.
#
# Steps:
#   1. Restore every stock core .rbf from .ra_stash/ (inline ra_off).
#   2. Copy MiSTer.stock over /media/fat/MiSTer so the stock binary is
#      resident before the boot hook is stripped.
#   3. Strip the RA_AUTORESTORE block from /media/fat/linux/user-startup.sh.
#   4. Delete /media/fat/_RA_Cores/, /media/fat/MiSTer.stock,
#      /media/fat/retroachievements.cfg, /media/fat/achievement.wav,
#      /media/fat/Scripts/RA_Helper.sh, /media/fat/Scripts/.ra/.
#   5. Reboot.
#
# Use this when odelot's RetroAchievements work lands in upstream MiSTer
# (no more need for a toggle layer), or when you otherwise want a fully
# clean stock-only device.
#
# ENV:
#   RA_UNINSTALL_ASSUME_YES=1   skip the interactive confirmation (used by
#                               the RA_Helper menu, which does its own
#                               two-level confirm before invoking this).
#   RA_KEEP_CFG=1               keep /media/fat/retroachievements.cfg
#                               instead of deleting it. The cfg contains
#                               your RA account password in plaintext, so
#                               the default is to wipe it.
#
# Project: https://github.com/manyhats-mike/mister-fpga-retroachievements
# License: MIT

set -u

SCRIPT_VERSION="0.3.0"

RA_DIR="/media/fat/_RA_Cores"
MANIFEST="${RA_DIR}/.manifest"
LIVE_BIN="/media/fat/MiSTer"
STOCK_BIN="/media/fat/MiSTer.stock"
CFG="/media/fat/retroachievements.cfg"
WAV="/media/fat/achievement.wav"
MENU="/media/fat/Scripts/RA_Helper.sh"
HELPERS_DIR="/media/fat/Scripts/.ra"
HOOK="/media/fat/linux/user-startup.sh"

echo "ra_uninstall v${SCRIPT_VERSION}"

# Re-exec from /tmp so we can safely delete $HELPERS_DIR (which contains
# this script) at the end without yanking the file out from under bash
# mid-run. FAT32 + BusyBox sh is not as forgiving as ext4 + GNU bash.
SELF="$(readlink -f "$0" 2>/dev/null || echo "$0")"
if [ "$SELF" != "/tmp/ra_uninstall.sh" ]; then
  cp -f "$SELF" /tmp/ra_uninstall.sh
  chmod +x /tmp/ra_uninstall.sh
  exec /tmp/ra_uninstall.sh "$@"
fi

if [ "${RA_UNINSTALL_ASSUME_YES:-0}" != "1" ]; then
  cat <<EOF

This will remove EVERYTHING the RetroAchievements toolkit installed and
REBOOT the device:

  - revert all cores to stock (.rbf files from .ra_stash/)
  - restore /media/fat/MiSTer from MiSTer.stock
  - strip the boot auto-restore hook
  - rm -rf /media/fat/_RA_Cores/
  - rm /media/fat/MiSTer.stock
  - rm /media/fat/achievement.wav
  - rm /media/fat/retroachievements.cfg  (credentials; set RA_KEEP_CFG=1 to preserve)
  - rm /media/fat/Scripts/RA_Helper.sh
  - rm -rf /media/fat/Scripts/.ra/

Your saved games, screenshots, and non-RA cores are NOT touched.

EOF
  printf "Type YES to continue: "
  read -r ans
  [ "$ans" = "YES" ] || { echo "aborted."; exit 1; }
fi

# --- 1. restore stock cores (inline ra_off, so uninstall still works if
# $HELPERS_DIR/ra_off.sh has already been removed or is broken) ---
if [ -f "$MANIFEST" ]; then
  echo "== restoring stock cores =="
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
else
  echo "== no manifest at $MANIFEST; skipping core restore =="
fi

# --- 2. restore stock MiSTer binary ---
echo "== restoring stock MiSTer binary =="
if [ -f "$STOCK_BIN" ]; then
  cp -f "$STOCK_BIN" "$LIVE_BIN"
  chmod +x "$LIVE_BIN"
  echo "  copied $STOCK_BIN -> $LIVE_BIN"
else
  echo "  WARN: no $STOCK_BIN backup found; leaving $LIVE_BIN as-is"
  echo "        (if /media/fat/MiSTer is odelot's binary you will need to"
  echo "         restore it manually via update_all or a fresh download.)"
fi

# --- 3. strip boot auto-restore hook ---
echo "== stripping boot auto-restore hook =="
if [ -f "$HOOK" ] && grep -q "RA_AUTORESTORE_BEGIN" "$HOOK"; then
  awk '
    /RA_AUTORESTORE_BEGIN/ { skip=1; next }
    /RA_AUTORESTORE_END/   { skip=0; next }
    !skip
  ' "$HOOK" > "${HOOK}.new"
  mv "${HOOK}.new" "$HOOK"
  echo "  stripped from $HOOK"
else
  echo "  no RA_AUTORESTORE block present; nothing to strip"
fi

# --- 4. delete deployed files ---
echo "== deleting toolkit files =="
[ -d "$RA_DIR"   ] && rm -rf "$RA_DIR"   && echo "  rm -rf $RA_DIR"
[ -f "$STOCK_BIN" ] && rm -f  "$STOCK_BIN" && echo "  rm $STOCK_BIN"
[ -f "$WAV"      ] && rm -f  "$WAV"      && echo "  rm $WAV"
[ -f "$MENU"     ] && rm -f  "$MENU"     && echo "  rm $MENU"
if [ "${RA_KEEP_CFG:-0}" = "1" ]; then
  echo "  keeping $CFG (RA_KEEP_CFG=1)"
elif [ -f "$CFG" ]; then
  rm -f "$CFG" && echo "  rm $CFG"
fi

# Self-delete: safe here because we re-exec'd from /tmp above.
[ -d "$HELPERS_DIR" ] && rm -rf "$HELPERS_DIR" && echo "  rm -rf $HELPERS_DIR"

sync

echo
echo "== done. Rebooting in 3 seconds... (Ctrl-C to abort) =="
sleep 3
reboot
