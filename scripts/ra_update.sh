#!/usr/bin/env bash
# ra_update.sh - fetch the latest odelot RA binary + cores from GitHub.
#
# Auto-discovers *_MiSTer repos on odelot's GitHub profile. Known repos are
# updated silently; previously-unseen repos prompt before being adopted.
#
# Manifest format (pipe-delimited, one entry per core):
#   repo|basename|stock_folder|stock_pattern|release_tag|rbf_source_name
# Comments start with "#".
#
# Project: https://github.com/<your-org>/mister-fpga-retroachievements
# License: MIT

set -eu

SCRIPT_VERSION="0.2.2"

RA_DIR="/media/fat/_RA_Cores"
MANIFEST="${RA_DIR}/.manifest"
RA_BIN="${RA_DIR}/MiSTer.ra"
LIVE_BIN="/media/fat/MiSTer"
STOCK_BIN="/media/fat/MiSTer.stock"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$RA_DIR"
[ -f "$MANIFEST" ] || { echo "# repo|basename|stock_folder|stock_pattern|release_tag|rbf_source_name" > "$MANIFEST"; }

OWNER="odelot"
API="https://api.github.com"

need() { command -v "$1" >/dev/null 2>&1 || { echo "ERR: missing tool '$1'" >&2; exit 1; }; }
need curl; need unzip

# MiSTer's BusyBox image often ships without a current CA bundle, so curl
# exits 60 ("unable to get local issuer certificate") against github.com.
# Try verified first; on TLS errors, warn once and fall back to --insecure
# for the rest of the run. We're pulling public GitHub release assets
# identified by tag name, so the downgrade is acceptable here.
CURL_INSECURE=""
fetch() {
  _url="$1"; _out="$2"
  if [ -n "${CURL_INSECURE}" ]; then
    curl -sSLk -o "$_out" "$_url"
    return
  fi
  _rc=0
  curl -sSL -o "$_out" "$_url" || _rc=$?
  if [ "$_rc" -eq 0 ]; then return 0; fi
  if [ "$_rc" -eq 60 ] || [ "$_rc" -eq 77 ] || [ "$_rc" -eq 35 ]; then
    echo "  WARN: TLS verification failed (curl rc=$_rc). Likely a stale CA bundle on this device; falling back to --insecure for the rest of this run." >&2
    CURL_INSECURE=1
    curl -sSLk -o "$_out" "$_url"
    return
  fi
  return "$_rc"
}

json_get() {
  grep -oE "\"$2\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$1" | head -1 | sed -E 's/.*:[[:space:]]*"([^"]*)".*/\1/'
}

default_stock_folder_for() {
  # Every odelot-supported system to date lives under _Console. Override by
  # editing the manifest line after first download if you need a different
  # folder (e.g. _Computer for home-computer cores).
  echo "/media/fat/_Console"
}

echo "ra_update v${SCRIPT_VERSION}"

# ---- 1. update Main binary from odelot/Main_MiSTer ----
echo "== checking odelot/Main_MiSTer =="
fetch "$API/repos/$OWNER/Main_MiSTer/releases/latest" "$TMP/main_release.json"
main_url="$(grep -oE '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]*\.zip"' "$TMP/main_release.json" | head -1 | sed -E 's/.*"([^"]*)".*/\1/')"
main_tag="$(json_get "$TMP/main_release.json" tag_name)"
if [ -z "$main_url" ]; then
  echo "  no zip asset on latest release; skipping binary update"
else
  echo "  latest: $main_tag ($main_url)"
  echo "  downloading main binary zip (~1-2 MB)..."
  fetch "$main_url" "$TMP/main.zip"
  echo "  extracting..."
  unzip -o "$TMP/main.zip" -d "$TMP/main" >/dev/null
  found="$(find "$TMP/main" -maxdepth 3 -type f -name MiSTer | head -1)"
  if [ -n "$found" ]; then
    if [ ! -f "$RA_BIN" ] || ! cmp -s "$found" "$RA_BIN"; then
      cp -f "$found" "$RA_BIN"
      chmod +x "$RA_BIN"
      echo "  updated $RA_BIN (tag=$main_tag)"
    else
      echo "  $RA_BIN already current"
    fi
    wav="$(find "$TMP/main" -maxdepth 3 -type f -name achievement.wav | head -1)"
    cfg="$(find "$TMP/main" -maxdepth 3 -type f -name retroachievements.cfg | head -1)"
    [ -n "$wav" ] && [ ! -f /media/fat/achievement.wav ] && cp "$wav" /media/fat/achievement.wav
    if [ -n "$cfg" ] && [ ! -f /media/fat/retroachievements.cfg ]; then
      cp "$cfg" /media/fat/retroachievements.cfg
      chmod 600 /media/fat/retroachievements.cfg 2>/dev/null || true
      echo "  installed default /media/fat/retroachievements.cfg (fill in credentials!)"
    fi
    if [ -f "$LIVE_BIN" ] && [ ! -f "$STOCK_BIN" ] && ! cmp -s "$LIVE_BIN" "$RA_BIN"; then
      cp "$LIVE_BIN" "$STOCK_BIN"
      chmod +x "$STOCK_BIN"
      echo "  captured $STOCK_BIN as first-time backup"
    fi
  else
    echo "  WARN: no MiSTer binary found inside zip" >&2
  fi
