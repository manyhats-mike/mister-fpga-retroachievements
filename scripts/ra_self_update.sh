#!/usr/bin/env bash
# ra_self_update.sh - fetch the latest tagged release of the
# mister-fpga-retroachievements toolkit from GitHub and replace the helper
# scripts on this MiSTer.
#
# Does NOT touch:
#   - odelot's MiSTer binary (use 'Update RA cores' / ra_update.sh)
#   - /media/fat/_RA_Cores/ (cores, manifest, .state)
#   - /media/fat/retroachievements.cfg (credentials)
#   - /media/fat/MiSTer.stock (rollback backup)
#   - /media/fat/linux/user-startup.sh (boot hook already installed)
#
# What it replaces:
#   /media/fat/Scripts/RA_Helper.sh
#   /media/fat/Scripts/.ra/ra_on.sh
#   /media/fat/Scripts/.ra/ra_off.sh
#   /media/fat/Scripts/.ra/ra_status.sh
#   /media/fat/Scripts/.ra/ra_update.sh
#   /media/fat/Scripts/.ra/ra_rollback_binary.sh
#   /media/fat/Scripts/.ra/ra_uninstall.sh
#   /media/fat/Scripts/.ra/ra_self_update.sh   (this script; via /tmp re-exec)
#   /media/fat/Scripts/.ra/VERSION
#   /media/fat/Scripts/.ra/CHANGELOG.md
#
# Safety:
#   1. Downloads and extracts the release tarball into /tmp first. If any
#      step fails before the copy phase, nothing on disk has changed.
#   2. Before overwriting, backs up the current .ra/ + RA_Helper.sh into
#      /media/fat/Scripts/.ra/.backup_<timestamp>/ so you can restore
#      manually if a bad release slips through.
#   3. Re-execs from /tmp so overwriting this script mid-run is safe.
#
# ENV:
#   RA_SELF_UPDATE_ASSUME_YES=1   skip the confirmation prompt (used by the
#                                 RA_Helper menu, which confirms separately).
#   RA_SELF_UPDATE_FORCE=1        re-install even if the current VERSION
#                                 already matches the latest release tag.
#
# Project: https://github.com/manyhats-mike/mister-fpga-retroachievements
# License: MIT

set -u

SCRIPT_VERSION="0.3.0"

REPO="manyhats-mike/mister-fpga-retroachievements"
API="https://api.github.com"

SCRIPTS_DIR="/media/fat/Scripts"
HELPERS_DIR="${SCRIPTS_DIR}/.ra"
MENU="${SCRIPTS_DIR}/RA_Helper.sh"
VERSION_FILE="${HELPERS_DIR}/VERSION"

echo "ra_self_update v${SCRIPT_VERSION}"

# Re-exec from /tmp so we can safely overwrite this file mid-run on FAT32.
SELF="$(readlink -f "$0" 2>/dev/null || echo "$0")"
if [ "$SELF" != "/tmp/ra_self_update.sh" ]; then
  cp -f "$SELF" /tmp/ra_self_update.sh
  chmod +x /tmp/ra_self_update.sh
  exec /tmp/ra_self_update.sh "$@"
fi

need() { command -v "$1" >/dev/null 2>&1 || { echo "ERR: missing tool '$1'" >&2; exit 1; }; }
need curl
need tar

# Mirror ra_update.sh's stale-CA-bundle fallback: some MiSTer images ship
# without a current CA bundle and curl exits 60 against github.com.
CURL_INSECURE=""
fetch() {
  _url="$1"; _out="$2"
  if [ -n "${CURL_INSECURE}" ]; then
    curl -fsSLk -o "$_out" "$_url"
    return
  fi
  _rc=0
  curl -fsSL -o "$_out" "$_url" || _rc=$?
  if [ "$_rc" -eq 0 ]; then return 0; fi
  if [ "$_rc" -eq 60 ] || [ "$_rc" -eq 77 ] || [ "$_rc" -eq 35 ]; then
    echo "  WARN: TLS verification failed (curl rc=$_rc). Falling back to --insecure." >&2
    CURL_INSECURE=1
    curl -fsSLk -o "$_out" "$_url"
    return
  fi
  return "$_rc"
}

# --- 1. ask GitHub for the latest release ---
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "== querying latest release =="
if ! fetch "$API/repos/$REPO/releases/latest" "$TMP/release.json"; then
  echo "ERR: failed to reach $API/repos/$REPO/releases/latest" >&2
  echo "     check the MiSTer's internet connection and try again." >&2
  exit 1
fi
if grep -q '"message"[[:space:]]*:[[:space:]]*"Not Found"' "$TMP/release.json"; then
  echo "ERR: no releases published yet on $REPO." >&2
  exit 1
fi

