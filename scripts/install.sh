#!/usr/bin/env bash
# install.sh - bootstrap the mister-fpga-retroachievements toolkit onto a
# fresh MiSTer over FTP. Run this from your workstation (Linux, macOS, or
# WSL). It does not need to run on the MiSTer itself.
#
# What it does:
#   1. Downloads odelot's latest Main_MiSTer binary + every published core
#      .rbf for systems he supports (NES, SNES, Genesis, SMS, GB, N64, PSX
#      at time of v0.1.0; auto-discovered against GitHub at install time).
#   2. FTPs a SHA-verified copy of your current /media/fat/MiSTer to
#      /media/fat/MiSTer.stock as a rollback backup (if not already present).
#   3. Uploads the modified binary to /media/fat/_RA_Cores/MiSTer.ra, the
#      modified cores to /media/fat/_RA_Cores/*.rbf, the achievement.wav,
#      a placeholder /media/fat/retroachievements.cfg, and the manifest.
#   4. Uploads RA_Helper.sh (the dialog-based menu) to /media/fat/Scripts/ as
#      the single MiSTer-menu-visible entry, and uploads the five toggle
#      scripts to /media/fat/Scripts/.ra/ where the main menu hides them.
#   5. Appends a boot auto-restore block to /media/fat/linux/user-startup.sh
#      so update_all can never permanently displace odelot's binary.
#
# Usage:
#   MISTER_HOST=192.168.1.42 MISTER_USER=root MISTER_PASS=1 ./install.sh
#
# Environment variables (all optional except MISTER_HOST):
#   MISTER_HOST    IP/hostname of the MiSTer (required)
#   MISTER_USER    FTP username (default: root)
#   MISTER_PASS    FTP password (default: 1 - the MiSTer factory default)
#   STAGING_DIR    Local working directory (default: ./staging)
#
# Project: https://github.com/<your-org>/mister-fpga-retroachievements
# License: MIT

set -eu

SCRIPT_VERSION="0.2.1"

: "${MISTER_HOST:?MISTER_HOST is required (e.g. 192.168.1.42)}"
MISTER_USER="${MISTER_USER:-root}"
MISTER_PASS="${MISTER_PASS:-1}"
STAGING_DIR="${STAGING_DIR:-./staging}"

OWNER="odelot"
API="https://api.github.com"

SCRIPT_SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_SRC_DIR/.." && pwd)"

echo "install.sh v${SCRIPT_VERSION}"
echo "Target: ftp://${MISTER_USER}@${MISTER_HOST}/"
echo "Staging: $STAGING_DIR"
echo

need() { command -v "$1" >/dev/null 2>&1 || { echo "ERR: missing tool '$1'" >&2; exit 1; }; }
need curl; need unzip; need awk

mkdir -p "$STAGING_DIR/cores" "$STAGING_DIR/main"

# Use `ftp://HOST//abs/path` (double slash) so the path is absolute from
# the FS root rather than relative to the login home. MiSTer's default FTP
# home is `/root`, so single-slash URLs would fail with 550 / CWD errors.
ftp_url() { printf "ftp://%s//%s" "$MISTER_HOST" "${1#/}"; }

ftp_get() {
  curl -sS --connect-timeout 10 -u "${MISTER_USER}:${MISTER_PASS}" \
    -o "$2" "$(ftp_url "$1")"
}
ftp_put() {
  curl -sS --connect-timeout 10 -u "${MISTER_USER}:${MISTER_PASS}" \
    -T "$1" "$(ftp_url "$2")"
}
ftp_ls() {
  curl -sS --connect-timeout 10 -u "${MISTER_USER}:${MISTER_PASS}" \
    "$(ftp_url "$1")"
}
ftp_mkd() {
  curl -sS --connect-timeout 10 -u "${MISTER_USER}:${MISTER_PASS}" \
    --quote "MKD /${1#/}" "$(ftp_url "/")" 2>/dev/null || true
}

# --- 0. preflight ---
echo "== preflight: verifying MiSTer connectivity =="
if ! ftp_ls "/media/fat/" >/dev/null 2>&1; then
  echo "ERR: cannot list /media/fat/ on ${MISTER_HOST}. Is FTP enabled? Are host/user/password correct?" >&2
  exit 1
fi
echo "  OK"