fi

# ---- 2. enumerate odelot's *_MiSTer repos ----
echo "== enumerating odelot/*_MiSTer repos =="
fetch "$API/users/$OWNER/repos?per_page=100" "$TMP/repos.json"
repos="$(grep -oE '"name"[[:space:]]*:[[:space:]]*"[^"]*_MiSTer"' "$TMP/repos.json" | sed -E 's/.*"([^"]*)".*/\1/' | grep -v '^Main_MiSTer$' || true)"
if [ -z "$repos" ]; then
  echo "  (none found)"
  exit 0
fi
echo "  found: $(echo "$repos" | tr '\n' ' ')"

manifest_known() {
  grep -E "^${1}\|" "$MANIFEST" || true
}
manifest_replace_line() {
  tmp="$(mktemp)"
  grep -vE "^${1}\|" "$MANIFEST" > "$tmp" || true
  echo "$2" >> "$tmp"
  mv "$tmp" "$MANIFEST"
}
manifest_tag_for() {
  grep -E "^${1}\|" "$MANIFEST" | head -1 | awk -F'|' '{print $5}'
}

# ---- 3. for each repo, fetch latest release asset if changed ----
for repo in $repos; do
  echo "-- $repo --"
  fetch "$API/repos/$OWNER/$repo/releases/latest" "$TMP/rel.json"
  if grep -q '"message"[[:space:]]*:[[:space:]]*"Not Found"' "$TMP/rel.json"; then
    echo "  no releases yet - skipping"
    continue
  fi
  tag="$(json_get "$TMP/rel.json" tag_name)"
  rbf_url="$(grep -oE '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]*\.rbf"' "$TMP/rel.json" | head -1 | sed -E 's/.*"([^"]*)".*/\1/')"
  zip_url=""
  if [ -z "$rbf_url" ]; then
    zip_url="$(grep -oE '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]*\.zip"' "$TMP/rel.json" | head -1 | sed -E 's/.*"([^"]*)".*/\1/')"
  fi
  if [ -z "$rbf_url" ] && [ -z "$zip_url" ]; then
    echo "  no .rbf or .zip asset - skipping"
    continue
  fi

  known_line="$(manifest_known "$repo")"
  known_tag="$(manifest_tag_for "$repo")"
  if [ -z "$known_line" ]; then
    inferred="${repo%_MiSTer}"
    if [ "${RA_UPDATE_ASSUME_YES:-0}" = "1" ]; then
      ans="y"
      echo "  NEW core $repo: auto-adopting (RA_UPDATE_ASSUME_YES=1; basename=$inferred, tag=$tag)"
    elif [ -t 0 ]; then
      printf "  NEW core detected: %s (basename=%s, tag=%s). Add? [y/N] " "$repo" "$inferred" "$tag"
      read -r ans
    else
      ans="n"
      echo "  NEW core $repo detected but stdin is not a tty; skipping (run interactively or set RA_UPDATE_ASSUME_YES=1 to adopt)"
    fi
    [ "$ans" = "y" ] || [ "$ans" = "Y" ] || { echo "  skipping $repo"; continue; }
    basename="$inferred"
    stock_folder="$(default_stock_folder_for "$basename")"
    stock_pattern="${basename}_*.rbf"
  else
    basename="$(echo "$known_line" | awk -F'|' '{print $2}')"
    stock_folder="$(echo "$known_line" | awk -F'|' '{print $3}')"
    stock_pattern="$(echo "$known_line" | awk -F'|' '{print $4}')"
  fi

  if [ "$known_tag" = "$tag" ] && [ -f "${RA_DIR}/${basename}.rbf" ]; then
    echo "  already up to date (tag=$tag)"
    continue
  fi

  if [ -n "$rbf_url" ]; then
    src_name="$(basename "$rbf_url")"
    echo "  downloading $src_name (core .rbf, several MB)..."
    fetch "$rbf_url" "${RA_DIR}/${basename}.rbf"
  else
    src_name="$(basename "$zip_url")"
    echo "  downloading $src_name (zipped core, several MB)..."
    fetch "$zip_url" "$TMP/${repo}.zip"
    echo "  extracting..."
    unzip -o "$TMP/${repo}.zip" -d "$TMP/${repo}" >/dev/null
    inside="$(find "$TMP/${repo}" -maxdepth 4 -type f -name '*.rbf' | head -1)"
    if [ -z "$inside" ]; then
      echo "  ERR: no .rbf inside $src_name" >&2
      continue
    fi
    cp "$inside" "${RA_DIR}/${basename}.rbf"
  fi
  echo "  downloaded ${basename}.rbf (tag=$tag, src=$src_name)"
  manifest_replace_line "$repo" "${repo}|${basename}|${stock_folder}|${stock_pattern}|${tag}|${src_name}"
done

echo "== update complete =="
