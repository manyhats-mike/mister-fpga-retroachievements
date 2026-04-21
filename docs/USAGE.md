# Usage

Day-to-day recipes. The primary entry point on the MiSTer is the
`RA_Helper` menu under the main menu's Scripts list; direct shell
invocation of the helpers is documented at the bottom as a fallback.

## The menu (recommended)

From the MiSTer main menu: **Scripts → RA_Helper**.

`RA_Helper` is a `dialog`-based menu with these entries:

| Entry | What it runs | Destructive? |
|-------|--------------|--------------|
| Status | `.ra/ra_status.sh` | no (read-only) |
| Turn RA cores ON | `.ra/ra_on.sh` | no (idempotent) |
| Turn RA cores OFF | `.ra/ra_off.sh` | no (idempotent) |
| Updates ▸ Update RA cores (odelot) | `.ra/ra_update.sh` (`RA_UPDATE_ASSUME_YES=1`) | no, but downloads from GitHub |
| Updates ▸ Update toolkit (scripts) | `.ra/ra_self_update.sh` (`RA_SELF_UPDATE_ASSUME_YES=1`) | no (keeps timestamped backup of prior scripts) |
| Updates ▸ View changelog | `dialog --textbox` on `.ra/CHANGELOG.md` | no (read-only) |
| View README | inline help text | no |
| Rollback main binary | `.ra/ra_rollback_binary.sh` after two confirmations | **yes — reboots** |
| Uninstall toolkit | `.ra/ra_uninstall.sh` after two confirmations | **yes — wipes everything + reboots** |

Output from each script is captured and shown in a scrollable text box
so you can read what happened before returning to the menu.

## Check current state

From the menu: **Status**. Sample output:

```
ra_status v0.2.0
Mode flag: ON
/media/fat/MiSTer : RA (odelot)

CORE         STATE   DETAILS
----         -----   -------
NES          RA      -> NES.rbf (1 symlink(s), 1 stashed)
SNES         RA      -> SNES.rbf (1 symlink(s), 1 stashed)
MegaDrive    STOCK   MegaDrive_20250707.rbf
...
```

`STATE` values:

| Value | Meaning |
|-------|---------|
| `RA` | Symlink to `_RA_Cores/<name>.rbf` is in place |
| `STOCK` | Only the stock `.rbf` is present |
| `DIRTY` | Both a symlink and a real stock file exist — run Turn ON to fix |
| `MISSING` | `_RA_Cores/<name>.rbf` is not present; run Update |
| `NONE` | Neither stock nor RA file is in the expected folder |

## Turn RetroAchievements on

From the menu: **Turn RA cores ON**.

For every core in `/media/fat/_RA_Cores/.manifest`:

- every stock `.rbf` matching the manifest pattern moves into
  `<stock_folder>/.ra_stash/`
- a symlink named like the stashed file takes its place, pointing at
  the odelot core under `_RA_Cores/`

Also re-applies odelot's main binary to `/media/fat/MiSTer` if
`update_all` has overwritten it since the last activation.

No reboot required. Any launcher (Zaparoo, NFC, MGL, main menu) will
resolve through the symlink and load the RA-enabled core.

## Turn RetroAchievements off

From the menu: **Turn RA cores OFF**.

Removes the symlinks, moves stashed files back. Does **not** revert the
main binary — odelot's binary is backward-compatible with stock cores and
stays resident for no-reboot toggling.

## Pull the latest odelot binary + cores

From the menu: **Updates ▸ Update RA cores (odelot)**. Confirms once, then
runs.

Queries GitHub for every `odelot/*_MiSTer` repo, downloads the latest
release assets into `_RA_Cores/`, and updates `_RA_Cores/.manifest`.

- Known cores update silently when the release tag changes.
- **New** cores (systems odelot publishes after your install) are
  auto-adopted when run from the menu (`RA_UPDATE_ASSUME_YES=1`).

After updates, run **Turn RA cores ON** again if RA mode was on, so the
new binary / cores are actually in effect.

## Pull the latest version of this toolkit's scripts