# --- 1. fetch odelot Main_MiSTer latest release ---
echo "== fetching odelot/Main_MiSTer release =="
curl -sSL -o "$STAGING_DIR/main_release.json" "$API/repos/$OWNER/Main_MiSTer/releases/latest"
main_url="$(grep -oE '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]*\.zip"' "$STAGING_DIR/main_release.json" | head -1 | sed -E 's/.*"([^"]*)".*/\1/')"
main_tag="$(grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' "$STAGING_DIR/main_release.json" | head -1 | sed -E 's/.*"([^"]*)".*/\1/')"
[ -n "$main_url" ] || { echo "ERR: no zip asset on latest Main_MiSTer release" >&2; exit 1; }
echo "  tag=$main_tag"
curl -sSL -o "$STAGING_DIR/main.zip" "$main_url"
unzip -o "$STAGING_DIR/main.zip" -d "$STAGING_DIR/main" >/dev/null
MAIN_BIN="$(find "$STAGING_DIR/main" -maxdepth 3 -type f -name MiSTer | head -1)"
MAIN_WAV="$(find "$STAGING_DIR/main" -maxdepth 3 -type f -name achievement.wav | head -1)"
MAIN_CFG="$(find "$STAGING_DIR/main" -maxdepth 3 -type f -name retroachievements.cfg | head -1)"
[ -n "$MAIN_BIN" ] || { echo "ERR: MiSTer binary not found inside $main_url" >&2; exit 1; }

# --- 2. fetch every odelot/*_MiSTer core with a published release ---
echo "== discovering odelot/*_MiSTer cores =="
curl -sSL -o "$STAGING_DIR/repos.json" "$API/users/$OWNER/repos?per_page=100"
repos="$(grep -oE '"name"[[:space:]]*:[[:space:]]*"[^"]*_MiSTer"' "$STAGING_DIR/repos.json" | sed -E 's/.*"([^"]*)".*/\1/' | grep -v '^Main_MiSTer$' || true)"
[ -n "$repos" ] || { echo "ERR: no odelot/*_MiSTer repos found" >&2; exit 1; }

manifest_lines=""
for repo in $repos; do
  echo "-- $repo --"
  curl -sSL -o "$STAGING_DIR/rel_${repo}.json" "$API/repos/$OWNER/$repo/releases/latest"
  if grep -q '"message"[[:space:]]*:[[:space:]]*"Not Found"' "$STAGING_DIR/rel_${repo}.json"; then
    echo "  no releases yet - skipping"
    continue
  fi
  tag="$(grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' "$STAGING_DIR/rel_${repo}.json" | head -1 | sed -E 's/.*"([^"]*)".*/\1/')"
  rbf_url="$(grep -oE '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]*\.rbf"' "$STAGING_DIR/rel_${repo}.json" | head -1 | sed -E 's/.*"([^"]*)".*/\1/')"
  zip_url=""
  if [ -z "$rbf_url" ]; then
    zip_url="$(grep -oE '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]*\.zip"' "$STAGING_DIR/rel_${repo}.json" | head -1 | sed -E 's/.*"([^"]*)".*/\1/')"
  fi
  [ -n "$rbf_url" ] || [ -n "$zip_url" ] || { echo "  no .rbf or .zip asset; skipping"; continue; }

  basename="${repo%_MiSTer}"
  out="$STAGING_DIR/cores/${basename}.rbf"
  if [ -n "$rbf_url" ]; then
    src_name="$(basename "$rbf_url")"
    curl -sSL -o "$out" "$rbf_url"
  else
    src_name="$(basename "$zip_url")"
    curl -sSL -o "$STAGING_DIR/${repo}.zip" "$zip_url"
    unzip -o "$STAGING_DIR/${repo}.zip" -d "$STAGING_DIR/${repo}" >/dev/null
    inside="$(find "$STAGING_DIR/${repo}" -maxdepth 4 -type f -name '*.rbf' | head -1)"
    [ -n "$inside" ] || { echo "  ERR: no .rbf inside $src_name" >&2; continue; }
    cp "$inside" "$out"
  fi
  echo "  staged $basename.rbf (tag=$tag)"
  manifest_lines="${manifest_lines}${repo}|${basename}|/media/fat/_Console|${basename}_*.rbf|${tag}|${src_name}
"
done

# --- 3. back up live /media/fat/MiSTer to MiSTer.stock if missing ---
echo "== backing up stock MiSTer binary =="
if ftp_ls "/media/fat/" 2>/dev/null | grep -qE "\\sMiSTer\\.stock\$"; then
  echo "  /media/fat/MiSTer.stock already exists; leaving untouched"
else
  ftp_get "/media/fat/MiSTer" "$STAGING_DIR/MiSTer.stock"
  ftp_put "$STAGING_DIR/MiSTer.stock" "/media/fat/MiSTer.stock"
  echo "  uploaded /media/fat/MiSTer.stock"
fi

# --- 4. create remote _RA_Cores and push artifacts ---
echo "== uploading _RA_Cores payload =="
ftp_mkd "/media/fat/_RA_Cores"

ftp_put "$MAIN_BIN" "/media/fat/_RA_Cores/MiSTer.ra"
echo "  uploaded MiSTer.ra"

[ -n "$MAIN_WAV" ] && ftp_put "$MAIN_WAV" "/media/fat/achievement.wav" && echo "  uploaded achievement.wav"

