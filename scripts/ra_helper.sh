#!/usr/bin/env bash
# ra_helper.sh - unified dialog-based menu for the mister-fpga-retroachievements
# toolkit. Runs on MiSTer. Requires `dialog` (ships standard with MiSTer Linux;
# MiSTer_SAM also uses it).
#
# Deployed as /media/fat/Scripts/RA_Helper.sh. Underlying helpers live in a
# sibling .ra/ dir (/media/fat/Scripts/.ra/) so they do not clutter the MiSTer
# main menu's Scripts browser -- that browser hides dotfile entries.
#
# Project: https://github.com/<your-org>/mister-fpga-retroachievements
# License: MIT

set -u

SCRIPT_VERSION="0.2.2"

SCRIPTS_DIR="$(dirname "$(readlink -f "$0")")/.ra"
TITLE="RetroAchievements Helper v${SCRIPT_VERSION}"

if ! command -v dialog >/dev/null 2>&1; then
  cat >&2 <<EOF
ERR: 'dialog' not found on this system.

RA_Helper.sh needs the 'dialog' utility. On MiSTer Linux:
  opkg update && opkg install dialog

Or invoke the helpers directly under:
  $SCRIPTS_DIR/ra_{on,off,status,update,rollback_binary}.sh
EOF
  exit 1
fi

if [ ! -d "$SCRIPTS_DIR" ]; then
  dialog --title "$TITLE" --msgbox \
    "Helper scripts directory not found:\n  $SCRIPTS_DIR\n\nRe-run install.sh from your workstation to deploy them." \
    10 60
  clear
  exit 1
fi

# Stream the helper's output into `dialog --programbox` so the user sees
# progress live (update fetches can take a minute or two; without streaming
# the menu looked frozen). Programbox keeps the box on screen after the
# command exits and waits for a keypress to dismiss.
run_and_show() {
  local label="$1"; shift
  local script="$1"; shift
  {
    "$SCRIPTS_DIR/$script" "$@" 2>&1
    _rc=$?
    echo
    echo "--- Done. Exit: $_rc. Press Enter to dismiss. ---"
  } | dialog --title "$label" --programbox 24 78
}

run_and_show_env() {
  local label="$1"; shift
  local env_kv="$1"; shift
  local script="$1"; shift
  {
    env "$env_kv" "$SCRIPTS_DIR/$script" "$@" 2>&1
    _rc=$?
    echo
    echo "--- Done. Exit: $_rc. Press Enter to dismiss. ---"
  } | dialog --title "$label" --programbox 24 78
}

show_readme() {
  dialog --title "About RA_Helper" --msgbox "\
RA_Helper is a menu front-end for the mister-fpga-retroachievements toolkit.
It wraps odelot's RetroAchievements-enabled build of MiSTer.

Menu actions:

 Status      Show current mode (RA vs stock) for each core + main binary.
             Read-only; safe to run any time.

 Turn ON     Replace stock core .rbf files with RA-enabled symlinks and
             re-apply odelot's MiSTer binary. Idempotent -- re-run after
             update_all to fix any drift.

 Turn OFF    Revert to stock cores. The main binary stays on odelot's
             build (it is backward-compatible with stock cores, so games
             without RA support still work fine).

 Update      Fetch the latest odelot binary + cores from GitHub. Any
             newly-published systems are auto-adopted. Needs internet.

 Rollback    Emergency: restore the original MiSTer binary from
             MiSTer.stock, strip the boot hook, and REBOOT. Use only if
             odelot's build is misbehaving.

Credentials live at /media/fat/retroachievements.cfg -- the 'password'
field is your RA ACCOUNT password (not a Web API key).

Softcore achievements only. Hardcore is disabled upstream because MiSTer
has no anti-tamper mechanism today." 24 76
}

confirm_update() {
  dialog --title "Update odelot assets" --yesno "\
This will query GitHub for the latest odelot binary and cores, then
download any that have changed. Core .rbf files can be several MB
each; expect 1-5 minutes on a typical connection.

Any previously-unseen system odelot has published will be
auto-adopted (equivalent to answering 'y' at the interactive prompt).

Proceed?" 13 66
}

confirm_rollback() {
  dialog --title "Rollback main binary" --yesno "\
This will restore /media/fat/MiSTer from MiSTer.stock, strip the
boot auto-restore hook, and REBOOT the device.

Your cores are NOT touched. If you also want stock cores back,
cancel now and run 'Turn RA cores OFF' first.

Continue?" 12 66 || return 1

  dialog --title "Really roll back?" --yesno "\
Last chance. The device will reboot within ~3 seconds of
pressing Yes.

Really roll back the main binary now?" 9 66
}

while true; do
  choice="$(dialog --stdout --clear --title "$TITLE" \
    --cancel-label "Exit" \
    --menu "Choose an action:" 17 72 9 \
    1 "Status               - show current RA/stock state" \
    2 "Turn RA cores ON     - activate RA-enabled cores" \
    3 "Turn RA cores OFF    - revert to stock cores" \
    4 "Update odelot assets - fetch latest binary + cores" \
    5 "View README          - what each option does" \
    6 "Rollback main binary - emergency restore + REBOOT" \
    7 "Exit")"
  rc=$?
  if [ "$rc" -ne 0 ] || [ -z "$choice" ]; then
    clear
    exit 0
  fi

  case "$choice" in
    1) run_and_show "Status" ra_status.sh ;;
    2) run_and_show "Turn RA cores ON" ra_on.sh ;;
    3) run_and_show "Turn RA cores OFF" ra_off.sh ;;
    4) confirm_update && run_and_show_env "Update odelot assets" "RA_UPDATE_ASSUME_YES=1" ra_update.sh ;;
    5) show_readme ;;
    6) confirm_rollback && run_and_show "Rollback main binary" ra_rollback_binary.sh ;;
    7) clear; exit 0 ;;
  esac
done
