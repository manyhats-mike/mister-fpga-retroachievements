# Usage

Day-to-day recipes. All commands run on the MiSTer.

## Turn RetroAchievements on

```sh
/media/fat/Scripts/ra_on.sh
```

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

```sh
/media/fat/Scripts/ra_off.sh
```

Removes the symlinks, moves stashed files back. Does **not** revert the
main binary — odelot's binary is backward-compatible with stock cores and
stays resident for no-reboot toggling.

## Check current state

```sh
/media/fat/Scripts/ra_status.sh
```

Sample output:

```
ra_status v0.1.0
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
| `DIRTY` | Both a symlink and a real stock file exist — run `ra_on.sh` to fix |
| `MISSING` | `_RA_Cores/<name>.rbf` is not present; run `ra_update.sh` |
| `NONE` | Neither stock nor RA file is in the expected folder |

## Pull the latest odelot binary + cores

```sh
/media/fat/Scripts/ra_update.sh
```

Queries GitHub for every `odelot/*_MiSTer` repo, downloads the latest
release assets into `_RA_Cores/`, and updates `_RA_Cores/.manifest`.

- Known cores update silently when the release tag changes.
- **New** cores (systems odelot publishes after your install) prompt for
  confirmation before being added. Answer `y` to adopt, anything else to
  skip. Skipped systems will be offered again on the next run.

After updates, run `ra_on.sh` again if RA mode was on, so the new
binary / cores are actually in effect.

## After running `update_all`

If `update_all` pulled fresh stock `.rbf` files while RA mode was on,
`ra_status.sh` will show `DIRTY` for the affected cores. Fix with:

```sh
/media/fat/Scripts/ra_on.sh
```

`ra_on.sh` is idempotent and will re-stash the new stock file, leaving
the symlink in place.

If `update_all` rewrote `/media/fat/MiSTer` with the upstream stock
binary, the next reboot's auto-restore hook will replace it with
`_RA_Cores/MiSTer.ra`. You can force it immediately without rebooting by
running `ra_on.sh` too.

## Emergency rollback of the main binary

```sh
/media/fat/Scripts/ra_rollback_binary.sh
```

Restores `/media/fat/MiSTer.stock` over `/media/fat/MiSTer`, strips the
boot auto-restore hook, and reboots. Use if an odelot binary update
breaks something and you need the stock MiSTer experience back.

Your cores are untouched by this; if you want stock cores back too, run
`ra_off.sh` first (before rolling back the binary).

## Removing the toolkit entirely

```sh
/media/fat/Scripts/ra_off.sh              # restore stock cores
/media/fat/Scripts/ra_rollback_binary.sh  # restore stock binary + reboot
# after reboot:
rm -rf /media/fat/_RA_Cores
rm /media/fat/MiSTer.stock
rm /media/fat/retroachievements.cfg
rm /media/fat/achievement.wav
rm /media/fat/Scripts/ra_*.sh
```

The boot hook is already stripped by `ra_rollback_binary.sh`.