# Install a placeholder cfg only if none exists remotely.
if ! ftp_ls "/media/fat/" 2>/dev/null | grep -qE "\\sretroachievements\\.cfg\$"; then
  tmp_cfg="$(mktemp)"
  cat "$PROJECT_ROOT/config/retroachievements.cfg.example" > "$tmp_cfg"
  ftp_put "$tmp_cfg" "/media/fat/retroachievements.cfg"
  rm -f "$tmp_cfg"
  echo "  uploaded placeholder retroachievements.cfg (FILL IN BEFORE USING)"
else
  echo "  retroachievements.cfg already present; leaving untouched"
fi

for rbf in "$STAGING_DIR"/cores/*.rbf; do
  [ -f "$rbf" ] || continue
  bn="$(basename "$rbf")"
  ftp_put "$rbf" "/media/fat/_RA_Cores/$bn"
  echo "  uploaded $bn"
done

# Build and upload the manifest.
tmp_manifest="$(mktemp)"
{
  echo "# repo|basename|stock_folder|stock_pattern|release_tag|rbf_source_name"
  printf "%s" "$manifest_lines"
} > "$tmp_manifest"
ftp_put "$tmp_manifest" "/media/fat/_RA_Cores/.manifest"
rm -f "$tmp_manifest"
echo "  uploaded .manifest"

# --- 5. upload toggle scripts + menu wrapper ---
echo "== uploading menu wrapper and toggle scripts =="
# RA_Helper.sh is the only entry visible in the MiSTer main menu's Scripts
# browser. The helpers it wraps live under .ra/ (dotfile dir; hidden from
# the browser by the same convention MiSTer_SAM uses for .MiSTer_SAM/).
ftp_mkd "/media/fat/Scripts/.ra"
ftp_put "$SCRIPT_SRC_DIR/ra_helper.sh" "/media/fat/Scripts/RA_Helper.sh"
curl -sS -u "${MISTER_USER}:${MISTER_PASS}" --quote "SITE CHMOD 755 /media/fat/Scripts/RA_Helper.sh" "$(ftp_url "/")" >/dev/null 2>&1 || true
echo "  uploaded RA_Helper.sh (MiSTer menu entry)"
for s in ra_on.sh ra_off.sh ra_status.sh ra_update.sh ra_rollback_binary.sh; do
  ftp_put "$SCRIPT_SRC_DIR/$s" "/media/fat/Scripts/.ra/$s"
  curl -sS -u "${MISTER_USER}:${MISTER_PASS}" --quote "SITE CHMOD 755 /media/fat/Scripts/.ra/$s" "$(ftp_url "/")" >/dev/null 2>&1 || true
  echo "  uploaded .ra/$s"
done

# --- 6. append boot auto-restore hook to user-startup.sh ---
echo "== installing boot auto-restore hook =="
tmp_startup="$STAGING_DIR/user-startup.sh"
if ! ftp_get "/media/fat/linux/user-startup.sh" "$tmp_startup"; then
  echo "#!/bin/sh" > "$tmp_startup"
fi
if grep -q "RA_AUTORESTORE_BEGIN" "$tmp_startup"; then
  echo "  hook already present; leaving untouched"
else
  cat >> "$tmp_startup" <<'EOF'

# RA_AUTORESTORE_BEGIN (managed by mister-fpga-retroachievements)
# Re-install odelot's MiSTer binary if anything overwrote it.
if [ "$1" = "start" ] || [ -z "$1" ]; then
  if [ -f /media/fat/_RA_Cores/MiSTer.ra ] && [ -f /media/fat/MiSTer ]; then
    if ! cmp -s /media/fat/MiSTer /media/fat/_RA_Cores/MiSTer.ra; then
      cp -f /media/fat/_RA_Cores/MiSTer.ra /media/fat/MiSTer
      chmod +x /media/fat/MiSTer
      logger -t RA "restored odelot MiSTer binary at boot" 2>/dev/null || true
    fi
  fi
fi
# RA_AUTORESTORE_END
EOF
  ftp_put "$tmp_startup" "/media/fat/linux/user-startup.sh"
  echo "  appended RA_AUTORESTORE block"
fi

cat <<EOF

== install complete ==

Next steps:
  1. Edit /media/fat/retroachievements.cfg on the MiSTer and replace the
     placeholder with your RA account username and password. The 'password'
     field expects your real account password, not a Web API key; it is
     only sent on first login, after which the rcheevos client caches a
     session token.
  2. Reboot the MiSTer. The boot hook installs odelot's MiSTer binary in
     place; rebooting lets the new binary take over.
  3. On the MiSTer main menu: Scripts -> RA_Helper. Use the menu to check
     status ('Status'), then activate cores ('Turn RA cores ON').
  4. Launch a game on a supported system to confirm the achievement set
     loads.

Toggle any time via the RA_Helper menu; no reboot needed for ON/OFF.
Helper scripts also live at /media/fat/Scripts/.ra/ if you prefer
invoking them directly from a shell.
EOF
