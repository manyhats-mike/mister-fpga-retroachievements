#!/usr/bin/env bash
# ra_helper.sh - unified dialog-based menu for the mister-fpga-retroachievements
# toolkit. Runs on MiSTer. Requires `dialog` (ships standard with MiSTer Linux;
# MiSTer_SAM also uses it).
#
# Deployed as /media/fat/Scripts/RA_Helper.sh. Underlying helpers live in a
# sibling .ra/ dir (/media/fat/Scripts/.ra/) so they do not clutter the MiSTer
# main menu's Scripts browser -- that browser hides dotfile entries.
#
# Project: https://github.com/manyhats-mike/mister-fpga-retroachievements
# License: MIT

set -u

SCRIPT_VERSION="0.3.0"

SCRIPTS_DIR="$(dirname "$(readlink -f "$0")")/.ra"
TITLE="RetroAchievements Helper v${SCRIPT_VERSION}"

if ! command -v dialog >/dev/null 2>&1; then
  cat >&2 <<EOF
ERR: 'dialog' not found on this system.

RA_Helper.sh needs the 'dialog' utility. On MiSTer Linux:
  opkg update && opkg install dialog

Or invoke the helpers directly under:
  $SCRIPTS_DIR/ra_{on,off,status,update,rollback_binary,uninstall,self_update}.sh
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

 Updates     Submenu: update odelot's binary/cores, update the toolkit's
             own scripts from GitHub, or view the CHANGELOG.

 Rollback    Emergency: restore the original MiSTer binary from
             MiSTer.stock, strip the boot hook, and REBOOT. Use only if
             odelot's build is misbehaving.

 Uninstall   Nuke the toolkit: revert cores, restore stock binary, strip
             the hook, delete every file this toolkit installed (including
             credentials), then REBOOT. Use when you want a fully clean
             MiSTer (e.g. after odelot's work lands upstream).

Credentials live at /media/fat/retroachievements.cfg -- the 'password'
field is your RA ACCOUNT password (not a Web API key).

Softcore achievements only. Hardcore is disabled upstream because MiSTer
has no anti-tamper mechanism today." 30 76
}

show_changelog() {
  cl="$SCRIPTS_DIR/CHANGELOG.md"
  if [ ! -f "$cl" ]; then
    dialog --title "Changelog" --msgbox "\
No CHANGELOG.md is installed on this device.

It ships with the toolkit as of v0.3.0. Run 'Update toolkit' in the
Updates submenu to pick it up, or re-run install.sh from your
workstation." 10 66
    return
  fi
  dialog --title "Changelog (all releases)" --textbox "$cl" 30 90
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

confirm_self_update() {
  dialog --title "Update toolkit scripts" --yesno "\
This will fetch the latest tagged release of the toolkit from GitHub
(manyhats-mike/mister-fpga-retroachievements) and replace the helper
scripts on this device.

It does NOT touch:
  - odelot's binary / cores (use 'Update RA cores' for that)
  - your credentials or save data
  - the boot hook or _RA_Cores/

A backup of the current scripts is saved under
  /media/fat/Scripts/.ra/.backup_<timestamp>/
so you can restore manually if a bad release slips through.

Proceed?" 18 70
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

confirm_uninstall() {
  dialog --title "Uninstall toolkit" --yesno "\
This will REMOVE EVERYTHING the RetroAchievements toolkit installed
and REBOOT the device:

  - revert all cores to stock
  - restore /media/fat/MiSTer from MiSTer.stock
  - strip the boot auto-restore hook
  - delete /media/fat/_RA_Cores/ (RA cores, manifest)
  - delete /media/fat/MiSTer.stock (the backup)
  - delete /media/fat/retroachievements.cfg (your credentials)
  - delete /media/fat/achievement.wav
  - delete this menu and its helper scripts

Your saved games and non-RA cores are NOT touched.

Continue?" 20 70 || return 1

  dialog --title "Really uninstall?" --yesno "\
Last chance. Once you confirm, there is no undo -- the device will
reboot within a few seconds and the RetroAchievements toolkit will
be gone.

Really uninstall now?" 10 70
}

updates_menu() {
  while true; do
    choice="$(dialog --stdout --clear --title "$TITLE - Updates" \
      --cancel-label "Back" \
      --menu "Choose an update action:" 14 72 5 \
      1 "Update RA cores (odelot)   - fetch latest binary + cores" \
      2 "Update toolkit (scripts)   - fetch latest from GitHub" \
      3 "View changelog             - what changed in each release" \
      4 "Back to main menu")"
    rc=$?
    if [ "$rc" -ne 0 ] || [ -z "$choice" ] || [ "$choice" = "4" ]; then
      return 0
    fi
    case "$choice" in
      1) confirm_update && run_and_show_env "Update RA cores (odelot)" "RA_UPDATE_ASSUME_YES=1" ra_update.sh ;;
      2) confirm_self_update && run_and_show_env "Update toolkit (scripts)" "RA_SELF_UPDATE_ASSUME_YES=1" ra_self_update.sh ;;
      3) show_changelog ;;
    esac
  done
}

while true; do
  choice="$(dialog --stdout --clear --title "$TITLE" \
    --cancel-label "Exit" \
    --menu "Choose an action:" 17 72 8 \
    1 "Status               - show current RA/stock state" \
    2 "Turn RA cores ON     - activate RA-enabled cores" \
    3 "Turn RA cores OFF    - revert to stock cores" \
    4 "Updates              - update RA cores, scripts, view changelog" \
    5 "View README          - what each option does" \
    6 "Rollback main binary - emergency restore + REBOOT" \
    7 "Uninstall toolkit    - wipe everything + REBOOT" \
    8 "Exit")"
  rc=$?
  if [ "$rc" -ne 0 ] || [ -z "$choice" ]; then
    clear
    exit 0
  fi

  case "$choice" in
    1) run_and_show "Status" ra_status.sh ;;
    2) run_and_show "Turn RA cores ON" ra_on.sh ;;
    3) run_and_show "Turn RA cores OFF" ra_off.sh ;;
    4) updates_menu ;;
    5) show_readme ;;
    6) confirm_rollback && run_and_show "Rollback main binary" ra_rollback_binary.sh ;;
    7) confirm_uninstall && run_and_show_env "Uninstall toolkit" "RA_UNINSTALL_ASSUME_YES=1" ra_uninstall.sh ;;
    8) clear; exit 0 ;;
  esac
done