latest_tag="$(grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' "$TMP/release.json" | head -1 | sed -E 's/.*"([^"]*)".*/\1/')"
tarball_url="$(grep -oE '"tarball_url"[[:space:]]*:[[:space:]]*"[^"]*"' "$TMP/release.json" | head -1 | sed -E 's/.*"([^"]*)".*/\1/')"
[ -n "$latest_tag" ] || { echo "ERR: could not parse tag_name from release JSON" >&2; exit 1; }
[ -n "$tarball_url" ] || { echo "ERR: could not parse tarball_url from release JSON" >&2; exit 1; }

# Strip leading "v" for comparison.
latest_ver="${latest_tag#v}"

current_ver="unknown"
if [ -f "$VERSION_FILE" ]; then
  current_ver="$(tr -d ' \t\n\r' < "$VERSION_FILE" 2>/dev/null)"
  [ -n "$current_ver" ] || current_ver="unknown"
fi

echo "  installed: ${current_ver}"
echo "  latest   : ${latest_ver} (${latest_tag})"

if [ "$current_ver" = "$latest_ver" ] && [ "${RA_SELF_UPDATE_FORCE:-0}" != "1" ]; then
  echo "Already up to date. Nothing to do."
  echo "(set RA_SELF_UPDATE_FORCE=1 to re-install anyway.)"
  exit 0
fi

# --- 2. confirm ---
if [ "${RA_SELF_UPDATE_ASSUME_YES:-0}" != "1" ]; then
  printf "Install ${latest_tag}? [y/N] "
  read -r ans
  case "$ans" in
    y|Y|yes|YES) ;;
    *) echo "aborted."; exit 1 ;;
  esac
fi

# --- 3. download + extract tarball ---
echo "== downloading ${latest_tag} tarball =="
fetch "$tarball_url" "$TMP/release.tar.gz"

echo "== extracting =="
mkdir -p "$TMP/extracted"
tar -xzf "$TMP/release.tar.gz" -C "$TMP/extracted"

# GitHub tarballs extract into a single top-level dir like
# manyhats-mike-mister-fpga-retroachievements-<shortsha>/. Find it.
ROOT=""
for d in "$TMP/extracted"/*; do
  [ -d "$d" ] || continue
  ROOT="$d"
  break
done
[ -n "$ROOT" ] || { echo "ERR: tarball did not extract a root dir" >&2; exit 1; }

# --- 4. sanity-check the extracted tree BEFORE touching anything on disk ---
echo "== validating extracted tree =="
for f in \
  scripts/ra_helper.sh \
  scripts/ra_on.sh \
  scripts/ra_off.sh \
  scripts/ra_status.sh \
  scripts/ra_update.sh \
  scripts/ra_rollback_binary.sh \
  scripts/ra_uninstall.sh \
  scripts/ra_self_update.sh \
  VERSION \
  CHANGELOG.md
do
  if [ ! -f "$ROOT/$f" ]; then
    echo "ERR: expected file missing from tarball: $f" >&2
    echo "     aborting before any on-device changes." >&2
    exit 1
  fi
done
echo "  OK"

# --- 5. back up current scripts ---
ts="$(date +%Y%m%d-%H%M%S 2>/dev/null || echo manual)"
BACKUP="${HELPERS_DIR}/.backup_${ts}"
echo "== backing up current scripts to ${BACKUP} =="
mkdir -p "$BACKUP"
[ -f "$MENU" ] && cp "$MENU" "$BACKUP/RA_Helper.sh"
for s in "$HELPERS_DIR"/*.sh "$HELPERS_DIR/VERSION" "$HELPERS_DIR/CHANGELOG.md"; do
  [ -e "$s" ] || continue
  cp "$s" "$BACKUP/"
done
echo "  (restore with: cp $BACKUP/RA_Helper.sh $MENU ; cp $BACKUP/*.sh $HELPERS_DIR/ )"

# --- 6. install new scripts ---
echo "== installing new scripts =="
mkdir -p "$HELPERS_DIR"

install_file() {
  src="$1"; dst="$2"
  cp -f "$src" "$dst"
  chmod 755 "$dst" 2>/dev/null || true
  echo "  $dst"
}

install_file "$ROOT/scripts/ra_helper.sh" "$MENU"
for s in ra_on.sh ra_off.sh ra_status.sh ra_update.sh ra_rollback_binary.sh ra_uninstall.sh ra_self_update.sh; do
  install_file "$ROOT/scripts/$s" "$HELPERS_DIR/$s"
done

# VERSION + CHANGELOG are plain data, not executable.
cp -f "$ROOT/VERSION" "$VERSION_FILE"
cp -f "$ROOT/CHANGELOG.md" "$HELPERS_DIR/CHANGELOG.md"
echo "  $VERSION_FILE"
echo "  $HELPERS_DIR/CHANGELOG.md"

sync

echo
echo "== done. Installed ${latest_tag} (was ${current_ver}). =="
echo "Return to the menu and reopen it to pick up any layout changes."
