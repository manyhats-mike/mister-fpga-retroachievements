#!/usr/bin/env bash
# ra_rollback_binary.sh - restore the upstream MiSTer binary captured at
# install time. Use this only if a future odelot binary release regresses
# and you need to fall back to stock. Also strips the boot auto-restore
# hook so the stock binary stays resident across reboots.
#
# Reboots the device at the end. Achievements stop working after this runs.
#
# Project: https://github.com/<your-org>/mister-fpga-retroachievements
# License: MIT

set -eu

SCRIPT_VERSION="0.1.0"

LIVE_BIN="/media/fat/MiSTer"
STOCK_BIN="/media/fat/MiSTer.stock"

echo "ra_rollback_binary v${SCRIPT_VERSION}"

[ -f "$STOCK_BIN" ] || { echo "ERR: no $STOCK_BIN backup found" >&2; exit 1; }

echo "Restoring stock binary over $LIVE_BIN ..."
cp -f "$STOCK_BIN" "$LIVE_BIN"
chmod +x "$LIVE_BIN"

hook="/media/fat/linux/user-startup.sh"
if [ -f "$hook" ] && grep -q "RA_AUTORESTORE_BEGIN" "$hook"; then
  awk '
    /RA_AUTORESTORE_BEGIN/ { skip=1; next }
    /RA_AUTORESTORE_END/   { skip=0; next }
    !skip
  ' "$hook" > "${hook}.new"
  mv "${hook}.new" "$hook"
  echo "Stripped RA auto-restore block from $hook"
fi

echo "Rebooting in 3 seconds... (Ctrl-C to abort)"
sleep 3
reboot
