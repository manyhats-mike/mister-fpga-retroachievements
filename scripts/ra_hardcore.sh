#!/bin/sh
# ra_hardcore.sh - read or flip the 'hardcore=' field in
# /media/fat/retroachievements.cfg.
#
# odelot's binary reads this on next core load. v1.x of his binary
# enforces hardcore for the NES/FDS path only; other cores accept the
# flag but silently run as softcore. This helper does not validate
# core support -- it just edits the cfg.
#
# Usage:
#   ra_hardcore.sh [status]   show current state (default)
#   ra_hardcore.sh on         set hardcore=1
#   ra_hardcore.sh off        set hardcore=0
#   ra_hardcore.sh toggle     flip current value
#
# Exit codes:
#   0  success
#   1  cfg missing or unknown command
#
# Project: https://github.com/manyhats-mike/mister-fpga-retroachievements
# License: MIT

set -u

SCRIPT_VERSION="0.4.0"

CFG="/media/fat/retroachievements.cfg"

usage() {
  cat <<EOF
ra_hardcore v${SCRIPT_VERSION}
Manage the 'hardcore=' field in $CFG.

  ra_hardcore.sh [status]   show current state
  ra_hardcore.sh on         set hardcore=1
  ra_hardcore.sh off        set hardcore=0
  ra_hardcore.sh toggle     flip current value

Note: at upstream level today (odelot v1.x), only the NES/FDS path
actually enforces hardcore. Other cores accept the flag but silently
run as softcore. Changes take effect on next core load.
EOF
}

# Print 'on', 'off', or 'missing'. Anything other than 1/true/yes is OFF.
read_state() {
  if [ ! -f "$CFG" ]; then
    echo "missing"
    return
  fi
  v=$(awk -F= '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*hardcore[[:space:]]*=/ {
      val=$2; gsub(/[[:space:]]/, "", val); print val; exit
    }
  ' "$CFG")
  case "$v" in
    1|true|TRUE|yes|YES|on|ON) echo "on" ;;
    *)                          echo "off" ;;
  esac
}

set_state() {
  new="$1"
  if [ ! -f "$CFG" ]; then
    echo "ERR: $CFG not found." >&2
    echo "     odelot's binary must be deployed before toggling hardcore." >&2
    exit 1
  fi

  tmp="${CFG}.new.$$"
  if grep -qE '^[[:space:]]*hardcore[[:space:]]*=' "$CFG"; then
    # Replace first hardcore= line; drop any duplicates so the cfg
    # cannot end up with conflicting values.
    awk -v new="$new" '
      /^[[:space:]]*hardcore[[:space:]]*=/ {
        if (!done) { print "hardcore=" new; done=1 }
        next
      }
      { print }
    ' "$CFG" > "$tmp"
  else
    cp "$CFG" "$tmp"
    printf "\n# Hardcore mode (1=enabled, 0=disabled). Currently only the\n# NES/FDS path enforces hardcore upstream; other cores auto-softcore.\nhardcore=%s\n" "$new" >> "$tmp"
  fi

  mv -f "$tmp" "$CFG"
}

cmd="${1:-status}"

case "$cmd" in
  status|"")
    state=$(read_state)
    case "$state" in
      missing)
        echo "hardcore: $CFG missing"
        exit 1
        ;;
      *)
        echo "hardcore: $state"
        ;;
    esac
    ;;
  on)
    set_state 1
    echo "hardcore: on  (effective on next core load; NES/FDS only enforced upstream)"
    ;;
  off)
    set_state 0
    echo "hardcore: off (effective on next core load)"
    ;;
  toggle)
    cur=$(read_state)
    case "$cur" in
      on)
        set_state 0
        echo "hardcore: off (was on; effective on next core load)"
        ;;
      off)
        set_state 1
        echo "hardcore: on  (was off; effective on next core load; NES/FDS only enforced upstream)"
        ;;
      missing)
        echo "ERR: $CFG missing" >&2
        exit 1
        ;;
    esac
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    echo "ERR: unknown command: $cmd" >&2
    usage >&2
    exit 1
    ;;
esac