From the menu: **Updates ▸ Update toolkit (scripts)**. Fetches the latest
tagged release of `manyhats-mike/mister-fpga-retroachievements` from
GitHub, validates the extracted tarball, then replaces the helpers under
`/media/fat/Scripts/RA_Helper.sh` and `/media/fat/Scripts/.ra/`. Prior
scripts are copied to `/media/fat/Scripts/.ra/.backup_<timestamp>/` before
overwriting so a bad release can be rolled back manually.

This does **not** touch odelot's binary, the modified cores, your
credentials, or the boot hook. Run **Update RA cores (odelot)** for those.

Equivalent CLI:

```sh
/media/fat/Scripts/.ra/ra_self_update.sh
# force a re-install even if already on the latest tag:
RA_SELF_UPDATE_FORCE=1 /media/fat/Scripts/.ra/ra_self_update.sh
```

## View the changelog from the device

From the menu: **Updates ▸ View changelog**. Opens the shipped
`CHANGELOG.md` in a scrollable `dialog` textbox so you can see what
changed in each release without leaving the device.

## After running `update_all`

If `update_all` pulled fresh stock `.rbf` files while RA mode was on,
Status will show `DIRTY` for the affected cores. Fix by running **Turn
RA cores ON** — it is idempotent and will re-stash the new stock file,
leaving the symlink in place.

If `update_all` rewrote `/media/fat/MiSTer` with the upstream stock
binary, the next reboot's auto-restore hook will replace it with
`_RA_Cores/MiSTer.ra`. You can force it immediately without rebooting
by running **Turn RA cores ON** too.

## Emergency rollback of the main binary

From the menu: **Rollback main binary**. Asks for confirmation twice,
then restores `/media/fat/MiSTer.stock` over `/media/fat/MiSTer`,
strips the boot auto-restore hook, and reboots. Use if an odelot binary
update breaks something and you need the stock MiSTer experience back.

Your cores are untouched by this; if you want stock cores back too, run
**Turn RA cores OFF** first, then the rollback.

## Removing the toolkit entirely

From the menu: **Uninstall toolkit**. Confirms twice, then does the full
sequence in one shot and reboots:

1. reverts every RA symlink, restores the stashed stock `.rbf` files
2. copies `MiSTer.stock` over `/media/fat/MiSTer`
3. strips the `RA_AUTORESTORE` block from `user-startup.sh`
4. deletes `/media/fat/_RA_Cores/`, `MiSTer.stock`, `achievement.wav`,
   `retroachievements.cfg` (credentials), `Scripts/RA_Helper.sh`, and
   `Scripts/.ra/`
5. reboots

Set `RA_KEEP_CFG=1` in the environment if you want
`/media/fat/retroachievements.cfg` preserved; by default it is deleted
because it stores your RA account password in plaintext.

Saved games, screenshots, and cores for non-RA systems are not touched.

Equivalent CLI invocation:

```sh
/media/fat/Scripts/.ra/ra_uninstall.sh
# or non-interactively:
RA_UNINSTALL_ASSUME_YES=1 /media/fat/Scripts/.ra/ra_uninstall.sh
```

If the uninstall script is missing or broken, the manual steps are:

```sh
/media/fat/Scripts/.ra/ra_off.sh               # restore stock cores
/media/fat/Scripts/.ra/ra_rollback_binary.sh   # restore stock binary + reboot
# after reboot:
rm -rf /media/fat/_RA_Cores
rm /media/fat/MiSTer.stock
rm /media/fat/retroachievements.cfg
rm /media/fat/achievement.wav
rm /media/fat/Scripts/RA_Helper.sh
rm -rf /media/fat/Scripts/.ra
```

The boot hook is already stripped by `ra_rollback_binary.sh`.

## Direct shell invocation (fallback)

If you'd rather skip the menu (scripting, SSH sessions, etc.) the
helpers are still individually callable:

```sh
/media/fat/Scripts/.ra/ra_status.sh
/media/fat/Scripts/.ra/ra_on.sh
/media/fat/Scripts/.ra/ra_off.sh
/media/fat/Scripts/.ra/ra_update.sh
/media/fat/Scripts/.ra/ra_rollback_binary.sh
/media/fat/Scripts/.ra/ra_uninstall.sh
```

Their behavior is unchanged from when they lived under `/media/fat/Scripts/`
directly in v0.1.0 — only the path moved. `ra_update.sh` still prompts
interactively for new-core adoption unless `RA_UPDATE_ASSUME_YES=1` is
set in the environment.
