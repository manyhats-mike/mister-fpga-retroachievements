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
| Update odelot assets | `.ra/ra_update.sh` (with `RA_UPDATE_ASSUME_YES=1`) | no, but downloads from GitHub |
| View README | inline help text | no |
| Rollback main binary | `.ra/ra_rollback_binary.sh` after two confirmations | **yes — reboots** |

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

From the menu: **Update odelot assets**. Confirms once, then runs.

Queries GitHub for every `odelot/*_MiSTer` repo, downloads the latest
release assets into `_RA_Cores/`, and updates `_RA_Cores/.manifest`.

- Known cores update silently when the release tag changes.
- **New** cores (systems odelot publishes after your install) are
  auto-adopted when run from the menu (`RA_UPDATE_ASSUME_YES=1`).

After updates, run **Turn RA cores ON** again if RA mode was on, so the
new binary / cores are actually in effect.

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
```

Their behavior is unchanged from when they lived under `/media/fat/Scripts/`
directly in v0.1.0 — only the path moved. `ra_update.sh` still prompts
interactively for new-core adoption unless `RA_UPDATE_ASSUME_YES=1` is
set in the environment.
