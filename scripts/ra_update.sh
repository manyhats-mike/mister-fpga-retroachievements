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

SCRIPT_VERSION="0.1.0"

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
curl -sSL -o "$TMP/main_release.json" "$API/repos/$OWNER/Main_MiSTer/releases/latest"
main_url="$(grep -oE '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]*\.zip"' "$TMP/main_release.json" | head -1 | sed -E 's/.*"([^"]*)".*/\1/')"
main_tag="$(json_get "$TMP/main_release.json" tag_name)"
if [ -z "$main_url" ]; then
  echo "  no zip asset on latest release; skipping binary update"
else
  echo "  latest: $main_tag ($main_url)"
  curl -sSL -o "$TMP/main.zip" "$main_url"
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
curl -sSL -o "$TMP/repos.json" "$API/users/$OWNER/repos?per_page=100"
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
  curl -sSL -o "$TMP/rel.json" "$API/repos/$OWNER/$repo/releases/latest"
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
    if [ -t 0 ]; then
      printf "  NEW core detected: %s (basename=%s, tag=%s). Add? [y/N] " "$repo" "$inferred" "$tag"
      read -r ans
    else
      ans="n"
      echo "  NEW core $repo detected but stdin is not a tty; skipping (run interactively to adopt)"
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
    curl -sSL -o "${RA_DIR}/${basename}.rbf" "$rbf_url"
  else
    src_name="$(basename "$zip_url")"
    curl -sSL -o "$TMP/${repo}.zip" "$zip_url"
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
